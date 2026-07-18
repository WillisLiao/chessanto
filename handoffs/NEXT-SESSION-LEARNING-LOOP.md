# Next session - Active Learning Loop

Use GPT 5.5 at medium reasoning for this task.

## Prompt to paste into the next Codex task

Continue Chessanto from the current `main` branch.
Read `AGENTS.md`, `handoffs/HANDOFF.md`, `handoffs/NEXT-SESSION-LEARNING-LOOP.md`, and the latest section of `devlogs/2026-07-18.md` before changing code.
Use the `implement` and `tdd` skills for execution.
For every UI or interaction decision, pair the normal frontend/interface design skill with `ui-ux-pro-max`.
Open the built app and reproduce each user-facing state before modifying it.
Implement the Active Learning Loop vertical slice described below from end to end.
Keep the user-approved forced-light warm-neutral and brass design system.
Do not redesign the board, replace the cburnett pieces, or introduce green into the application chrome.
Work in small tested slices, run every gate, update the handoff and devlog, then commit and push.

## Why this is the next product move

Chessanto now presents analysis clearly, but the user still consumes most of it passively.
The strongest path toward being genuinely helpful and habit-forming is to turn each important mistake into an active recall exercise.
The desired motivation is respectful and learning-centered.
Do not add manipulative streak pressure, artificial scarcity, or noisy reward effects.

The next release should answer one question immediately after analysis:

> What should I practice right now so I play the next game better?

## Current product state

The UI/UX execution pass is complete.
The app uses a forced-light warm ivory, graphite, and brass visual system by explicit user request.
The board remains the visual center.
Moves use a compact two-column notation table.
Reports use cards and restrained classification chips.
Coach is a docked panel at wide widths and a right-side slide-over at narrow widths.
Coach can follow the board or pin to a move or key moment.
The sidebar has a stable bottom action bar, and the import path is no longer hidden in toolbar overflow.
Onboarding, settings, fetch, dashboard, and empty states share the same design tokens.
A dedicated macOS app icon is included.

The full package suite, app suite, Release build, and live Coach grounding harness are green at handoff.

## Product audit

### What is already strong

- The core promise is distinctive: local analysis plus mechanically verified coaching.
- The board, move table, eval graph, and Report now form a coherent analysis workspace.
- The Coach panel no longer destroys spatial context when opened.
- Position pinning makes Coach conversations understandable and predictable.
- The forced-light palette is calm, high-end, and appropriate for long study sessions.
- The brass accent is memorable without competing with the chessboard.
- Import, fetch, onboarding, settings, empty states, and progress now speak the same visual language.
- Trust is unusually strong because engine facts and generated prose have explicit verification gates.

### What still limits usefulness and return frequency

- A completed analysis ends with information rather than a next action.
- The Progress dashboard reports trends but does not help the user improve one concrete weakness.
- Key moments are readable, but the user is not required to retrieve or apply the better move.
- Coach answers can be long and generic with small local models.
- The game library has no search, filtering, or sorting for a larger collection.
- There is no persistent learning state, due queue, or evidence that a recurring mistake has been mastered.
- Accessibility is mostly structural and lacks a dedicated UI-test matrix.
- A final 900-point-wide pixel pass is still desirable after the sidebar-width increase because the last Codex environment could build and inspect prior screenshots but could not create a new native window.

## Scope for this session

Build one complete tracer-bullet feature:

> From an analyzed game, start a practice session for its key moments, choose moves on the real board, receive engine-grounded feedback, and persist mastery so Progress can offer the next due lesson.

Do not build a general puzzle platform.
Do not add cloud sync, social features, leaderboards, subscriptions, or remote accounts.
Do not make Coach generation a dependency for completing practice.

## Domain model

Create a small domain module rather than embedding training logic in a SwiftUI view.

Recommended concepts:

- `TrainingCard`
  - Stable identifier.
  - Source game ID.
  - Source ply.
  - Pre-move FEN.
  - Side to move.
  - Best known ranked lines.
  - Mistake classification.
  - Detected themes.
  - Optional rule-based explanation.
- `TrainingAttempt`
  - Card ID.
  - Attempted UCI move.
  - Timestamp.
  - Evaluation loss against the best move.
  - Outcome.
  - Hint count.
- `MasteryState`
  - New.
  - Learning.
  - Review.
  - Mastered.
- `ReviewSchedule`
  - Due date.
  - Consecutive successful recalls.
  - Last result.

Keep engine and database details out of the domain types.
Give the training evaluator one clear interface that accepts a card and a legal attempted move and returns typed feedback.

## Correctness rules

Do not grade only by exact equality with the engine's rank-one first move.
A human move can be equally strong without appearing first in a shallow MultiPV list.

Use this order:

1. Reject illegal moves using `ChessCore`.
2. Accept a move immediately if it matches a cached top ranked line.
3. Otherwise evaluate the attempted move from the card FEN.
4. Compare its white-perspective result with the cached best result from the mover's perspective.
5. Treat a move as successful when its loss stays within a documented tolerance.
6. Distinguish strong, playable, inaccurate, and incorrect outcomes with typed thresholds and tests.

Keep mate scores separate from centipawn scores.
Never convert a mate result into a fake large centipawn number.

## Persistence

Add one forward-only migration.
Do not modify prior migrations.

Recommended tables:

- `trainingCard`
- `trainingAttempt`

Use a unique key on source game ID plus source ply so rebuilding a report does not duplicate cards.
Persist the source facts needed to practice even if the report is not currently open.
Deleting a game should cascade to its cards and attempts.
Write migration tests for a real partial old schema and a current schema.

The first version can use a deterministic schedule:

- Incorrect: due again today.
- Playable: due tomorrow.
- Strong: due in three days.
- Strong twice consecutively: due in seven days.
- Strong three times consecutively: mastered and due in fourteen days.

Keep the schedule behind a domain interface so it can evolve without rewriting views or persistence.

## User experience

### Entry points

Add a primary `Practice key moments` action after a report has key moments.
Add a small `Practice` action on each key-moment card.
Turn the Progress dashboard's most prominent action into `Review next lesson` when a card is due.
When nothing is due, show the next review date and a secondary `Practice any position` action.

### Practice session

Reuse the real `BoardView` and board theme.
Show one position at a time.
Orient the board to the side that must move.
Keep the prompt short:

> Find the move you wish you had played.

The user should select and play a legal move exactly as in Exploration Mode.
Do not reveal engine arrows before the first attempt.

After the move:

- Strong move: show a calm positive confirmation and the verified reason.
- Playable move: acknowledge the idea, show the stronger move, and explain the difference.
- Incorrect move: restore the position, explain the tactical or strategic consequence, and offer `Try again`.
- Hint one: identify the relevant piece or theme.
- Hint two: show the origin square.
- Reveal: show the verified move arrow and short continuation.

Use motion sparingly.
A short card transition and restrained brass success glow are enough.
Do not add confetti.

### Session completion

Show:

- Cards completed.
- Successful first attempts.
- One recurring theme.
- Next due review.
- A direct `Back to game` action.

The result should feel rewarding because the user demonstrated understanding, not because the app manufactured urgency.

## Design requirements

Use the existing design tokens.
Protect the forced-light appearance.
Protect the board artwork, square themes, coordinates, last-move highlight, and flip behavior.
Maintain a 44 by 44 point effective target for primary controls.
Every icon-only control needs a visible tooltip and accessibility label.
Status must never rely on color alone.
Keyboard users must be able to move focus through hint, reveal, retry, and next controls.
Reduced-motion users should get an immediate transition.

Use `ui-ux-pro-max` to audit:

- Information hierarchy.
- Empty, loading, error, and completed states.
- Keyboard navigation.
- Contrast.
- Target sizes.
- Feedback timing.
- Narrow-window behavior.

## Engineering sequence

### Step 0 - Reproduce and baseline

Launch the app with an analyzed fixture.
Capture the current Report and Progress states at 900 and 1400 points.
Record the exact path from analysis completion to the current dead end.

Gate:
The baseline clearly shows where the new practice action will enter.

### Step 1 - Domain tests first

Add failing tests for outcome grading, mate handling, scheduling, deduplication identity, and mastery transitions.
Implement the domain types and pure evaluator policy until they pass.

Gate:
The domain suite is fast, deterministic, and engine-free.

### Step 2 - Persistence

Add the migration, records, CRUD, cascade behavior, and migration tests.

Gate:
Old and current schemas migrate forward, duplicate source positions do not duplicate cards, and deleting a game cascades.

### Step 3 - Card generation

Convert verified report key moments into cards.
Generate cards after report construction without duplicating them.
Do not create cards for facts that failed the existing fact audit.

Gate:
The real fixture creates the expected number of cards with exact source FENs and plies.

### Step 4 - Practice state machine

Create a dedicated observable view model with explicit states such as loading, prompt, evaluating, feedback, and completed.
Do not encode the flow as a collection of loosely related booleans.

Gate:
Unit tests cover retry, hint, reveal, next, completion, cancellation, and engine failure.

### Step 5 - Practice UI

Build the board-centered practice view.
Use the existing board interactions and design system.
Provide every state, including no cards and engine unavailable.

Gate:
One real card can be solved, retried, revealed, and completed entirely through the UI.

### Step 6 - Report and Progress integration

Add the report entry points and the due-card action on Progress.
Progress should show useful action even when there is only one analyzed game.

Gate:
The user can enter from either surface and return without losing the selected game.

### Step 7 - Accessibility and responsive pass

Exercise the full flow at 900 and 1400 points.
Run VoiceOver or raw AX inspection for labels, focus order, state announcements, and buttons.
Verify forced-light contrast under a system-dark desktop.

Gate:
The flow is understandable without color and operable without a mouse.

### Step 8 - Acceptance

Run all package tests.
Run the complete app test suite.
Run the live engine smoke test.
Run `coach-grounding`.
Run a Release build.
Complete one practice session from a real imported game and confirm attempts persist after relaunch.

Gate:
All checks are green and the persisted dashboard state matches direct database inspection.

## Acceptance scenario

1. Import or open a real game.
2. Analyze it.
3. Open Report and select `Practice key moments`.
4. Attempt one incorrect legal move and receive grounded corrective feedback.
5. Retry and play a strong move.
6. Use a hint on the next card.
7. Finish the session.
8. Open Progress and see the next due review.
9. Quit and relaunch.
10. Confirm mastery and due state persist.

## Explicit non-goals

- Do not add a streak counter in this slice.
- Do not add achievements or badges.
- Do not require the local LLM.
- Do not generate arbitrary puzzles from unverified model prose.
- Do not build spaced repetition beyond the deterministic schedule above.
- Do not tackle library search, promotion UI, or variation promotion in the same implementation.

## Ranked follow-up backlog after the learning loop

1. Add library search, filtering, and sorting for opponent, result, date, opening, and analyzed status.
2. Improve Coach response quality with concise-answer prompting, response-length controls, and a stronger recommended-model path.
3. Add the promotion picker and fix mainline-equivalent variation deduplication.
4. Add collapse controls for variation branches and design a real promote-variation operation.
5. Build stable screenshot-driven native UI regression tests for 900 and 1400 point layouts.
6. Add a signed and notarized distribution pipeline after credentials are explicitly supplied.
7. Evaluate Lichess import only after the learning loop proves useful.

## Handoff requirements

Update `handoffs/HANDOFF.md`.
Append the current devlog.
Record all schema and grading decisions.
Include screenshots of the completed practice flow, but keep large audit captures out of git.
Commit and push code plus documentation together.
