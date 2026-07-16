# Next session: M3 - Exploration Mode (variation play, tree, lines-panel adoption)

This is a bootstrap, not a fully de-risked execution plan like M2's -
read it, then re-derive the details from the current code and `PLAN.md`
rather than treating every line here as fixed.

## Where things stand

M1 and M2 are done and pushed to `main` at
https://github.com/WillisLiao/chessanto.
The app imports/persists/replays PGNs, runs real in-process Stockfish
analysis (batch, cached per ply, mutually exclusive with live), shows an
eval bar/eval graph/move classification badges/accuracy summary, and runs
live infinite analysis of whatever position is on screen while scrubbing
through the mainline with generation-tagged updates so nothing stale ever
renders.

Read `handoffs/HANDOFF.md`'s current-state section and `PLAN.md`'s M3
bullet before starting:

> Free variation play on the board, variation tree move list
> (promote/delete/collapse, "back to game"), variations persisted. Engine
> lines panel with clickable, adoptable MultiPV lines.
> **Accept:** from any game position, play a 5-move variation with a
> sub-variation inside it, watch the eval bar track every explored position
> live, delete the sub-variation, quit and relaunch, and the remaining
> variation is intact.

## What M2 already gives you to build on

- `Packages/Persistence`: a `variation` table already exists in
  `Schema.swift` (`gameId`, `parentPlyIndex`, `moveSAN`, `orderIndex`,
  `parentVariationId` self-referencing with cascade delete) but has **no**
  `VariationRecord` model or `GameStore` methods yet - that's this
  milestone's persistence work, mirroring the `AnalysisRecord` pattern M2
  added (delete-first replacement isn't the right shape here though;
  variations need real insert/update/delete-subtree semantics).
- `App/Sources/Chessanto/Analysis/EngineService.swift`: `showPosition(fen:)`
  / `stopLive()` already exist and are generation-safe. Free variation play
  should just keep calling `showPosition` with whatever FEN is on screen,
  variation or mainline - no EngineService changes should be needed for
  live eval tracking during exploration.
- `App/Sources/Chessanto/Analysis/LinesPanelView.swift`: currently
  **display-only** (per M2's plan, deliberately deferred). This milestone
  should make its lines clickable/adoptable - clicking a line's first move
  should play it as a new variation branch from the current position. Check
  `ChessGame.sanLine(fromUCI:startingFEN:)` (`Packages/ChessCore`) for
  turning a clicked PV back into playable SAN moves, and
  `ChessGame.playMove(san:at:)` / `playMove(from:to:at:)` (already exist)
  for actually playing them.
- `ChessCore`'s `MoveIndex`/`MoveTree` (from chesskit-swift) already
  supports variations natively (`MoveTree.Index.variation`,
  `mainlineIndices` filters to `.mainVariation`) - re-read
  `Packages/ChessCore/.build/checkouts/chesskit-swift/Sources/ChessKit/MoveTree/`
  before designing the tree UI; the underlying data structure may already
  do most of what you need, and `ChessGame` just needs new API surface to
  expose non-mainline navigation, promotion, and deletion.

## Suggested approach (re-derive, don't just follow)

1. Read the actual `MoveTree`/`MoveTree.Index` source first - variation
   promotion/deletion/collapse semantics should follow whatever chesskit-swift
   already models, not be reinvented.
2. Add `VariationRecord` + `GameStore` methods (insert one move at a time as
   it's played, not batch-replace; delete-subtree for "delete this
   variation"; load-all for reconstructing the tree on game open).
3. Extend `GameReplayViewModel` (or a new view model if variation state gets
   large) to track "am I on the mainline or in a variation" and expose
   whatever the move-list UI needs to render a tree instead of a flat list.
4. Wire board interaction (drag-and-drop or click-click) to play a move at
   the current position - `ChessGame.legalMoves`/`playMove` already exist
   from M1 but no UI currently calls them (M1/M2 are replay-only, no
   move input yet). This is probably the single biggest net-new chunk of
   work in this milestone.
5. Adopt the lines panel: clicking a line plays it as a variation.
6. Persist as moves are played (not just on some "save" action) so the
   accept criterion's "quit and relaunch, variation intact" works via
   normal crash-safety, matching M2's per-ply save pattern rather than a
   batch save at the end.

## Working style notes (carried forward, they keep paying off)

- Verify third-party APIs (chesskit-swift's `MoveTree`, in particular)
  against the checked-out source in `.build/checkouts/` before writing
  code against them.
- Do real E2E verification through the built app, not just `swift test`.
  If Screen Recording permission still isn't available in this
  environment, the 2026-07-17 devlog documents a working
  `osascript`/System Events accessibility-introspection method
  (`entire contents of window`) plus `cliclick` for driving the GUI and
  reading back state without screenshots - reuse that rather than
  rediscovering it, but note it could not see inside SwiftUI
  `LazyVStack`/`ScrollView` content (opaque provider group to System
  Events), so plan verification of tree/move-list UI accordingly (may need
  actual screenshots if Screen Recording permission becomes available, or
  a lighter-weight accessibility identifier strategy).
- After adding/removing files in `App/`, rerun `xcodegen generate` (the
  `.xcodeproj` is gitignored).
- Commit and push milestone work together with updated handoffs and a
  dated devlog entry.
