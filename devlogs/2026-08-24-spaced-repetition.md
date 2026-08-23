# 2026-08-24: Spaced Repetition (P4.6)

## Overview

This session implemented real spaced repetition for Chessanto's practice queue (P4.6 from `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`).
The previous review scheduler suffered from two major shortcomings:
1. Incorrect and inaccurate answers set `dueAt = now`, causing failed cards to reappear immediately in the same practice session and training shallow recognition rather than active recall.
2. Correct answers progressed along a rigid, flat interval ladder (3 days, 7 days, 14 days and mastered) with no ease factor, no per-card difficulty memory, no lapse tracking, and no explicit interval storage.

We addressed this in two verified phases: first resolving the immediate-reappearance defect in isolation with dedicated test coverage, and then implementing a complete ease-factor-driven spaced repetition model with an append-only database migration.

## Step 1: The Immediate-Reappearance Fix

In `DeterministicReviewScheduler.next(card:outcome:now:)`, `.incorrect` and `.inaccurate` outcomes previously assigned `updated.dueAt = now`.
When a learner failed a move, the card remained due immediately and would reappear within seconds during the same practice session.
Learning science and spaced-repetition principles establish that immediate re-testing measures fleeting working-memory recognition rather than durable retrieval strength.

The fix was implemented test-first:
A new test `incorrectAndInaccurateAnswersDoNotRescheduleImmediately` was added to `TrainingDomainTests`, asserting that failed cards are rescheduled at least one calendar day into the future.
After observing the test fail against the old behavior, `DeterministicReviewScheduler` was updated to calculate `updated.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now`.
All 175 tests in the app test suite passed.

## Step 2: Fuller Ease-Factor Model & Schema Migration

### Schema Migration (`v12_spacedRepetition`)

To support spaced repetition without relying on fragile interval inference from timestamp deltas, three columns were added to the `trainingCard` table in `Packages/Persistence/Sources/Persistence/Schema.swift`:

1. `easeFactor`: `.double`, `notNull`, defaulting to `2.5` (the standard SM-2 starting multiplier).
2. `lapseCount`: `.integer`, `notNull`, defaulting to `0` (tracks total lifetime lapses for difficulty dampening and leech detection).
3. `intervalDays`: `.double`, `notNull`, defaulting to `0.0` (stores the explicit scheduled interval in days to avoid timezone and clock drift).

The migration followed the project's append-only convention.
`TrainingCardRecord` was updated with the three new properties, default initializers, and reconciliation validation.
`GameStore.reconcileTrainingCards` preserves existing `easeFactor`, `lapseCount`, and `intervalDays` when card answers remain unchanged across report reconciliations, and resets them to clean defaults (`2.5`, `0`, `0.0`) when an answer changes.

A dedicated test `v12MigrationPreservesExistingCardsAndAddsSpacedRepetitionDefaults` was added to `Packages/Persistence/Tests/PersistenceTests/PersistenceTests.swift` along with updated migration chain assertions.

### Scheduling Algorithm

The scheduling logic in `DeterministicReviewScheduler` was replaced with an adapted SM-2 algorithm tailored to Chessanto's four outcome grades:

#### 1. `.strong` (Correct Recall)
- `consecutiveSuccesses += 1`
- `easeFactor = max(1.3, card.easeFactor + 0.15)`
  Ease increases by 0.15 on each clean recall, bounded by a 1.3 floor.
- `lapseCount = card.lapseCount` (unchanged)
- Interval calculation:
  - **Success 1 (`consecutiveSuccesses == 1`):**
    If the card previously lapsed (`card.lapseCount > 0`), interval is `1.0` day as a relearn confirmation step.
    If the card is fresh (`card.lapseCount == 0`), interval is `3.0` days (preserving step 1 of the familiar ladder).
    `masteryState` becomes `.review`.
  - **Success 2 (`consecutiveSuccesses == 2`):**
    If the card previously lapsed (`card.lapseCount > 0`), interval is `3.0` days.
    If the card is fresh (`card.lapseCount == 0`), interval is `7.0` days (preserving step 2 of the familiar ladder).
    `masteryState` becomes `.review`.
  - **Success 3+ (`consecutiveSuccesses >= 3`):**
    `masteryState` becomes `.mastered`.
    `let previousInterval = card.intervalDays > 0 ? card.intervalDays : (card.consecutiveSuccesses >= 2 ? 7.0 : 3.0)`
    `let calculatedInterval = round(previousInterval * updated.easeFactor)`
    `let maxInterval = max(30.0, 180.0 / (1.0 + 0.25 * Double(updated.lapseCount)))`
    `intervalDays = min(maxInterval, max(previousInterval + 1.0, calculatedInterval))`
- `dueAt = Calendar.current.date(byAdding: .day, value: max(1, Int(updated.intervalDays)), to: now) ?? now`

#### 2. `.inaccurate` and `.incorrect` (Lapses)
- `consecutiveSuccesses = 0`
- `masteryState = .learning`
- `lapseCount = card.lapseCount + 1`
- `easeFactor = max(1.3, card.easeFactor - 0.2)`
  Ease decreases by 0.2 per lapse, clamped at the 1.3 floor.
- `intervalDays = 1.0`
- `dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now`

#### 3. `.playable` (Partial Credit / Alternate Idea)
- `consecutiveSuccesses = 0`
- `masteryState = .learning`
- `easeFactor = card.easeFactor` (unchanged: a playable idea is not a blunder, but not clean recall either)
- `lapseCount = card.lapseCount` (unchanged: not counted as a lapse)
- `intervalDays = 1.0`
- `dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now`

### Role of `lapseCount`

We decided that `lapseCount` actively influences spaced repetition behavior in three distinct, measurable ways:
1. Every lapse drops `easeFactor` by 0.2 (down to 1.3), which directly reduces future interval expansion multipliers.
2. A card that has lapsed (`lapseCount > 0`) uses a tighter post-lapse ladder (1 day confirmation -> 3 days -> graduation) compared to a fresh card (3 days -> 7 days -> graduation).
3. `lapseCount` acts as a leech dampener on the maximum graduation interval via `max(30.0, 180.0 / (1.0 + 0.25 * Double(lapseCount)))`.
   A fresh card can expand up to 180 days (~6 months), while a card with repeated lapses is capped progressively lower (e.g. ~102 days after 3 lapses, with a hard floor of 30 days), ensuring problematic tactical motifs are never scheduled too far out.

### Test Changes

Two existing tests were updated deliberately:
1. `deterministicScheduleTransitionsToMasteredAfterThreeStrongRecalls`:
   Previously asserted a flat 14-day interval.
   Under the ease-factor scheduler with `consecutiveSuccesses == 2` transitioning to 3, the prior 7-day interval is scaled by the updated ease factor (2.5 + 0.15 = 2.65), producing `round(7.0 * 2.65) = 19` days.
   The test was updated to assert `intervalDays == 19.0` and `dueAt` 19 days out.
2. `playableResetsSuccessesAndIsDueTomorrow`:
   Maintained its existing assertion of 1-day interval and `.learning` state, with additional verification that `easeFactor` and `lapseCount` remain unchanged.

Three new tests were added to `TrainingDomainTests`:
- `easeFactorIncreasesOnStrongRecallAndIsFlooredOnDecreases`: verifies +0.15 ease increase, -0.2 decrease on lapses, and the 1.3 floor clamp.
- `freshCardFollowsStandardLadderAndScalesOnGraduation`: verifies the 3d -> 7d -> 21d -> 65d progression for fresh cards.
- `lapsedCardRelearnsWithTighterLadderAndLapseDampenedCeiling`: verifies lapse tracking, ease drops, 1d -> 3d -> 8d relearn steps, and dampened interval scaling.

## Validation Results

1. `swift test` from `Packages/Persistence/`:
   - 44 tests passed across 2 suites (was 43 baseline).
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build`:
   - `** BUILD SUCCEEDED **`
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test`:
   - 178 tests passed across 34 suites (was 174 baseline).
   - `** TEST SUCCEEDED **`
4. `swift test` in `Packages/ChessCore`:
   - 29 tests passed across 1 suite.
