# Next session - real spaced repetition (P4.6)

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with `handoffs/NEXT-SESSION-TAKEAWAYS.md` and `handoffs/NEXT-SESSION-COACH-ENTRY-POINTS.md` (separate sessions, separate git worktrees/branches - do not read or wait on either, your work is independent).

You are working in a dedicated git worktree on branch `spaced-repetition-p4.6`, checked out from `main`. This is a real, separate checkout - commit and push this branch when you are done, do not attempt to merge to `main` yourself, and do not touch the primary checkout at `/Users/willis/Documents/chessanto` (other sessions may be using it).

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.6 Spaced repetition" section, for the original framing.
3. `App/Sources/Chessanto/Training/TrainingDomain.swift` in full - `DeterministicReviewScheduler` (currently around lines 474-505) is the function you are replacing the internals of. Read the whole file for `TrainingOutcome`, `MasteryState`, and every other type it touches.
4. `Packages/Persistence/Sources/Persistence/TrainingCardRecord.swift` in full - the persisted shape you will be adding fields to.
5. `Packages/Persistence/Sources/Persistence/Schema.swift` in full, especially the most recent few migrations (`v9_analysisProvenance` through `v11_playerIdentity`) for the exact pattern a new migration follows. The next migration is `v12`.
6. `App/Sources/Chessanto/Training/PracticeSessionViewModel.swift`, specifically wherever it calls `scheduler.next(card:outcome:now:)` (around line 268) and however it reads/writes `TrainingCardRecord` back to the store, so you understand the full round trip before changing what the scheduler returns.
7. `Packages/AnalysisKit/Tests/AnalysisKitTests/` or wherever `TrainingDomainTests` currently live (it may be in `App/Tests/ChessantoTests/` - confirm the actual location) - specifically the existing tests `deterministicScheduleTransitionsToMasteredAfterThreeStrongRecalls` and `playableResetsSuccessesAndIsDueTomorrow`, since your change will need to either preserve or deliberately, explicitly change what these assert.
8. This project's native database-safety procedure (referenced in several other handoff documents: sandbox backup, disposable copy, both opt-in environment variables `CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE` and `CHESSANTO_DATABASE_PATH`) - required if you do any native QA against a real database with real cards in it, though unit tests against an in-memory or temp database should cover most of this work.

## The problem

`DeterministicReviewScheduler` today: an incorrect answer sets `dueAt = now`, so the card can reappear in the same practice session seconds after being shown - which trains recognition ("I just saw this"), not recall. Correct answers follow a fixed ladder (1st correct: 3 days, 2nd: 7 days, 3rd+: 14 days and mastered) with no ease factor, no lapse tracking, and no per-card memory of how well a specific position has stuck versus how many times it has been gotten wrong before.

There is also no way to drill a theme across games (the Player Brief already diagnoses "Loose pieces, 4 of 6 games" but offers only the generic due queue as an action) - that is explicitly a separate, larger feature (practice session composition, not scheduler math) and is **out of scope for this session**.

## Scope for this session

Replace the fixed-ladder scheduler with an ease-factor-driven one, and fix the same-session-reappearance bug as the first, non-negotiable part of this work.

### The minimum fix, first, before anything else

An incorrect or inaccurate answer must never set `dueAt` to a time in the past or the immediate present. At minimum, push it out at least until the next calendar day. This alone fixes the most damaging part of the reported problem and should be your first commit in this session, verified with its own test, before you touch the ease-factor design.

### The fuller design - proposed, not rigidly fixed, but write down your reasoning for any number you change

Add two new persisted fields to `TrainingCardRecord` via a `v12` migration:
- `easeFactor: Double`, default `2.5` for a new card.
- `lapseCount: Int`, default `0`.

Also add `intervalDays: Double`, default `0`, to store the interval explicitly rather than inferring it from `dueAt - updatedAt` at the next review - explicit storage is how real spaced-repetition systems (Anki, SM-2) avoid clock-skew and timezone bugs from creeping into interval math, and is worth the one extra column.

Suggested update rule for `next(card:outcome:now:)`, adapted from SM-2 to this app's four-outcome model (`.strong`, `.playable`, `.inaccuracy`, `.incorrect` - confirm the actual case names by reading `TrainingOutcome`'s definition):

- **`.strong` (a correct, confident answer):**
  - `consecutiveSuccesses += 1`.
  - `easeFactor = max(1.3, card.easeFactor + 0.15)` (floor of 1.3 is SM-2's standard floor - a card should never require reviewing so often that shortening its interval further stops helping).
  - New interval: keep the existing ladder for the first two successes to preserve continuity with current behavior and the existing test's expectations (1st success: 1 day if the card was previously new or had lapsed, otherwise use the 3-day/7-day steps as today) - then, once graduated, `intervalDays = previousIntervalDays * easeFactor`, capped at a sensible maximum (100-180 days is the usual SM-2-derived range; pick one and justify it) so a card is never scheduled absurdly far out.
  - Preserve the existing graduation rule: a card reaches `mastered` at the 3rd consecutive success, the same threshold the existing test already asserts - only the interval *values* from that point on should change to be ease-factor-driven rather than a flat 14 days.
- **`.inaccuracy` / `.incorrect` (a lapse):**
  - `lapseCount += 1`, `consecutiveSuccesses = 0`, `masteryState` returns to `learning`.
  - `easeFactor = max(1.3, card.easeFactor - 0.2)`.
  - `intervalDays = 1` (relearn tomorrow, not immediately - this is the fix from the minimum-fix section above, now integrated into the fuller model rather than a separate special case).
- **`.playable` (a hint-assisted or partial-credit answer):** the existing behavior (1 day, `learning` state) is a reasonable middle ground already - decide whether it should adjust `easeFactor` at all (a defensible choice is: no change, since it is a weaker signal than a clean `.strong` and not a real lapse either) and state your reasoning.

This design is a considered starting point, not untouchable - if reading the actual `TrainingOutcome` cases or existing tests reveals a better-fitting number or rule, use your judgment and write down why you changed it, the same way past sessions in this project have documented a deviation from a suggested design when the code turned up something the design didn't anticipate.

## Required rigor

- TDD (red-green-refactor), this project's standing convention. Write the failing test before the implementation for each behavior.
- A new migration is a one-way, additive schema change in this project's convention (see `v8` through `v11` for the pattern) - never alter or remove an existing column, never renumber an existing migration.
- If you do any native QA against a real database, follow the sandbox backup / disposable copy / both opt-in environment variables procedure without exception - this project has found and fixed a real data-safety bug before from skipping steps of this procedure.
- Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in any long Markdown you write or substantially edit. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Test plan (minimum - add more as your design requires)

- The minimum fix in isolation: an incorrect answer's new `dueAt` is never `now` or earlier, and is at least a day out.
- `easeFactor` increases on a `.strong` answer and decreases on a lapse, each clamped correctly at the 1.3 floor.
- A card that lapses has `consecutiveSuccesses` reset to 0 and returns to `learning`, regardless of how far it had progressed before.
- The existing graduation behavior (3rd consecutive success -> `mastered`) still holds, updated only for whatever new interval value your design produces at that point - update `deterministicScheduleTransitionsToMasteredAfterThreeStrongRecalls` deliberately if its asserted interval numbers need to change, and say so in your report rather than silently editing it.
- `playableResetsSuccessesAndIsDueTomorrow` - confirm whether this still holds under your design or needs a deliberate, reported update.
- A card that lapses repeatedly (e.g. 3 lapses in a row) shows a real, measurable difference in scheduling behavior from a card lapsing once - `lapseCount` actually being used for something is the point of tracking it; state clearly in your report what you decided it should affect, since the design above tracks it but does not yet specify a rule that reads it beyond incrementing it. If you decide `lapseCount` should further slow ease growth or cap the maximum interval for a frequently-lapsed card, implement that and test it; if you decide to leave it recorded-but-unused for now (a defensible choice, since a future session could use it for cross-card interleaving), say so explicitly rather than leaving it silently dead code.
- The migration itself: existing cards in a pre-`v12` database gain the new columns with the stated defaults and the app still functions against them (a round-trip persistence test, matching this project's existing migration-test pattern - find it by reading how `v11_playerIdentity` or a similar recent migration is tested).

## Validation commands

1. `swift test` from `Packages/Persistence/` - must pass. Confirm and report the current baseline count before your changes.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 174 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Cross-card/cross-game theme drilling (a separate, larger practice-session-composition feature). Any change to how practice cards are generated, selected for a session, or graded (`PracticeSessionViewModel`'s grading logic, `TrainingCardFactory` - read-only if you need context, do not modify). P4.2, P4.3, P4.5, P4.8, P2.5 (separate parallel sessions or future work). Do not touch `Packages/AnalysisKit` or `Packages/CoachKit`.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries - other parallel sessions are touching this same file and it will be merged by hand afterward, so keep your addition self-contained and easy to splice in.
Write a dated devlog at **`devlogs/2026-08-24-spaced-repetition.md`** (this exact filename, not the bare date - two other sessions are writing their own devlogs today and a shared filename causes a git conflict during integration).
Commit on this branch (`spaced-repetition-p4.6`) and push it to `origin` - do not merge to `main` yourself, a separate integration step will handle that.
Report back plainly: the exact final algorithm you implemented and any deviation from the suggested design with your reasoning, what you decided about `lapseCount`, whether/how the two existing tests changed and why, the migration you wrote, and validation command results.
