# Next session - multi-ply practice cards (P4.5)

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with three other sessions (fork detection, move-quality flags, LLM Coach purpose - separate worktrees/branches, do not read or wait on any of them, your work is independent).

You are working in a dedicated git worktree on branch `multiply-practice-p4.5`, checked out from `main`. Commit and push this branch when you are done; do not merge to `main` yourself; do not touch the primary checkout at `/Users/willis/Documents/chessanto` or any other worktree directory.

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.5 Practice trains recognition, not calculation" section, in full.
3. `App/Sources/Chessanto/Training/PracticeSessionViewModel.swift`, in full. This is the file you are extending. Its current flow: `submit(attemptedUCI:)` grades the learner's first move against the card's best line and ends the exchange immediately - the learner never sees the opponent's reply or plays a follow-up.
4. `App/Sources/Chessanto/Training/TrainingDomain.swift`, in full - `TrainingCard`, `RankedLine` (confirm its `principalVariationUCI: [String]` already stores a multi-ply line - this is the data you need, already present, not something to add), `TrainingCardFactory`, `DeterministicReviewScheduler` (recently changed by a parallel session that has already merged - read its current state, do not assume the old fixed-ladder version).
5. `App/Sources/Chessanto/Training/PracticeContentView.swift`, in full, and `App/Sources/Chessanto/Training/ChessGlossary.swift` - the current hint ladder (two levels: theme name, then starting square) and its display.
6. `App/Sources/Chessanto/Board/BoardInteraction.swift` (or wherever the shared select-then-move state machine lives - confirmed to exist as a single shared type used by both `GameReplayView` and `PracticeSessionViewModel`) - read this fully before changing how practice interaction works, since multi-ply practice needs the board to accept a sequence of moves rather than one, and this state machine is the correct place to understand what already exists for that versus what you'd need to add.

## The problem

`PracticeSessionViewModel.submit(attemptedUCI:)` grades on the first legal move and ends the card there. The learner never sees the opponent's reply and never has to calculate the follow-up - which is where the actual difficulty in a tactic usually lives. A queen sacrifice that leads to mate in three is not tested by "did you find the first move," it's tested by "can you find all three."

The hint ladder is also thin: level one is a theme name (only exists if a theme fired) or a generic "Look for the forcing idea," level two is the origin square. Neither teaches a method, and the single most useful first hint - "what is your opponent threatening?" - does not exist, even though `ThemeDetector.ignoredThreat` now exists and could answer exactly that question for cards built from a missed-threat moment (confirm whether any current practice cards are actually sourced from ignored-threat moments by reading `TrainingCardFactory.drafts` - if not yet, that is a `TrainingCardFactory`-level integration question, not something to solve in this session unless it falls out naturally).

## Scope for this session

Make a practice card multi-ply: after the learner plays the best move (or an acceptable alternative), the engine's response plays out on the board automatically, and the learner is then asked for the *next* move in the line, continuing until the point of the tactic is made (i.e., until `RankedLine.principalVariationUCI` is exhausted, or until the position is clearly resolved - e.g. material is won and no immediate follow-up matters, or checkmate is delivered).

Concretely decide and implement:

1. **The multi-ply state machine.** `PracticeSessionViewModel` needs new state to track: which ply of the line the learner is currently on, what's already been played (both the learner's correct moves and the engine's automatic replies), and when the exchange is actually complete. Design this as an explicit, testable state (an enum or a small struct), not a scattering of new booleans - this codebase's existing `BoardInteraction` and `SessionState` types are the pattern to follow for how state is modeled elsewhere in this same file.
2. **Grading each ply.** The learner's move at each step must be graded against the corresponding ply of `principalVariationUCI` (or an equivalently-good alternative if the position allows more than one correct continuation - decide whether to require exact match to the stored line or to accept other objectively-fine moves, and justify your choice; matching the stored line exactly is the simpler, more conservative default if you're not confident about verifying "objectively fine" without a fresh engine call, and this codebase already has a `DefaultTrainingMoveEvaluator` grading approach for the first ply - read it and either reuse its exact logic at every ply or explain precisely why a ply needs different treatment).
3. **The engine's automatic reply.** After a correct learner move, the position advances automatically to include the line's next (opponent) move, animated/displayed the same way a move is normally shown on this board (reuse existing board-update mechanisms - do not build a second, parallel way to move a piece on screen).
4. **When the exchange ends.** Decide and implement a clear termination condition: the stored line is exhausted, checkmate is reached, or (your call, with reasoning) a position where the material/positional point has been made even if the stored line technically continues a few more "obvious" moves - state which you chose and why.
5. **Wrong-answer feedback that names what the point was**, per the backlog's specific complaint: today's feedback ("That move misses the point of the position. Reset and try to find Qe7") never says what the point was. At minimum, on a wrong answer, tell the learner what the correct move's actual idea accomplished (using already-available Facts the way `ReportText` already composes them - reuse existing sentence-building rather than inventing new free-composed prose).
6. **A first hint: "What is your opponent threatening?"** - add this as hint level zero/one (renumber the ladder as needed), populated using `ThemeDetector.ignoredThreat` or the equivalent threat information already available for that position, when it exists; when it doesn't (no concrete threat detectable, e.g. a card built from a `betterMove`-only moment), fall back to the current generic hint text rather than showing something false.

## Design decisions you must make and write down (in code comments and your session report)

- How many plies is "enough" before giving up on continuing the line if the learner keeps failing - does `tryAgain()`'s existing retry behavior extend naturally to a multi-ply exchange, or does it need to reset to ply one each time? Read `tryAgain()`'s current implementation before deciding.
- Whether `firstAttemptSuccesses` (used in the session completion summary) should now mean "got every ply right on the first try" or something else - state your choice.
- How this interacts with the spaced-repetition scheduler that just landed (a parallel session's work, already merged to `main` - read `DeterministicReviewScheduler`'s current state in this branch, which already includes it) - does a multi-ply card's overall outcome (for scheduling purposes) come from the first ply only, the hardest ply, or all-or-nothing across the whole line? State your reasoning; there is no existing precedent for this in the codebase since practice cards have always been single-ply until now.

## Required rigor

- TDD. Write the failing test before each piece of implementation - this is UI-state-machine-heavy work, and this codebase's `PracticeSessionViewModel`/`TrainingDomain` already have an established test style to follow (read `Packages/AnalysisKit/Tests/AnalysisKitTests/` and whatever test file already covers `PracticeSessionViewModel` or `TrainingDomain` in `App/Tests/ChessantoTests/` for the pattern).
- Do not free-compose new chess prose - reuse `ReportText`'s existing sentence-building functions or Fact types wherever the feedback needs to state something about the position; if a genuinely new sentence template is needed, follow `ReportText`'s exact template discipline (a typed Fact interpolated into a fixed string, nothing composed freely).
- Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in long Markdown. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.
- If your environment allows screen capture, verify the multi-ply flow visually at least once (a real card, playing through 2-3 plies, seeing the engine's reply appear on the board). If it does not, verify via the accessibility tree the same way past sessions in this project have, and say explicitly what you could and could not visually confirm.

## Test plan (minimum)

- A 3-ply card (learner move, engine reply, learner move) where the learner gets both moves right - the exchange completes, is recorded correctly, and the summary/scheduling reflects a full success.
- The same card where the learner gets the second ply wrong - correct wrong-answer feedback naming the actual point of the position, and a sensible retry/reset behavior (per your design decision above).
- A card where the stored line ends in checkmate - the exchange terminates cleanly at the mate, not asking for a move that doesn't exist.
- The new "what's the threat" hint - present and correct when a genuine threat fact is available for the card, absent/generic when it is not, never a false claim.
- Confirm the existing single-ply cards (any legacy card without a rich enough `principalVariationUCI`, if such a case can occur) still work without a crash - state explicitly whether this case is even reachable given current data, and if so, how it's handled.

## Validation commands

1. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 179 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Fork/pin detection, move-quality flags, `%clk` analysis, the LLM Coach's purpose (separate parallel sessions). Do not touch `Packages/AnalysisKit`'s detectors or `Packages/CoachKit`. Do not change how cards are initially selected/generated (`TrainingCardFactory.drafts`) beyond what's strictly needed to support multi-ply grading - if you find the card-generation step itself needs a change to supply enough line depth, make the smallest change that unblocks you and report it, rather than redesigning card generation.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries.
Write a dated devlog at **`devlogs/2026-08-24-multiply-practice.md`** (this exact filename - three other sessions are writing their own devlogs today).
Commit on this branch (`multiply-practice-p4.5`) and push it to `origin` - do not merge to `main` yourself.
Report back plainly: your state-machine design and why, the grading/termination rules you chose, the hint you added and its data source, what you visually or AX-tree verified, and validation results.
