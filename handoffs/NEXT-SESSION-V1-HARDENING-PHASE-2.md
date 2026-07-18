# Next session - V1 hardening phase 2: bounded engine search and the typed grading seam

Use Claude Sonnet at medium reasoning for this task.
This document is a complete execution plan.
It does not require another design interview.

## Starting point

The expected starting commit is `3e395c1` (`Harden training card reconciliation and review UI`).
At planning time `main` was clean and exactly synchronized with `origin/main`.

Verify this before changing anything:

```bash
git status --short --branch
git log -1 --oneline
git fetch origin && git rev-list --left-right --count origin/main...HEAD
```

The last command must print `0	0`.

This checkout contains no physical `AGENTS.md`.
Do not create one to satisfy any instruction that references it.
Treat the repository rules supplied in your session prompt as authoritative and record the missing physical file in the devlog, exactly as the previous session did.

## Treat as finished

The first V1 hardening slice is complete and must not be replanned.
That includes the classification symbols, the exact pre-move FEN for training cards, learner-owned report filtering, transactional reconciliation, the `v5_trainingIndexes` migration, `TrainingCardSynchronizer` readiness and generation safety, the Dashboard queue snapshot and backfill, and the stale-card removal.
Only revisit those if you find a concrete regression through inspection or a failing test.

## Verified diagnosis

Every fact below was reproduced or read directly during the planning session.
Facts marked `reproduced` came from a throwaway harness that linked the real `EngineKit` package and drove real in-process Stockfish.
The harness lived outside the repository and was not committed.

### F1 - `searchOneShot` arms its waiter after sending `go` (reproduced)

`EngineService.searchOneShot` is at `App/Sources/Chessanto/Analysis/EngineService.swift:289`.
It sends `await engine.go(movetimeMilliseconds:)` at line 293.
It only installs the waiting continuation afterwards, at line 315 inside `awaitBatchSearch`.

`EngineService.routeBatch` is at line 118.
Its `.bestMove` branch at lines 125 through 127 calls `batchContinuation?.resume()` and then clears the field.
When the terminating bestmove is routed before any continuation exists, that optional chain is a silent no-op and nothing records that the search already finished.
The continuation installed a moment later is therefore never resumed.

The planning harness measured the terminating bestmove arriving `0.000s` after `await engine.go(...)` returned, on a position with no legal moves.
An ordinary midgame position measured `0.114s`.
The window is real and is at its narrowest exactly on the positions practice grading reaches.

This is an unbounded hang, not a slow path.
There is no timeout anywhere in `searchOneShot` or `awaitBatchSearch`.

### F2 - engine updates are stamped with the generation at delivery time (reproduced)

`AnalysisEngine`'s listener task is at `Packages/EngineKit/Sources/EngineKit/AnalysisEngine.swift:66`.
Line 72 reads `let gen = await self.generation` once per delivered response and stamps both `.info` and `.bestMove` with it.
That is the generation current when the update is *delivered*, not the generation the search was *started* under.

`setPosition` at line 107 tries to close this window by waiting for an in-flight search to acknowledge its stop.
That wait only runs `if isSearching`, and `markSearchEnded` at line 95 clears `isSearching` when the bestmove is processed.
Trailing `info` responses that are still in flight after that point are therefore stamped with the next search's generation and pass every downstream generation check.

The planning harness reproduced this directly.
It ran a bounded search on a midgame position, then a bounded search on a stalemate position with no legal moves.
In two of three runs the stalemate search accepted a scored line that the stalemate position cannot produce.
One run recorded `rank=2 cp=-43 pv=d7d6 b1c3 f8e7`.
That is verbatim the final rank-2 line of the *previous* midgame search.
The third run was clean.

This is silent cross-position data contamination.
It is nondeterministic, which is why no offline test has ever caught it.
The same path writes `AnalysisRecord` rows during batch analysis, so a contaminated line can be persisted as a game's stored evaluation.

### F3 - terminal positions return no scored analysis (reproduced)

Stockfish answers a position with no legal moves with `bestmove (none)` and emits only unscored `info` lines.
The harness measured `infos=5 scoredInfos=0 bestmove=(none)` for a checkmated position and `infos=4 scoredInfos=0 bestmove=(none)` for a stalemate.

`EngineService.runCoachEvaluateSearch` at line 363 does not treat this as a distinct case.
`BatchCollector` records unscored infos as normal, so `infos.first` at line 368 usually succeeds and yields a result whose `scoreCentipawns` and `mateIn` are both nil.
That flows into training grading as a completely unknown score.

### F4 - the coach and training FIFO leaks a hung search forever

`coachEvaluate` is at line 332.
Lines 353 through 361 wrap the real work in an unstructured `Task` and chain `coachEvaluateTail` onto it.
Cancelling the calling task does not cancel that unstructured work task.
If the work task hangs on F1, `coachEvaluateTail` never completes, and every later coach evaluation, chat tool call, and training evaluation queues behind it for the remaining lifetime of the process.

One wedged practice grading therefore disables Coach chat and report narration as well.

### F5 - the documented stop-wait duration in the backlog is wrong

`handoffs/NEXT-SESSION-V1-HARDENING.md` line 56 states that `setPosition` advances after "a roughly three-second stop wait".
The actual loop at `AnalysisEngine.swift:111` iterates while `waited < 300`, sleeping 10 milliseconds per iteration.
The real bound is approximately 300 milliseconds.
The harness measured a healthy switch away from an infinite search at `0.011s`.
Correct this in the devlog rather than editing the historical backlog document.

### F6 - any cached ranked line is graded as a perfect answer

`DefaultTrainingMoveEvaluator.evaluate` is at `App/Sources/Chessanto/Training/TrainingDomain.swift:274`.
Line 280 returns `.strong` with zero loss when the attempted move matches the first move of *any* cached ranked line.
MultiPV is configured to 3 at `EngineService.swift:96`, so the rank-2 and rank-3 lines are cached too.
A rank-3 line that is 200 centipawns worse than rank 1 is currently reported as a strong move with no loss.

### F7 - finding a forced mate is graded as incorrect

`classify` at `TrainingDomain.swift:336` routes to `classifyMate` whenever *either* side of the comparison carries a mate score.
`classifyMate` at line 360 begins `guard let best else { return (.incorrect, nil) }`.
When the cached best line is centipawn-based and the learner's move delivers a forced mate, `best` is nil and the outcome is `.incorrect`.
The learner is told "That move misses the point of the position."

F3 compounds this.
A checkmating move that is not the cached rank-one move is searched on a position with no legal moves, returns an unscored result, and falls through line 344 to `.incorrect` as well.

### F8 - grading failure is a dead end and grading has no escape

`PracticeSessionView.swift:109` renders `.evaluating` as a spinner with the caption `Checking with the engine...` and no cancel affordance.
An F1 hang leaves that spinner on screen permanently.

`PracticeSessionViewModel.submit` at `App/Sources/Chessanto/Training/PracticeSessionViewModel.swift:195` maps any thrown error to `.failed`.
`PracticeSessionView.swift:55` renders `.failed` as a full-pane `ContentUnavailableView` that replaces the board and offers no retry.
A single transient engine error therefore destroys the whole practice session.

### F9 - the bounded-search path has no test coverage at all

`App/Tests/ChessantoTests/EngineServiceTests.swift` covers only `LiveGenerationFilter`, `BatchCollector`, and `EngineScoreNormalizer`.
None of them exercise completion, timeout, cancellation, or ordering.
`Packages/EngineKit/Tests/EngineKitTests/AnalysisEngineTests.swift` contains one structural test.

A live engine cannot be driven from XCTest in this project.
`Packages/EngineKit/Package.swift` records the reason at its `engine-smoke` target: chesskit-engine delivers responses through main-thread run-loop notifications, which XCTest does not guarantee.
This constraint drives the architecture below.

## In scope

1. Stamp engine updates with the generation the search actually started under, and drop updates that belong to no active search.
2. Replace the loose `batchCollector`, `batchGeneration`, and `batchContinuation` fields with one bounded-search coordinator that completes exactly once.
3. Arm the waiter before `go` is sent, and add a finite timeout, correct cancellation, late-result rejection, and typed errors.
4. Make `coachEvaluate` cancellation-correct so a cancelled or failed call cannot wedge the FIFO.
5. Introduce `WhitePerspectiveScore` and `TrainingPositionRequest` as the typed training engine boundary.
6. Short circuit terminal positions with `ChessCore` before any engine search.
7. Grade cached lower-ranked lines against rank one using the documented thresholds.
8. Make a grading failure recoverable instead of terminal.
9. Extend `engine-smoke` with live assertions for generation isolation and terminal positions.

## Out of scope

Do not start any of the following.
They remain open V1 work and the final checklist must not claim them.

- The full deep `Training` module, `PracticeScope`, `TrainingLesson`, `TrainingReconciliation`, and `PracticeFeedback` types sketched in `handoffs/NEXT-SESSION-V1-HARDENING.md`.
- Moving persistence mapping out of `TrainingDomain.swift`, and removing its `Persistence` import.
- Replacing `ReviewScheduling` with a concrete `ReviewScheduler` over typed `ReviewProgress`.
- The full `PracticeSessionViewModel` render-state machine.
- Non-disclosing incorrect and inaccurate feedback copy, and the distinct Reveal state.
- Duplicate-submit rejection.
- Recording review decisions for Reveal and Skip.
- Dashboard and practice presentation ownership, and nested sheets.
- The 900-point replay and practice layout.
- Contrast, target size, keyboard, focus, announcement, reduced-motion, and native capture coverage.
- README and version alignment.
- Promotion moves in practice, which currently submit a four-character UCI string with no promotion suffix at `PracticeSessionViewModel.swift:113`.

Also do not do the following.

- Do not change `RankedLine` in `Packages/AnalysisKit/Sources/AnalysisKit/ReportInput.swift`.
  It is `Codable` and its encoded form is persisted in `trainingCard.rankedLinesJSON`, so a shape change would silently invalidate existing rows.
- Do not change `EngineToolResult` or anything else in `CoachKit`.
  `CoachVerifier` depends on it and the grounding harness gates on it.
- Do not redesign the `EngineKit` public interface beyond the generation-stamping fix.
- Do not add a `TrainingKit` package.
- Do not modify migrations `v1` through `v5`, and do not add a new migration.
  This slice needs no schema change.
- Do not modify `CHANGELOG.md` or any generated file.
- Do not change the forced-light warm-neutral and brass visual identity, the board, the pieces, or the app icon.

## Fixed architectural decisions

### The coordinator lives in the App target, not in EngineKit

`EngineKit` cannot be tested against a live engine under XCTest, per F9.
The bounded-search lifecycle is therefore owned by a new engine-free type in the App target, where `BatchCollector` and `LiveGenerationFilter` already live and are already unit-tested.
The coordinator never imports the engine.
It is driven entirely by method calls, so every lifecycle test runs deterministically with no Stockfish process.

Create `App/Sources/Chessanto/Analysis/BoundedSearch.swift`.

```swift
enum EngineSearchError: Error, Equatable {
    case timedOut(milliseconds: Int)
    case cancelled
    case noAnalysis
    case engineUnavailable(String)
}

/// Owns exactly one bounded search: collection, exactly-once completion,
/// timeout, cancellation, and rejection of updates from other generations.
@MainActor
final class BoundedSearchSession {
    let generation: Int
    init(generation: Int)

    /// Records an info if it belongs to this session and it is still open.
    func record(_ info: AnalysisEngine.EngineInfo)

    /// Marks the search finished. Safe to call before, during, or after a
    /// caller begins awaiting, and safe to call more than once.
    func complete(generation: Int)

    /// Resolves the session with a failure exactly once.
    func fail(_ error: EngineSearchError)

    /// Awaits completion. Returns immediately if the search already
    /// completed before this was called.
    func value() async throws -> [AnalysisEngine.EngineInfo]
}
```

The latch is the whole point.
`complete` must set a stored outcome even when no continuation is installed yet, and `value()` must check that stored outcome before suspending.
This is what makes F1 impossible to reproduce.

### Ordering rule

`EngineService.searchOneShot` must construct the session and assign it to the active-session field **before** it sends `go`.
The generation comes from `setPosition`, which already precedes `go`, so the sequence becomes: `setPosition`, create session, install session, `go`, await.

Never send `go` while no session is installed.

### Timeouts

Every bounded search carries a deadline derived from its requested movetime.

```swift
let deadlineMilliseconds = movetimeMilliseconds * 4 + 3000
```

The multiplier absorbs a loaded machine and the additive term absorbs process scheduling.
For `.fast` this is 3400 ms, for `.standard` 4400 ms, for `.deep` 11000 ms, and for the 500 ms coach and training search 5000 ms.
On expiry the session fails with `.timedOut`, the engine is told to stop, and the active session is cleared so later updates are dropped.

Do not make the timeout configurable through user settings.
Do expose it as an injectable parameter with the default above, so tests can use a 50 ms deadline without sleeping.

### Cancellation

`searchOneShot` must remain cancellable and must always leave the service usable.

On cancellation the session fails with `.cancelled`, `engine.stop()` is sent, and the active session is cleared.
The bestmove that eventually terminates the stopped search must be dropped rather than resuming anything, which the generation check plus the cleared session field both guarantee.

`coachEvaluate` must be fixed so the caller's cancellation reaches the work.
Replace the unstructured `Task` with a form that propagates cancellation, and ensure `coachEvaluateTail` is always resolved on every exit path, including throw and cancellation.
Keep the FIFO guarantee that M7 added.
That guarantee exists because `searchOneShot` uses single shared fields, and the live `coach-grounding` concurrent probe is the only thing that has ever caught a regression in it.

### Late-result rejection

Two independent gates must both hold.

The engine-side gate is the F2 fix.
In `AnalysisEngine`, add a private `searchGeneration` that `goInfinite`, `go(depth:)`, and `go(movetimeMilliseconds:)` set to the current `generation`, and that the bestmove path clears to a sentinel value of `0`.
The listener task must stamp updates with `searchGeneration` instead of `generation`.
Updates that arrive while no search is active are stamped `0` and every existing generation comparison then rejects them, because `setPosition` returns generations starting at `1`.

The service-side gate is the session identity.
`route` must ask the active session whether an update belongs to it, and a session that has already resolved must ignore everything.

Both gates are required.
The engine-side gate is what actually stops cross-position contamination, and the service-side gate is what stops a resolved session from being mutated.

### Terminal positions never reach the engine

Detect them with `ChessCore` before searching.

`ChessGame.replayLine(fromUCI:startingFEN:)` returns `ReplayedMove.isCheckmate`, derived from actually playing the move rather than from notation, per `Packages/ChessCore/Sources/ChessCore/ChessGame.swift:276`.
When the attempted move reports `isCheckmate`, the mover delivered mate and the result is `WhitePerspectiveScore.mate` oriented to the mover, with no engine call at all.

For stalemate, build `ChessGame(startingFEN: resultingFEN)` and check whether any occupied square of the side to move has a legal destination.
No legal moves and no check means stalemate, which scores `.centipawns(0)`.

This removes the F3 failure mode from the hot path entirely and makes both cases deterministic and testable.
`.noAnalysis` remains as a typed error for a genuine engine anomaly.

### The typed score

Create `App/Sources/Chessanto/Training/WhitePerspectiveScore.swift`.

```swift
enum WhitePerspectiveScore: Sendable, Equatable {
    case centipawns(Int)
    case mate(Int)
}

struct TrainingPositionRequest: Sendable, Equatable {
    let preMoveFEN: String
    let attemptedMoveUCI: String
}
```

The type cannot represent centipawns and mate at once, which is the defect behind F7.

Give it one conversion helper from the persisted pair, used to read `RankedLine`:

```swift
init?(scoreCentipawns: Int?, mateIn: Int?)
```

Mate wins when both are present, and the initializer returns nil when both are absent.
This keeps `RankedLine` unchanged while making every comparison total.

Replace `TrainingEngineEvaluation` with `WhitePerspectiveScore`.
Change the evaluator seam to:

```swift
typealias EvaluatePosition = @Sendable (TrainingPositionRequest) async throws -> WhitePerspectiveScore
```

`EngineService.trainingEvaluationAfterMove` at `EngineService.swift:384` becomes `evaluateTrainingPosition(_:)` returning `WhitePerspectiveScore`.
It must not route through `coachEvaluate`, because the training domain should not be coupled to the Coach tool interface.
It must still pass through the same FIFO chokepoint and the same `searchOneShot`, so the single-engine invariant holds.

Update both production call sites at `App/Sources/Chessanto/GameReplayView.swift:235` and `App/Sources/Chessanto/Dashboard/DashboardView.swift:175`.

### Grading rules

Comparison is always in mover perspective.
Orient by negating the white-perspective value when the mover is Black, which is what `classify` already does at `TrainingDomain.swift:349`.

Keep the documented centipawn thresholds unchanged.
Strong is a loss of 30 or less, playable is 31 through 90, inaccurate is 91 through 220, and incorrect is above 220.

Replace F6's blanket acceptance.
When the attempted move matches the first move of a cached ranked line, grade that cached line's own score against the rank-one score with the same thresholds, and do not call the engine.
Rank one matching itself still yields a loss of 0 and therefore `.strong`.

Replace F7's mate handling with total comparison over `WhitePerspectiveScore`.

- Mover has mate and best had mate: compare distance, and a shorter or equal distance is `.strong`.
- Mover has mate and best was centipawns: `.strong`, because a forced mate is never worse than any centipawn evaluation.
- Best had mate and mover has centipawns: the forced win was lost, so `.inaccurate` when the mover's centipawn score is still clearly winning, and `.incorrect` otherwise.
- Mover is now being mated: `.incorrect`.

Use a shared oriented comparison so the Black-to-move sign convention is applied in exactly one place.

### Recovery semantics

A grading failure must not destroy the session.

Add a non-blocking error to the prompt state rather than routing engine errors to `.failed`.
`.failed` stays reserved for a failure to load the lesson at all, which is what `load()` already uses at `PracticeSessionViewModel.swift:94`.

On a thrown `EngineSearchError` during `submit`, return to the prompt for the same card, keep the board and the card intact, do not record an attempt, do not advance the scheduler, and surface a short retryable message.
`.timedOut` should read as a timing problem rather than a wrong answer.
Use `DesignColors.error`, which exists at `App/Sources/Chessanto/DesignSystem/DesignColors.swift:19`.

Do not build a full state machine here.
Add the minimum needed so a bounded-search failure is survivable.

## Implementation order

Work strictly in this order.
Each step is red first, then green, then a small refactor, and each ends at a gate you must not proceed past.

Run `xcodegen generate` after adding any new file, because `Chessanto.xcodeproj` is generated and gitignored.

### Step 0 - Data safety and baseline

Follow the process the previous session recorded in the `V1 hardening execution` section of `devlogs/2026-07-18.md`.

```bash
SANDBOX_DB="$HOME/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite"
ls -l "$SANDBOX_DB"
cp "$SANDBOX_DB" "$SANDBOX_DB.before-v1-hardening-phase2-$(date +%Y%m%d-%H%M%S)"
```

Never mutate the live sandbox database during development or QA.
Never treat `$HOME/Library/Application Support/Chessanto/chessanto.sqlite` as production data.
That non-sandbox path is stale and only reached migration `v3_m8Settings`.

For every native run, copy the backup to a disposable file under the app container's temporary area and launch with both opt-in variables, which `GameStore.defaultStore(environment:)` requires together at `Packages/Persistence/Sources/Persistence/GameStore.swift:45`:

```bash
QA_DB="$HOME/Library/Containers/com.chessanto.app/Data/tmp/chessanto-qa-$(date +%H%M%S).sqlite"
cp "$SANDBOX_DB" "$QA_DB"
CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1 CHESSANTO_DATABASE_PATH="$QA_DB" open -n <path to built app>
```

Record the backup path and every disposable path in the devlog.

Capture the baseline before touching code:

```bash
swift test --package-path Packages/EngineKit
xcodebuild test -scheme Chessanto -destination 'platform=macOS' 2>&1 | tail -20
```

Gate: the backup exists, the baseline app suite passes, and you have recorded its test and suite counts.

### Step 1 - Engine-side generation isolation

Red: extend `Packages/EngineKit/Sources/engine-smoke/main.swift` with a live assertion that fails on today's code.
Run a `go(movetimeMilliseconds: 500)` search on a normal midgame position, then immediately run a bounded search on `7k/5Q2/6K1/8/8/8/8/8 b - - 0 1`, which is a stalemate with no legal moves.
Assert that no `info` attributed to the second search's generation carries a centipawn or mate score, and assert its bestmove is `(none)`.
Repeat that pair at least five times in the same process, because the planning harness saw contamination in two of three runs.

```bash
swift run --package-path Packages/EngineKit engine-smoke
```

This must fail before the fix.
If it passes on the first attempt, raise the repeat count and confirm you see a failure, because the defect is timing dependent.

Green: add `private var searchGeneration = 0` to `AnalysisEngine`.
Set it to `generation` in all three `go` methods.
Reset it to `0` in `markSearchEnded`.
Change the listener task at line 72 to stamp with `searchGeneration`.

Note the ordering that already exists in that listener.
Line 72 reads the stamp once at the top of each iteration, before the `switch`.
The terminating bestmove therefore still carries its own search's generation even though `markSearchEnded` resets the field a moment later in the same iteration.
Preserve that ordering, because a bestmove stamped `0` would be dropped by every downstream check and would recreate F1.

Refactor: update the doc comment on `setPosition` so it describes what the code now actually guarantees, and note the real 300 ms bound rather than implying something stronger.

Gate:

```bash
swift test --package-path Packages/EngineKit
swift run --package-path Packages/EngineKit engine-smoke
```

Both must pass, and `engine-smoke` must still exit 0 on all of its pre-existing assertions.

### Step 2 - The bounded-search coordinator

Red: create `App/Tests/ChessantoTests/BoundedSearchTests.swift` with these exact test names.

- `completionBeforeAwaitStillResolves`
- `completionResolvesExactlyOnce`
- `timeoutFailsWithTypedError`
- `cancellationFailsWithTypedError`
- `lateUpdatesAfterResolutionAreIgnored`
- `updatesFromAnotherGenerationAreIgnored`
- `emptyResultsSurfaceNoAnalysis`
- `resolvedSessionIgnoresRepeatedFailures`

`completionBeforeAwaitStillResolves` is the direct regression test for F1.
It must call `complete(generation:)` before it ever calls `value()`, and then require that `value()` returns without suspending indefinitely.

Green: implement `BoundedSearch.swift` as specified above.

Gate:

```bash
xcodegen generate
xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/BoundedSearchTests
```

### Step 3 - Rewire EngineService onto the coordinator

Green: delete the `batchCollector`, `batchGeneration`, and `batchContinuation` fields and `awaitBatchSearch`.
Install one `activeSearch: BoundedSearchSession?`.
Rewrite `searchOneShot` to create and install the session before `go`, then await it with a deadline.
Rewrite `route` and `routeBatch` to dispatch on the active session.
Keep `routeLive` and the live debounce, pause, and resume behavior exactly as it is.

Fix F4 in `coachEvaluate`.
Propagate cancellation into the queued work, and resolve `coachEvaluateTail` on every exit path.

Add `evaluateTrainingPosition(_:)` and remove `trainingEvaluationAfterMove`.

Keep `BatchCollector` as the rank-collection helper, used by the session.
Its existing tests must continue to pass unchanged.

Gate:

```bash
xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/EngineServiceTests -only-testing:ChessantoTests/BoundedSearchTests
swift run --package-path Packages/CoachKit coach-grounding
```

`coach-grounding` includes the live concurrent-evaluate probe that is the only real check on the FIFO guarantee.
It must exit 0.

### Step 4 - The typed score

Red: add `App/Tests/ChessantoTests/WhitePerspectiveScoreTests.swift` with these exact test names.

- `mateWinsOverCentipawnsWhenBothArePresent`
- `absentValuesProduceNoScore`
- `blackToMoveOrientationNegatesBothForms`

Green: create `WhitePerspectiveScore.swift` with the type, `TrainingPositionRequest`, the failable initializer, and one oriented-comparison helper.

Refactor: replace `TrainingEngineEvaluation` throughout and update the two production call sites and every existing test construction site.

Gate:

```bash
xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/WhitePerspectiveScoreTests
```

### Step 5 - Grading correctness

Red: add these exact test names to `App/Tests/ChessantoTests/TrainingDomainTests.swift`.

- `cachedLowerRankedLineIsGradedAgainstRankOne`
- `cachedRankOneRemainsStrongWithoutEngineSearch`
- `deliveringMateIsStrongEvenWhenCachedBestIsCentipawns`
- `slowerWinningMateIsStillCredited`
- `losingAForcedMateIsNotStrong`
- `walkingIntoMateIsIncorrect`
- `stalematingMoveIsGradedWithoutEngineSearch`
- `terminalPositionsNeverCallTheEngine`
- `blackToMoveMateOrientationIsCorrect`
- `unavailableCachedScoreDoesNotCrashGrading`

`terminalPositionsNeverCallTheEngine` must inject an evaluator closure that fails the test if it is ever invoked.

Keep the four existing tests in that file passing.
`cachedTopLineIsAcceptedWithoutEngineSearch` must keep passing unchanged, because rank one still grades strong without an engine call.

Green: implement the terminal-position short circuit, the cached-line comparison, and the total mate comparison in `DefaultTrainingMoveEvaluator`.

Gate:

```bash
xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/TrainingDomainTests
```

### Step 6 - Recoverable grading failure

Red: add these exact test names to `App/Tests/ChessantoTests/PracticeSessionViewModelTests.swift`.

- `engineTimeoutReturnsToPromptWithRetryableMessage`
- `engineTimeoutDoesNotRecordAnAttemptOrAdvanceScheduling`
- `retryAfterEngineTimeoutCanStillGradeTheSameCard`

Green: add the non-blocking error to the prompt path in `submit`, and render it in `PracticeSessionView` alongside the existing prompt controls.

Keep the existing three tests in that file passing.

Gate:

```bash
xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/PracticeSessionViewModelTests
```

All six steps are in scope and none of them is optional.
Do not descope in order to finish faster.

If you genuinely run out of room, stop at the last **completed** gate rather than leaving a step half-built.
A step is complete only when its tests pass and its gate command is green.
Then record exactly which steps landed, commit the finished work, and write the remainder into the phase-3 plan.
Never leave the repository at a state where a gate was skipped or a test was weakened to make it pass.

## Full verification

Run all of these before committing.

```bash
xcodegen generate
swift test --package-path Packages/ChessCore
swift test --package-path Packages/AnalysisKit
swift test --package-path Packages/EngineKit
swift test --package-path Packages/ChessComKit
swift test --package-path Packages/CoachKit
swift test --package-path Packages/Persistence
xcodebuild test -scheme Chessanto -destination 'platform=macOS'
swift run --package-path Packages/EngineKit engine-smoke
swift run --package-path Packages/CoachKit coach-grounding
scripts/release-build.sh
git diff --check
```

The app suite passed 31 tests across 13 suites at `3e395c1`.
Your final run must exceed that count and must not lose any suite.

## Production-aligned E2E reproduction and acceptance

Do this against a Release build and a disposable database copy, using the Step 0 procedure.

The existing native tooling is `scripts/axprobe.swift` for reads, `scripts/axclick.swift` for presses, `scripts/axclickat.swift` for real coordinate clicks, and `scripts/capture-window.swift` for Chessanto-window captures.
Reads and presses work without the app frontmost.
Sheets do not render while backgrounded, so activate the app before capturing any practice state.

Reproduce before fixing:

1. Open an analyzed game with key moments and start practice from the Report.
2. Submit a legal move that is not any cached ranked line, so grading reaches the engine.
3. Record how long the `Checking with the engine...` state persists and confirm feedback eventually arrives.
4. Note that no cancel affordance exists.

Accept after fixing:

1. The same submission returns bounded feedback, and the `Checking with the engine...` state always terminates.
2. A submission that matches a rank-two or rank-three cached line no longer reports a strong move with zero loss.
3. Run a full `Analyze` pass on a real game and confirm it completes and persists, so the rewired batch path is exercised end to end rather than only in tests.
4. Open Coach chat on the same game and send one turn, confirming that the FIFO still serves coach evaluations after training evaluations have run in the same process.
5. Capture the practice prompt and feedback states with the app definitely activated.

Every screenshot must visibly contain the claimed Chessanto state.
The previous audit found six screenshot files that actually captured a different foreground application, and those were rejected as evidence.
Screenshot PNGs stay local and uncommitted.

The mate-grading fix cannot be reached reliably through ordinary native play, because it needs a cached card whose position admits a mate that is not the rank-one move.
Cover it with the Step 5 tests and say so explicitly rather than claiming native coverage you did not obtain.

## Documentation, review, commit, and push

Update `handoffs/HANDOFF.md`.
Add a section describing the phase-2 slice, and state plainly which V1 hardening items remain open.

Append to `devlogs/2026-07-18.md` if you work on that date, or create `devlogs/<today>.md` if the date has rolled over.
Record the reproduction evidence, the engine facts you confirmed, the F5 correction about the 300 ms stop wait, the exact commands, the test counts, the backup path, every disposable database path, and the missing physical `AGENTS.md`.

Write `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` describing the next slice.
The obvious candidate is the full practice render-state machine together with non-disclosing feedback and the distinct Reveal state, because Step 6 deliberately touches only the recovery path.

That phase-3 document must also carry forward the two repository-hygiene items below.
Both were deliberately excluded from phase 2 because changing repository-wide instruction files during an implementation slice adds risk for no benefit.
Do not start either one in this session.
Record them as scoped, ready-to-execute follow-ups.

#### Follow-up A - Add a project-level `CLAUDE.md`

This repository has no project-level `CLAUDE.md` and no `AGENTS.md`.
Every durable rule currently reaches the agent through the session prompt instead of through the checkout.
The `V1 hardening execution` section of `devlogs/2026-07-18.md` already records the consequence, noting that the missing physical file left the prompt-supplied rules authoritative.
That is fragile, because a rule that is only ever pasted is a rule that will eventually be forgotten.

The phase-3 plan should specify capturing at least the following in a project `CLAUDE.md`.

- The forced-light warm-neutral and brass visual identity, and the rule that the board, pieces, app icon, and Chessanto identity are not to be redesigned.
- The rule that green stays confined to the board arrow and the reserved move-classification colors, and never enters application chrome.
- The native database-safety procedure, including the sandbox path, the backup step, the disposable-copy step, and the two required opt-in environment variables.
- The standard verification command set, including the per-package suites, the app suite, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh`.
- The rule that `xcodegen generate` must run after adding or removing files, because `Chessanto.xcodeproj` is generated and gitignored.
- The documentation rules already in force, which are one full sentence per physical line in Markdown, never the em dash character, no modification of `CHANGELOG.md` or generated files, and no agent co-author on commits.

Note explicitly that this is a documentation change only.
It must not alter behavior, and it must not silently become a place to invent new rules that the project has not actually agreed.

#### Follow-up B - Author a root `CONTEXT.md`

The project now has a substantial domain vocabulary that exists only as prose spread across roughly one hundred kilobytes of `handoffs/HANDOFF.md` and the devlogs.
Representative terms include ply, source ply, pre-move FEN, key moment, ranked line, MultiPV rank, generation, bounded search, white-perspective score, reconciliation, mastery state, review scheduling, and learner-owned filtering.

Four installed skills read a root `CONTEXT.md` when one exists, which are `tdd`, `diagnosing-bugs`, `improve-codebase-architecture`, and `ask-matt`.
Each of them guards the read with an explicit existence check, so the absence of the file is currently a missed opportunity rather than a defect.

Use the `domain-modeling` skill to author it, and follow its `CONTEXT-FORMAT.md`.
Do not hand-roll a format.
Do not use `setup-matt-pocock-skills` for this, because that skill only records where domain documents live and never writes their content.

The payoff is compounding rather than immediate.
It improves every later session's naming and mental model, so schedule it once V1 hardening is closed rather than in the middle of it.

Run `mattpocock-skills:code-review` over the diff before committing, using this document as the spec axis.
Do not skip it because the tests pass, since neither the F1 race nor the F2 contamination was catchable by the offline suite.

Commit and push together with the documentation:

```bash
git add -A
git commit
git push origin main
```

Write the commit message in the style of the existing history.
Do not add an agent co-author.
Do not sign the commit as a co-author under any name.

Every full sentence in a Markdown file you write or substantially edit must occupy its own physical line.
Never use the em dash character.

## Final checklist

Tick these only when they are literally true.

- [ ] `main` started clean at `3e395c1` and the backup of the live sandbox database exists.
- [ ] `engine-smoke` gained a repeated live generation-isolation assertion, and that assertion failed before the fix.
- [ ] `AnalysisEngine` stamps updates with the search generation and drops updates that belong to no active search.
- [ ] `BoundedSearchSession` completes exactly once, latches completion that arrives before any waiter, and is covered by all eight named tests.
- [ ] `searchOneShot` installs its session before sending `go`.
- [ ] Timeout, cancellation, and late-result rejection have typed errors and passing tests.
- [ ] `coachEvaluate` propagates cancellation and always resolves its FIFO tail.
- [ ] `WhitePerspectiveScore` replaced the two-optional engine score at the training boundary.
- [ ] Terminal positions are resolved by `ChessCore` and never reach the engine.
- [ ] Cached lower-ranked lines are graded against rank one rather than accepted as strong.
- [ ] Delivering a forced mate grades as strong even when the cached best line was centipawn-based.
- [ ] A bounded-search failure during grading is survivable rather than terminal.
- [ ] All package suites, the app suite, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` pass.
- [ ] Native acceptance ran against a disposable database and the live database was never mutated.
- [ ] Handoff, devlog, and the phase-3 plan are written and committed with the code.
- [ ] The phase-3 plan carries forward Follow-up A, which is the project-level `CLAUDE.md`.
- [ ] The phase-3 plan carries forward Follow-up B, which is the root `CONTEXT.md` authored with `domain-modeling`.

The following remain open V1 work and are **not** complete after this session.

- [ ] The deep `Training` module, typed practice scopes, and the concrete `ReviewScheduler`.
- [ ] The full `PracticeSessionViewModel` render-state machine.
- [ ] Non-disclosing incorrect feedback, the distinct Reveal state, and duplicate-submit rejection.
- [ ] Review decisions for Reveal and Skip.
- [ ] Dashboard and practice presentation ownership without nested sheets.
- [ ] The 900-point replay and practice layout.
- [ ] Contrast, target size, keyboard, focus, announcement, and reduced-motion coverage.
- [ ] Promotion moves in practice.
- [ ] README and version alignment.
- [ ] A project-level `CLAUDE.md`, which is Follow-up A.
- [ ] A root `CONTEXT.md`, which is Follow-up B.

## Recommended skills

The `mattpocock-skills` plugin is installed globally at user scope, so every skill below is available in a fresh session.
The plugin was installed from the `mattpocock` marketplace at version 1.2.0.

Use them in this order.

- `implement` to drive the plan overall.
  This document is the spec it should work from.
- `diagnosing-bugs` before Step 1 and Step 2.
  Reproduce F1 and F2 yourself against the live engine before you change either of them.
  Do not trust this document's reproduction as a substitute for your own.
- `tdd` for every step.
  Each step in this plan is already written red first, then green, then refactor, with exact test names.
- `codebase-design` for the two seams that matter: the `BoundedSearchSession` interface in Step 2 and the `WhitePerspectiveScore` boundary in Step 4.
  Both are deep-module decisions and the deep-module vocabulary is the right lens for them.
- `mattpocock-skills:code-review` before the final commit, which runs the Standards and Spec reviews in parallel.
  That is the same two-axis review the previous session used, recorded at the end of the `Final review hardening` section of `devlogs/2026-07-18.md`.
  Use this document as the spec axis.
  Do not skip it because the tests pass, since neither F1 nor F2 was catchable by the offline suite.

Note that `mattpocock-skills:code-review` and the built-in `/code-review` are different skills with the same short name.
Qualify it with the plugin prefix so you get the two-axis review.

Do not run `setup-matt-pocock-skills` in this session.
It is an interactive per-repo setup interview covering issue trackers and triage labels, none of which this slice needs, and it would add unrelated files to the repository.

No UI design skill is required.
Step 6 adds one inline error message inside the existing design system and introduces no new visual direction.
If you find yourself designing anything beyond that message, you have left the scope of this plan.
