# Next session - v1 hardening and learning-loop refinement

Use GPT-5.5 at medium reasoning for this task.

## Prompt to paste into the next Codex task

Continue Chessanto from the current `main` branch.
The expected starting commit is `aaf6d98` (`Add active learning practice loop`), and `main` was clean and synchronized with `origin/main` at planning time.

Read these before changing code:

- The workspace-provided `AGENTS.md` instructions.
- `handoffs/HANDOFF.md`.
- The latest section of `devlogs/2026-07-18.md`.
- `handoffs/NEXT-SESSION-LEARNING-LOOP.md`.
- `handoffs/NEXT-SESSION-V1-HARDENING.md`.
- Every image in `handoffs/screenshots/learning-loop/`.

If a physical `AGENTS.md` is still absent from the checkout, do not create one just to satisfy this instruction.
Use the workspace-provided AGENTS instructions and record the missing physical file in the devlog.

Use the `implement` and `tdd` skills for execution.
Use `ui-ux-pro-max` together with the available frontend or interface-design skill for every UI and interaction change.
Use the `codebase-design` vocabulary and deep-module principles for the training and engine work.
Start every bug fix by reproducing it through the native app as closely as an end user experiences it.
Work in small tested slices.
Do not proceed past a failed verification gate.

Preserve the forced-light warm-neutral and brass visual identity.
Do not redesign the board, pieces, app icon, or Chessanto identity.
Do not introduce green into application chrome.
The existing green board arrow and reserved move-quality semantic colors may remain confined to the board and classification system.

## Short product diagnosis

Chessanto now has the feature set of a compelling v1, but the Active Learning Loop is still a tracer bullet rather than a release-hardened product loop.
The main problems are not missing spectacle or another large feature.
They are correctness, state ownership, discoverability, and acceptance reliability.

Historic analyzed games do not generate practice cards until their Report is rebuilt.
The Report can expose its Practice action before its untracked card-persistence task finishes.
Reanalysis can leave stale cards behind and preserve mastery even when the best answer changes.
The Dashboard captures a stale lesson array, does not refresh after practice, and can reopen the old card with old progression.
Malformed persisted card data can misalign the displayed card and the record being updated.

The current incorrect-feedback path reveals the answer immediately through both the best-move arrow and copy that names the best SAN.
This defeats recall and makes the explicit Reveal action redundant.
The strong-feedback path can reuse a report explanation about the original mistake, so a correct answer can be followed by prose describing a loss of winning chances.
Every cached MultiPV move is currently graded strong with zero loss, even when a lower-ranked cached line is outside the documented strong threshold.
Reveal and skip can count a card as completed without recording a review decision, leaving it immediately due while the completion screen implies success.

The bounded engine-search path also has a real continuation race.
`EngineService.searchOneShot` sends `go` before the batch continuation is installed.
A sufficiently fast `bestmove` can therefore be routed before anything is waiting for it.
The wait also has no finite timeout.
`AnalysisEngine.setPosition` eventually advances after a roughly three-second stop wait even if the old search has not acknowledged completion, despite its stronger generation-safety comment.

The visual direction is strong and should be protected.
The two screenshots that visibly show Chessanto confirm the warm-light identity, board quality, improved empty state, and stable sidebar actions.
However, six files named as Dashboard, Report, prompt, feedback, or completion states actually capture Codex in the foreground instead of the claimed Chessanto state.
Those files are not valid visual acceptance evidence.
The 900-point app capture also exposes a minimum-width conflict: a roughly 240-point sidebar leaves about 660 points for a detail view whose child columns require at least 420 plus 260 points.
The right pane can consequently become clipped or unsatisfiable at the supported minimum window size.

Measured token contrast also needs correction.
`DesignColors.textSecondary`, implemented as 60 percent primary text, measures approximately 4.02:1 to 4.22:1 across the app surfaces.
The brass accent `#A6791F` measures approximately 3.43:1 to 3.91:1 against the current light surfaces.
Both are below the 4.5:1 requirement when used for small normal text.
Keep the palette, but use accessible neutral and darker-brass tokens for text and interactive fills.

The external release story is also inconsistent.
`project.yml` still reports marketing version `0.1.0`.
`README.md` still describes mistake-derived practice and spaced repetition as future work even though the learning loop now ships.
The app can become an honest unsigned v1 build in this session.
Public distribution remains blocked on Developer ID signing and notarization credentials and is not authorized in this task.

## Ranked work items

1. Harden the bounded engine-search path so practice evaluation cannot miss completion or hang indefinitely.
2. Deepen the training module around reconciliation, fresh lesson loading, response grading, scheduling, and persistence.
3. Backfill cards from historic analyzed games and make Report practice readiness awaited, observable, and failure-aware.
4. Replace the current loose practice state with an explicit, cancellable state machine and correct incorrect, playable, reveal, retry, skip, and completion semantics.
5. Make Dashboard lessons personalized, fresh after dismissal, independent from stale captured arrays, and clear about due-now versus future reviews.
6. Fix the 900-point layout conflict, sheet stacking, control hierarchy, contrast, target sizes, keyboard flow, and accessibility announcements.
7. Add the missing domain, persistence, integration, state-machine, engine-orchestration, AX, and native screenshot acceptance coverage.
8. Align README, version metadata, handoff, devlog, local-data guidance, and the unsigned Release build with the completed v1 behavior.

## Fixed architectural direction

Do not create a new `TrainingKit` package in this session.
There is still one app consumer, so a new package would create visibility and dependency churn without a second real use.

Do not add a generic repository protocol.
The concrete `GameStore` already has an in-memory GRDB configuration through `GameStore()`, which is the local-substitutable test adapter.

Create one deep training module with a small caller-facing interface.
The preferred shape is:

```swift
struct Training {
    typealias EvaluatePosition = @Sendable (
        TrainingPositionRequest
    ) async throws -> WhitePerspectiveScore

    init(
        store: GameStore,
        evaluatePosition: @escaping EvaluatePosition
    )

    func reconcile(
        gameID: Int64,
        report: GameReport,
        input: ReportInput,
        at occurredAt: Date
    ) async throws -> TrainingReconciliation

    func lesson(
        _ scope: PracticeScope,
        at now: Date
    ) async throws -> TrainingLesson

    func respond(
        _ response: PracticeResponse,
        to cardID: Int64,
        at occurredAt: Date
    ) async throws -> PracticeFeedback
}
```

The exact type name may change if a clearer existing project term fits.
Preserve the three caller intents: reconcile verified report facts, load a lesson, and respond to a card.

Use a typed lesson scope instead of arbitrary captured loader closures:

```swift
enum PracticeScope: Sendable, Equatable {
    case due(username: String?, limit: Int)
    case any(username: String?, limit: Int)
    case game(gameID: Int64, sourcePly: Int?)
}
```

The training module should hide:

- Raw `TrainingCardRecord` and `TrainingAttemptRecord` values from SwiftUI callers.
- JSON encoding and decoding.
- Throwing validation of persisted enum values and ranked lines.
- Report-to-card conversion.
- Stale-card reconciliation.
- Due and fallback query differences.
- Legality and SAN conversion.
- Cached-line grading.
- Engine fallback.
- Mate and centipawn comparison.
- Review scheduling.
- Attempt insertion and progression update ordering.

Keep ephemeral presentation behavior in `PracticeSessionViewModel`.
This includes board selection, current lesson index, focus, hints shown, active error presentation, and session summary.

Move persistence mapping out of `TrainingDomain.swift`.
`TrainingDomain.swift` should no longer import `Persistence`.
Use a focused file such as `TrainingPersistenceMapping.swift` for throwing record conversion.

Replace the failable `compactMap` load with paired, throwing conversion.
Never keep raw records and decoded cards in parallel arrays that can have different counts.

Use a concrete pure `ReviewScheduler`.
Do not keep a `ReviewScheduling` protocol with one real implementation.
The scheduler should operate on typed `ReviewProgress` and return a typed `ReviewDecision`.
Pass one captured timestamp and an explicit `Calendar` through the whole review operation.
Use `Calendar.autoupdatingCurrent` in production and fixed calendars in tests.

Replace the two-optionals engine score with a type that cannot represent both centipawns and mate at once:

```swift
enum WhitePerspectiveScore: Sendable, Equatable {
    case centipawns(Int)
    case mate(Int)
}
```

Use a typed engine request:

```swift
struct TrainingPositionRequest: Sendable, Equatable {
    let preMoveFEN: String
    let attemptedMoveUCI: String
}
```

Production uses `EngineService`.
Tests use a deterministic closure or adapter.
Do not couple the training domain conceptually to CoachKit merely to reuse the Coach tool interface.

Do not rewrite the entire EngineKit public interface in this session.
Harden the bounded-search lifecycle with a focused internal module that owns collection, exactly-once completion, timeout, cancellation, and late-result rejection.
This is the correct depth for the current scope.
A wholesale UCI driver redesign is deferred.

## Fixed persistence decisions

Do not modify migrations `v1` through `v4`.
Add a forward-only `v5_trainingIndexes` migration.

Add indexes that support the actual queries:

- `trainingCard(dueAt, updatedAt)`.
- `trainingAttempt(cardId, attemptedAt)`.

Replace per-card best-effort upsert with one transactional game reconciliation.

Reconciliation must:

1. Validate and encode every candidate before writing anything.
2. Insert new source plies.
3. Update verified content for existing source plies.
4. Preserve mastery, due date, and attempts only when `preMoveFEN`, side to move, and rank-one best move are unchanged.
5. Reset progress when the best answer changes.
6. Delete cards that are absent from the latest audited report.
7. Let the existing cascade remove attempts tied to a changed or removed derived exercise.
8. Roll back the whole reconciliation if any candidate is invalid.

Deleting invalidated attempt history is intentional for this slice.
An attempt against a retired answer must not continue to count as mastery evidence.
Do not add retirement, revision-history, event-sourcing, or archive tables.

Replace the current three independent Dashboard reads with one snapshot read at a caller-supplied instant.
The snapshot should include:

- The limited due-card lesson.
- The exact total due-card count.
- A fallback lesson.
- The earliest future due date.
- Whether any card is still due now.

If a chess.com username is configured, Dashboard lesson queries should include only games where the username matches White or Black case-insensitively.
The Report may still practice an explicitly opened unmatched or imported study game.
When a user side is known for a game, generate cards only for that side's key moments.
When no side can be identified, use neutral practice copy such as `Find the strongest move.` rather than falsely saying `you`.

Persist only real move attempts in `trainingAttempt`.
Do not insert an empty-string move for Reveal or Skip.
Reveal and Skip should still apply an incorrect review decision so the card remains due now.

## Fixed grading decisions

Keep the documented centipawn thresholds:

- Strong: loss of 30 centipawns or less.
- Playable: loss of 31 through 90 centipawns.
- Inaccurate: loss of 91 through 220 centipawns.
- Incorrect: loss above 220 centipawns.

Do not automatically mark every cached MultiPV first move strong.
If the attempted move matches any cached line, grade it against rank one using the cached line's score.
Avoid the live engine search, but still apply the same outcome thresholds.

Keep mate values separate from centipawns.
Add explicit tests for:

- Preserving a winning mate with the same or nearly the same distance.
- Choosing a slower winning mate.
- Losing a forced mate.
- Finding a forced mate when the cached best score is centipawn-based.
- Escaping a mate sequence.
- Black-to-move sign orientation.
- Unavailable or inconsistent cached score data.

Strong feedback must describe the user's successful move.
It must not reuse prose whose subject is the original mistake.
A safe default is:

> You found Nf3.
> It matches the engine's top choice.

Playable feedback should name the user's move, show the stronger move, and quantify the verified difference when centipawn loss exists.

Incorrect and inaccurate feedback must not name the best SAN or draw the best-move arrow before Reveal.
They should restore the original position, describe only verified loss or a verified audited consequence, and offer Try again as the primary action.

Reveal should be a distinct state.
It should show the best move arrow, best SAN, and a short verified continuation derived from the cached rank-one UCI line with `ChessCore`.
It must not be represented as a fabricated incorrect `TrainingEvaluation`.

## Step-by-step implementation plan

### Step 0 - Safeguard local data and reproduce the current behavior

Confirm the repository and starting point:

```bash
git status --short --branch
git log -3 --oneline --decorate
git pull --ff-only
```

Locate the active sandbox database:

```bash
SANDBOX_DB="$HOME/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite"
NON_SANDBOX_DB="$HOME/Library/Application Support/Chessanto/chessanto.sqlite"
ls -l "$SANDBOX_DB" "$NON_SANDBOX_DB" 2>/dev/null || true
```

At planning time, the sandbox database had all migrations through `v4_trainingLoop`, seven games, 479 analysis rows, one manually seeded training card, and one attempt.
The non-sandbox database had only migrations through `v3_m8Settings` and no training tables.
The Release sandbox app uses the first path.
Do not inspect or mutate the second path as if it were production data.

Back up the sandbox database before launching changed code:

```bash
BACKUP_DB="$SANDBOX_DB.before-v1-hardening-$(date +%Y%m%d-%H%M%S)"
cp "$SANDBOX_DB" "$BACKUP_DB"
```

Do not use the user's live database as a disposable screenshot fixture.
Add a narrowly scoped `CHESSANTO_DATABASE_PATH` launch override to `GameStore.defaultStore()` and cover it with a test.
Use a QA database inside the app container's temporary area for native acceptance.

Build and launch the current Release app against a QA copy.
Reproduce these current behaviors before fixing them:

- Open Report and press Practice immediately after report construction.
- Complete a due card, dismiss practice, and observe the stale Dashboard action.
- Make an incorrect move and confirm that the best move is revealed before Reveal.
- Use Reveal and advance, then compare the completion copy with the card's due state.
- Resize the main window to 900 points and inspect the replay right pane.
- Capture the current screen with the app definitely activated.

Add or repair a window-scoped capture helper under `scripts/`.
It must activate Chessanto, identify the real Chessanto window, and capture that window instead of the whole Codex desktop.

Verification gate:

- The backup exists.
- The QA database is distinct from the live sandbox database.
- AX can read the real Chessanto window.
- The captured image visibly contains the claimed Chessanto state.
- The current bugs are recorded with before screenshots or AX output.
- No app code fix has been attempted before reproduction.

### Step 1 - Harden bounded engine search

Write failing tests for:

- Completion arriving before the waiter begins awaiting.
- Exactly-once completion.
- Timeout.
- Cancellation.
- Late bestmove after timeout.
- Empty info results.
- FIFO behavior for two bounded searches.

Replace the loose `batchCollector`, `batchGeneration`, and `batchContinuation` lifecycle with a focused bounded-search session or coordinator.
Create the waiter synchronously before sending `go`.
Make timeout and cancellation complete the request exactly once.
Stop the engine on cancellation or timeout.
Ignore late updates from the expired generation.
Return a typed error for timeout and empty results.

Make engine startup and stop acknowledgement finite.
Do not bump the generation and send a new position when the old search still has not acknowledged stopping.
Surface a recoverable engine-unavailable message instead of hanging.

Keep live-analysis pause and resume behavior intact.
Do not disturb the Coach FIFO guarantee.

Verification gate:

```bash
xcodegen generate
swift test --package-path Packages/EngineKit
xcodebuild test \
  -scheme Chessanto \
  -destination 'platform=macOS' \
  -only-testing:ChessantoTests/EngineServiceTests
swift run --package-path Packages/EngineKit engine-smoke
```

The live smoke test must finish.
A timed-out or cancelled bounded search must not poison the next engine request.

### Step 2 - Deepen the pure training policy

Split domain models, persistence mapping, evaluator policy, and session presentation into focused files.
Keep the external training interface small.
Remove `Persistence` from the pure domain file.

Implement:

- Typed engine requests and scores.
- Throwing card conversion.
- Cached-line grading against rank one.
- Exhaustive mate handling.
- Mover-perspective normalization.
- A concrete calendar-aware review scheduler.
- Neutral versus user-owned prompt metadata.
- Feedback copy that describes the attempted move rather than the original mistake.

Add tests at every threshold boundary and for both mover colors.
Add a real report-fixture card-generation test that asserts exact source plies and pre-move FENs.
Add user-side filtering tests.

Verification gate:

```bash
xcodebuild test \
  -scheme Chessanto \
  -destination 'platform=macOS' \
  -only-testing:ChessantoTests/TrainingDomainTests
```

The domain suite must be deterministic, engine-free, database-free, and independent of the system timezone.

### Step 3 - Add transactional reconciliation and queue snapshots

Add `v5_trainingIndexes`.
Do not edit `v4_trainingLoop`.

Implement one transactional reconciliation operation in `GameStore`.
Implement one queue snapshot read at a supplied `now`.
Replace the current persistence method that accepts an arbitrary attempt and arbitrary updated card.
The store must enforce attempt-to-card identity inside one transaction.
Capture one `occurredAt` and use it for the attempt, card update, and schedule base.

Make record mapping validate:

- Enum values.
- Required ranked-line JSON.
- `bestMoveUCI` consistency with rank one.
- FEN and side-to-move consistency where practical.

Add tests for:

- v3 through v5 migration.
- Existing v4 training data through v5.
- Expected indexes.
- `PRAGMA foreign_key_check`.
- Reconciliation insert, update, reset, delete, idempotence, and rollback.
- Preserving progression when the best answer is unchanged.
- Resetting progression when the best answer changes.
- Removing cards when a key moment disappears.
- Exact due ordering and due-at-now inclusion.
- Total due count when the returned lesson is limited.
- One-timestamp persistence.
- Cascades after reconciliation and game deletion.

Verification gate:

```bash
swift test --package-path Packages/Persistence
```

Also migrate a copy of the real sandbox database and inspect it:

```bash
sqlite3 "$QA_DB" "SELECT identifier FROM grdb_migrations ORDER BY identifier;"
sqlite3 "$QA_DB" "PRAGMA foreign_key_check;"
sqlite3 "$QA_DB" ".indexes trainingCard"
sqlite3 "$QA_DB" ".indexes trainingAttempt"
```

The live sandbox database must remain untouched during this gate.

### Step 4 - Synchronize historic and current reports

Replace `GameReplayViewModel.buildReport()`'s untracked, error-swallowing persistence task with an awaited, generation-safe synchronization state.

Expose a small state such as:

- Preparing practice.
- Practice ready with a card count.
- No learner-owned key moments.
- Practice preparation failed with Retry.

Do not show an enabled `Practice key moments` action until reconciliation has completed.
Do not turn a persistence failure into a false empty lesson.

Run an idempotent, cancellable backfill for analyzed games that lack reconciled cards.
Reuse the existing shared `ReportBuilding` path.
Do not run report analysis on the main actor.
Do not create cards from facts that failed the existing audit.

When a configured username matches one side, generate only that side's cards.
When Dashboard is personalized by username, exclude unmatched study games from its due queue.
Keep explicit Report practice available for unmatched study games with neutral copy.

Verification gate:

```bash
xcodebuild test \
  -scheme Chessanto \
  -destination 'platform=macOS' \
  -only-testing:ChessantoTests/TrainingCardSynchronizerTests \
  -only-testing:ChessantoTests/GameReplayViewModelTrainingTests
```

Add those test files if they do not exist.

The real fixture must create the expected cards without manually seeding SQL.
An old analyzed QA database must gain cards without opening every replay.
Opening Practice immediately after Report becomes ready must never flash a false empty state.

### Step 5 - Replace the practice flow with an explicit state machine

Keep `PracticeSessionViewModel` as the SwiftUI-facing module, but make its interface small and event-driven.

Use one render state with associated values.
Do not publish a state enum alongside independently mutable arrays and counters that can contradict it.

The states should cover:

- Loading.
- Empty.
- Prompt.
- Evaluating.
- Incorrect or inaccurate feedback without answer disclosure.
- Playable feedback with the stronger move.
- Strong feedback.
- Revealed answer.
- Recoverable engine failure.
- Recoverable persistence failure.
- Completion.

Own and cancel the active evaluation task.
Move synchronously to evaluating before launching asynchronous work.
Reject duplicate submissions while evaluating.
Ignore stale completions by request generation and card ID.
Cancel work when the sheet closes.

Only allow selection of a piece belonging to the side to move.
Keep the board at the original position during evaluation and feedback.

Use this action hierarchy:

- Incorrect or inaccurate: Try again is primary.
- Reveal is secondary.
- Skip is visually subordinate and never the prominent action.
- Playable: acknowledge the idea, show the stronger move, and make Next primary.
- Strong: confirm the played SAN and make Next primary.
- Revealed: show the verified arrow and continuation, with Try it yourself primary and Skip secondary.

Do not show the best SAN or arrow in incorrect or inaccurate feedback before Reveal.
Do not use the original mistake summary as strong feedback.

Hints should be deterministic:

- Hint one uses an audited theme when available, otherwise a neutral forcing-move prompt.
- Hint two names the piece and origin square from the verified best move.
- Reveal is tracked separately from the two hints.

Completion should report:

- Positions reviewed.
- First-attempt strong recalls.
- Revealed or skipped positions.
- A theme to revisit.
- Review again today when any session card is still due.
- Otherwise the earliest future review.

Do not call a single theme `recurring`.
Use `Theme to revisit` unless at least two reviewed cards share it.

Make the completion primary action depend on entry point:

- From Report: `Back to game`.
- From Dashboard: `Back to Progress`.

Do not show a `Back to game` button whose callback is nil.

Verification gate:

```bash
xcodebuild test \
  -scheme Chessanto \
  -destination 'platform=macOS' \
  -only-testing:ChessantoTests/PracticeSessionViewModelTests \
  -only-testing:ChessantoTests/PracticeSessionStateMachineTests
```

Cover load reset, invalid records, retry, hint, reveal, skip, playable, strong, duplicate submission, cancellation, stale completion, engine retry, persistence retry, multi-card progression, and completion counts.

### Step 6 - Fix Dashboard and presentation coordination

Do not pass captured Dashboard arrays into a practice session.
Pass a `PracticeScope` that loads fresh data when the session starts.

Refresh the Dashboard queue after practice dismisses.
The same card must not remain visually due after a strong answer schedules it into the future.
Reopening practice must use the persisted progression, not the original Dashboard snapshot.

Make Next lesson visible even when accuracy-trend prerequisites are unavailable.
A user who imports PGN locally or has not configured a chess.com username must still have a path to existing practice cards.
Keep the accuracy dashboard's username guidance separate from learning-loop availability.

Avoid stacking a practice sheet on top of the Dashboard sheet.
Coordinate Dashboard and practice from one presentation owner.
Return to Dashboard after a Dashboard lesson and reload it.
Preserve the selected game in the main window throughout.

Clarify scheduling copy:

- `Review now` when cards remain due.
- `Tomorrow` when the next due date is the next calendar day.
- An abbreviated date for later reviews.
- Exact total due count, or `20+`, when the lesson itself is limited.

Verification gate:

- Solve one due card from Dashboard.
- Return to Progress.
- Confirm the action and due count update without closing Progress manually.
- Reopen practice and confirm it does not load the stale solved card.
- Quit and relaunch against the QA database.
- Confirm the same Dashboard state persists.
- Inspect the matching database row directly.

### Step 7 - Visual, responsive, accessibility, and capture pass

Resolve the 900-point replay layout conflict without enlarging the minimum app window beyond 900 points.
At the narrow detail width, allow the board column to use approximately 400 points or allow the right pane to use a proven smaller minimum.
Do not let the right pane clip or horizontally scroll.
Keep the board visually dominant.

Make the practice layout adaptive between the supported 900-point and 1400-point app windows.
Avoid fixed widths that overflow when the Dashboard route or a narrow sheet presents practice.
Use scroll containment for long feedback rather than truncation.

Correct the shared contrast tokens while preserving the palette.
Use measured accessible values.
Good starting values are:

- Secondary text near `#6B665F`, which exceeds 4.5:1 on all three existing light surfaces.
- A darker brass near `#906719`, which exceeds 4.5:1 against the current surfaces and with white text.

Verify exact values before committing them.
Do not introduce a new hue.

Audit classification chips separately.
Their labels already prevent color-only meaning, but their small foreground text must also meet contrast.
Keep semantic hues reserved for move quality.

Give primary practice and Dashboard controls an effective 44 by 44 point target.
Keep icon-only controls labeled, tooled, and semantically exposed.

Add accessibility behavior for:

- Board square labels that include piece, selected state, and legal-destination state.
- Logical focus order.
- Prompt-to-evaluating and evaluating-to-feedback announcements.
- Outcome and reveal announcements.
- Disabled button state.
- Escape dismissal.
- Keyboard activation for Hint, Reveal, Try again, Skip, Next, and Done.
- Reduced-motion transitions.

Do not rely on green or any other color alone for success.
Use text and symbols.
Use brass for success chrome.

Commit or repair a reliable native window-capture helper.
Do not build a broad golden-image framework in this session.

Verification gate:

```bash
swift scripts/axprobe.swift Chessanto > /tmp/chessanto-learning-loop-ax.txt
rg -n "Practice|Hint|Reveal|Try again|Skip|Next|Strong|Playable|Review" /tmp/chessanto-learning-loop-ax.txt
```

Exercise the app under a system-dark desktop and confirm the app remains intentionally forced light.
Exercise reduced motion.
Exercise keyboard-only flow.

### Step 8 - Full acceptance, documentation, version, commit, and push

Run every package suite:

```bash
swift test --package-path Packages/ChessCore
swift test --package-path Packages/AnalysisKit
swift test --package-path Packages/CoachKit
swift test --package-path Packages/EngineKit
swift test --package-path Packages/ChessComKit
swift test --package-path Packages/Persistence
```

Run the full app suite:

```bash
xcodegen generate
xcodebuild test \
  -scheme Chessanto \
  -destination 'platform=macOS'
```

Run the live gates:

```bash
swift run --package-path Packages/EngineKit engine-smoke
swift run --package-path Packages/CoachKit coach-grounding
```

Build Release:

```bash
scripts/release-build.sh
```

Inspect the product:

```bash
APP_DIR="$(
  xcodebuild \
    -scheme Chessanto \
    -project Chessanto.xcodeproj \
    -configuration Release \
    -showBuildSettings 2>/dev/null |
  awk -F'= ' '/ BUILT_PRODUCTS_DIR/ { print $2; exit }'
)"
APP="$APP_DIR/Chessanto.app"
test -d "$APP"
plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"
lipo -archs "$APP/Contents/MacOS/Chessanto"
codesign --verify --deep --strict "$APP"
```

An ad-hoc or unsigned local build is acceptable according to the existing release policy.
Do not sign with a Developer ID.
Do not notarize.
Do not upload a release artifact.

If every gate passes, update `project.yml`:

- `MARKETING_VERSION` to `1.0.0`.
- `CURRENT_PROJECT_VERSION` to `2`.

Update `README.md`:

- Add persistent practice and due lessons to the feature list.
- Remove mistake-derived practice and spaced repetition from Future directions.
- State that all app data, analysis, attempts, and mastery remain local.
- Keep signing and notarization explicitly manual.
- Do not claim public distribution until credentials are supplied and that process is run.

Update `handoffs/HANDOFF.md`:

- Record the engine-search hardening.
- Record the deep training interface and exact grading decisions.
- Record `v5_trainingIndexes`.
- Record reconciliation, reset, and deletion policy.
- Record historic-game backfill behavior.
- Record Dashboard refresh and lesson scoping.
- Record new practice-state semantics.
- Record the real command results and test counts.
- Record the valid screenshot names.
- Record the sandbox versus non-sandbox database caveat.
- Keep remaining deferred work explicit.

Append a new section to `devlogs/2026-07-18.md`:

- List every reproduced bug before its fix.
- Describe the architecture changes and why the seams were placed there.
- Record migration checks.
- Record live QA behavior.
- Record contrast measurements.
- Record screenshot-capture failures and the corrected method.
- Record all commands and results.

When writing or substantially editing those Markdown files, put each complete sentence on its own physical line.

Run final hygiene:

```bash
git diff --check
git status --short
git diff --stat
```

Use small, reviewable commits.
Suggested commit sequence:

```text
fix: harden engine and training persistence
refactor: deepen the practice session flow
polish: finish Chessanto v1 release readiness
```

Do not add an agent co-author.
Do not modify `CHANGELOG.md`.
Do not force-add ignored screenshot PNGs unless the user explicitly asks to commit them.
Keep the large native captures local and list their paths in the handoff and devlog.

Push only after every gate and the final screenshot review pass:

```bash
git push origin main
git status --short --branch
git log -3 --oneline --decorate
```

The final branch must be clean and show `main` synchronized with `origin/main`.

## Native screenshots to capture

Capture the Chessanto window itself, not the whole Codex desktop.
The macOS menu bar or window title must prove Chessanto is active.
Open every PNG and visually inspect it before calling it acceptance evidence.

At a 900-point-wide main window, capture:

1. `v1-dashboard-due-900.png`.
2. `v1-report-practice-ready-900.png`.
3. `v1-practice-prompt-900.png`.
4. `v1-practice-black-to-move-900.png`.
5. `v1-practice-incorrect-no-answer-900.png`.
6. `v1-practice-reveal-900.png`.
7. `v1-practice-playable-900.png`.
8. `v1-practice-strong-900.png`.
9. `v1-practice-complete-900.png`.
10. `v1-dashboard-after-practice-900.png`.

At a 1400-point-wide main window, capture:

1. `v1-replay-report-1400.png`.
2. `v1-practice-prompt-1400.png`.
3. `v1-practice-feedback-1400.png`.
4. `v1-dashboard-1400.png`.

The incorrect screenshot must contain no best-move arrow and no best SAN.
The reveal screenshot must contain the verified arrow, SAN, and continuation.
The strong screenshot must name the move the user found and must not describe the original mistake as if it just happened.
The completion screenshot must distinguish due-now from a future review.
The Dashboard-after-practice screenshot must prove the stale lesson state is fixed.

## Exact files and modules likely to change

Primary training implementation:

- `App/Sources/Chessanto/Training/TrainingDomain.swift`.
- `App/Sources/Chessanto/Training/PracticeSessionViewModel.swift`.
- `App/Sources/Chessanto/Training/PracticeSessionView.swift`.
- New `App/Sources/Chessanto/Training/Training.swift`.
- New `App/Sources/Chessanto/Training/TrainingPersistenceMapping.swift`.
- New `App/Sources/Chessanto/Training/TrainingCardSynchronizer.swift`, if synchronization is not kept private inside `Training`.
- New `App/Sources/Chessanto/Training/PracticeSessionState.swift`, if it materially simplifies the view model.

Engine:

- `App/Sources/Chessanto/Analysis/EngineService.swift`.
- New `App/Sources/Chessanto/Analysis/BoundedEngineSearch.swift`.
- `Packages/EngineKit/Sources/EngineKit/AnalysisEngine.swift`.
- `Packages/EngineKit/Tests/EngineKitTests/AnalysisEngineTests.swift`.
- `App/Tests/ChessantoTests/EngineServiceTests.swift`.
- `Packages/EngineKit/Sources/engine-smoke/main.swift` only if the bounded interface changes.

Persistence:

- `Packages/Persistence/Sources/Persistence/Schema.swift`.
- `Packages/Persistence/Sources/Persistence/GameStore.swift`.
- `Packages/Persistence/Sources/Persistence/TrainingCardRecord.swift`.
- `Packages/Persistence/Sources/Persistence/TrainingAttemptRecord.swift`.
- `Packages/Persistence/Tests/PersistenceTests/PersistenceTests.swift`.

App integration:

- `App/Sources/Chessanto/GameReplayViewModel.swift`.
- `App/Sources/Chessanto/GameReplayView.swift`.
- `App/Sources/Chessanto/GameReportView.swift`.
- `App/Sources/Chessanto/Dashboard/DashboardView.swift`.
- `App/Sources/Chessanto/ContentView.swift`.
- `App/Sources/Chessanto/GameLibrary.swift`.
- `App/Sources/Chessanto/ReportBuilding.swift` only if a shared report-plus-input result removes duplicate construction cleanly.

Design and accessibility:

- `App/Sources/Chessanto/DesignSystem/DesignColors.swift`.
- `App/Sources/Chessanto/DesignSystem/DesignComponents.swift`.
- `App/Sources/Chessanto/Analysis/MoveClassificationStyle.swift`.
- `App/Sources/Chessanto/Board/BoardView.swift`.

Tests:

- `App/Tests/ChessantoTests/TrainingDomainTests.swift`.
- `App/Tests/ChessantoTests/PracticeSessionViewModelTests.swift`.
- New `App/Tests/ChessantoTests/PracticeSessionStateMachineTests.swift`.
- New `App/Tests/ChessantoTests/TrainingCardSynchronizerTests.swift`.
- New `App/Tests/ChessantoTests/GameReplayViewModelTrainingTests.swift`.
- New `App/Tests/ChessantoTests/DesignColorContrastTests.swift`.

Tooling and release documentation:

- New or repaired native capture helper under `scripts/`.
- `README.md`.
- `project.yml`.
- `handoffs/HANDOFF.md`.
- `devlogs/2026-07-18.md`.

Do not touch unrelated packages or generated files.
Do not manually modify `Chessanto.xcodeproj`.
Regenerate it with XcodeGen.

## Exact acceptance scenario

1. Launch the Release app with the QA database.
2. Confirm historic analyzed games generate cards without manually inserting SQL and without opening every Report.
3. Open one of the user's analyzed games.
4. Open Report and wait for the explicit Practice-ready state.
5. Start the full key-moment lesson.
6. Attempt one legal but incorrect move.
7. Confirm the original position is restored.
8. Confirm no best SAN or arrow is disclosed.
9. Retry and play a strong move.
10. Confirm feedback names the move played and uses verified positive copy.
11. On the next card, use hint one and hint two.
12. Reveal the answer.
13. Confirm the verified arrow and short continuation appear only now.
14. Finish the session.
15. Confirm the summary reports reviewed, first-attempt strong, revealed, and due-now or future state accurately.
16. Return to Progress without nested sheets.
17. Confirm Next lesson refreshes immediately.
18. Reopen practice and confirm it loads fresh persisted progress.
19. Quit and relaunch.
20. Confirm the queue, attempts, mastery, and due dates persist.
21. Inspect the matching rows directly in the QA SQLite database.
22. Run one non-cached legal move through the live training evaluator.
23. Confirm a cancelled or timed-out search does not block the next live engine operation.
24. Run `coach-grounding` and confirm the training work did not regress verified Coach output.

## Final acceptance checklist

- [ ] `main` started clean and synchronized.
- [ ] The real sandbox database was backed up before migration testing.
- [ ] QA used a distinct database path.
- [ ] No shipped migration before v5 was edited.
- [ ] v5 indexes exist.
- [ ] `PRAGMA foreign_key_check` is empty.
- [ ] Reconciliation removes stale cards.
- [ ] Reconciliation resets changed answers.
- [ ] Reconciliation preserves unchanged mastery.
- [ ] Historic analyzed games backfill without manual SQL.
- [ ] Report Practice cannot race card persistence.
- [ ] Dashboard lessons load fresh records.
- [ ] Dashboard refreshes after practice.
- [ ] User-scoped Dashboard queues exclude unmatched games when a username is known.
- [ ] Invalid local card data surfaces a typed recoverable error and cannot misalign records.
- [ ] Cached alternatives use cached grading thresholds rather than automatic strong.
- [ ] Mate handling is fully typed and tested.
- [ ] Incorrect feedback does not reveal the answer.
- [ ] Reveal is a distinct state.
- [ ] Strong feedback describes the successful move.
- [ ] Reveal and Skip leave the card due without inserting fake move attempts.
- [ ] Duplicate submissions cannot produce duplicate evaluations or attempts.
- [ ] Dismissal cancels active evaluation.
- [ ] Engine bounded search has finite completion, timeout, and cancellation.
- [ ] A late bestmove cannot complete the wrong request.
- [ ] The 900-point replay layout does not clip.
- [ ] Practice works at 900 and 1400 points.
- [ ] Dashboard practice does not stack sheets.
- [ ] Primary controls meet the 44-point effective target.
- [ ] Keyboard-only practice is complete.
- [ ] AX labels and announcements are meaningful.
- [ ] Reduced motion is respected.
- [ ] Forced-light appearance remains correct on a system-dark desktop.
- [ ] Secondary text and brass text/fills meet measured contrast requirements.
- [ ] No green was introduced into chrome.
- [ ] Board, pieces, square themes, coordinates, flip, and identity are unchanged.
- [ ] Every named screenshot visibly contains the claimed Chessanto state.
- [ ] All package tests pass.
- [ ] Full app tests pass.
- [ ] `engine-smoke` passes.
- [ ] `coach-grounding` passes.
- [ ] Release build succeeds.
- [ ] Release version reports `1.0.0` only after all gates pass.
- [ ] README matches the shipped learning loop.
- [ ] Handoff and devlog contain exact results.
- [ ] `git diff --check` is clean.
- [ ] No generated or auto-generated file was manually edited.
- [ ] No agent co-author was added.
- [ ] Changes were committed and pushed to `origin/main`.
- [ ] Final worktree is clean.

## Clear non-goals

- Do not add library search, filtering, or sorting in this session.
- Do not add a promotion picker.
- Do not add variation promotion or collapse controls.
- Do not improve general Coach prose quality or model recommendations.
- Do not change Coach verification policy.
- Do not add a new spaced-repetition algorithm.
- Do not add streaks, badges, achievements, or manipulative urgency.
- Do not add cloud sync, iCloud, accounts, social features, subscriptions, or leaderboards.
- Do not add Lichess import.
- Do not build repertoire training or play-vs-engine.
- Do not redesign the board, pieces, app icon, or brand identity.
- Do not introduce green into chrome.
- Do not add a generic repository protocol.
- Do not add a generic Redux framework or TCA dependency.
- Do not create a separate Training package.
- Do not rewrite the full EngineKit public interface or UCI driver architecture.
- Do not build a broad screenshot golden-diff system.
- Do not sign, notarize, publish, or upload a release without explicit credentials and authorization.

## Deferred next priorities

After this session is fully accepted, the next product priorities should remain:

1. Library search, filtering, and sorting for larger collections.
2. Promotion UI and mainline-equivalent variation handling.
3. Real variation branch promotion and collapse semantics.
4. Coach concision and stronger recommended-model guidance.
5. A dedicated XCUITest and golden native screenshot matrix.
6. Developer ID signing and notarized distribution after credentials are supplied.
7. Lichess import only after the local learning loop proves sustained value.
