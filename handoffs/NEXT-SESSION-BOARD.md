# Next session - the board

Bootstrap for Priority 3 of the 2026-07-30 product review.
Nothing in this document is implemented.

Read `handoffs/HANDOFF.md` first.
The review that produced this is `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` (Priority 1 of which is now done); this document expands its Priority 3 into a workable plan.

## Why this is the next thing

The board is the surface the user physically touches, and it is the one place where a beginner will decide the app is broken rather than that they are.
Priority 1 fixed what the app *knows*.
This fixes what it *feels like*.

Everything here is self-contained: no engine work, no analysis changes, no schema changes.

## The one confirmed bug

**A promotion in Practice is probably ungradeable. Reproduce it before fixing it.**

`PracticeSessionViewModel.select` builds a four-character UCI:

```swift
let attemptedUCI = selectedSquare.algebraic + square.algebraic   // "e7e8"
```

`DefaultTrainingMoveEvaluator.evaluate` then does two things with it, and both look wrong for a promotion:

1. `ChessGame.replayLine(fromUCI: [attemptedUCI], startingFEN: card.preMoveFEN)` - `replayLine` completes a promotion only when the parsed move carries a `promotedPiece` (`ChessGame.swift:303`), which a four-character UCI does not.
2. The cached-line shortcut at `TrainingDomain.swift:320` compares `attemptedUCI` against `rankedLines.first?.principalVariationUCI.first`, which the engine emits as five characters (`e7e8q`), so it can never match.

Expected symptom: a practice card whose best move is a promotion cannot be answered correctly, and probably grades `.incorrect` even when the learner plays the right move.

Per the repository's bug-fix rule, reproduce this end to end first.
The cheapest route is a unit test in `App/Tests/ChessantoTests/TrainingDomainTests.swift` with a card whose `preMoveFEN` has a pawn on the seventh rank and whose rank-one PV starts with a promotion.
`Packages/ChessCore/Tests/ChessCoreTests/LegalMoveCountTests.swift` shows the fixture style for sparse, out-of-book positions, which promotion positions naturally are.

## The seam that already exists

`ChessGame.isPromotion(from:to:at:)` is defined at `Packages/ChessCore/Sources/ChessCore/ChessGame.swift:144` and has **zero call sites**.
Its own doc comment says it is "used by the board UI to decide whether to prompt for a promotion piece before calling `playMove`".
It was built for this and never wired up.

`ChessGame.playMove(from:to:at:promotion:)` takes a `PromotionKind` and defaults it to `.queen`, auto-completing the promotion at `ChessGame.swift:171`.
So underpromotion is currently unreachable from the UI, and the interactive paths never ask.

## Where the board is used

`App/Sources/Chessanto/Board/BoardView.swift` is the only board on macOS. Three call sites:

- `GameReplayView.swift:180` - interactive, drives `handleSquareTapped` and `viewModel.playMove(from:to:)`.
- `Training/PracticeBoardSection.swift:25` - interactive, drives `PracticeSessionViewModel.select(square:)`.
- `Board/LinePreviewBoardSection.swift:14` - display only, no `onSquareTapped`.

The iPhone companion has a separate, read-only `CompanionBoardView` (`Mobile/Sources/ChessantoMobile/OfflineReportReader.swift:67`).
It is out of scope here unless the work naturally shares a type.

Note that the two interactive call sites have **two independent copies of the same select-then-move state machine**: `GameReplayView.handleSquareTapped` and `PracticeSessionViewModel.select`. They differ subtly already. Whatever interaction model this session lands on should be written once and used by both, or they will keep drifting.

## The work

### B1 - Drag and drop

`BoardView` is tap-source then tap-destination only, via a `Button` per square (`BoardView.swift:28`).
A user will try to drag a piece, nothing will happen, and they will conclude the board does not work.
This is the single most urgent item in the document.

Keep tap-to-move working alongside it; both are standard, and tap is the accessible path.
The per-square `Button` currently provides the accessibility element (`accessibilityIdentifier("square-...")`), which the AX-driven QA scripts in `scripts/` rely on, so do not remove it without giving the squares equivalent AX identity. `scripts/axprobe.swift` and `scripts/axclick.swift` are the tooling that reads and drives the app.

### B2 - Promotion picker

Wire `isPromotion` into both interactive paths, present a four-piece chooser, and pass the result through to `playMove(promotion:)` and to a five-character UCI in Practice.
This closes the confirmed bug above and makes underpromotion reachable.

### B3 - Piece animation

Pieces teleport between squares, so stepping through a game gives no sense of what moved.
`BoardView` positions pieces absolutely inside a `ZStack` by `square`, which is the hard case for SwiftUI animation: the natural fix is a stable identity per piece plus `matchedGeometryEffect` or an explicit position animation, rather than animating the `ZStack` contents wholesale.

Note the constraint already documented in `LinesPanelView`: the board sizes itself from leftover space via `GeometryReader` plus `.aspectRatio(.fit)`, so anything that changes the surrounding column's height visibly resizes the board. Do not introduce animation that reflows the layout.

### B4 - Move and capture sounds

There is currently no audio anywhere in the board (no `NSSound`, no `AVAudioPlayer`).
Distinct move and capture sounds, off by default or respecting a setting, are how a learner tracks what happened.
`GeneralSettingsView` is the existing home for a toggle.

### B5 - Right-click annotation arrows and circles

This is the primary tool for thinking about a position, and it is absent.
`BoardView` already draws engine-suggested arrows (`arrows:`, `ArrowShape` at `BoardView.swift:159`), so the drawing primitive exists; what is missing is user-authored annotations and a right-drag gesture to create them.

Decide explicitly whether annotations persist per position. If they do, that is a schema change and should be its own session.

### B6 - Coordinates

File and rank glyphs are drawn in-square at 16% of the square size (`BoardView.swift:127`), which is small for someone still learning the coordinate system.
Consider larger, or optional coordinates outside the board edge.

## Suggested order

1. Reproduce the promotion bug with a failing test.
2. B2, which fixes it and wires up the existing unused seam.
3. B1, the largest interaction change, sharing one state machine between both interactive call sites.
4. B3, then B4, then B6.
5. B5 last, and only after deciding the persistence question.

## Verification expectations

Unit tests for anything in `ChessCore` and for the promotion grading path.

Native end-to-end QA is expected for interaction work, because none of drag, animation, or sound is provable by unit test.
Note two environment facts found on 2026-07-30:

- Screen capture is refused in the agent environment (`could not create image from window`), so the accessibility tree via `scripts/axprobe.swift` is the way to read the UI. If you need real screenshots, ask the user to grant Screen Recording permission first.
- Drive the app against an isolated database copy using `CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1` and `CHESSANTO_DATABASE_PATH`, then delete the copy and verify the live database is unchanged. The live database's current hash is recorded in `handoffs/HANDOFF.md`.
- `scripts/axclick.swift` matches on a substring of the accessibility description. Clicking "Analyze" matches sidebar rows ending in "Analyzed"; use `--last` or a more specific string, and confirm the target with the window title afterwards.

## Known blocker in the library

One game fails to parse with `ChessKit.PGNParser.Error error 2`, and its modal "Load error" alert silently swallows clicks on the window beneath it.
This will interrupt AX-driven QA if you happen to select that game.
Dismiss the alert (`scripts/axclick.swift Chessanto "OK"`) before continuing.

Worth fixing on its own account: a parse failure should not leave the app in a state where the window looks interactive but is not.
