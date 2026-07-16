# Next session: M2 - engine integration and move classification

This is a bootstrap brief for a fresh session with no prior context.
Read `PLAN.md` in full first (especially the M2 section and the Analysis
pipeline section) - this file only summarizes what's already true in the
repo and what's left to decide/build, it doesn't replace the plan.

## Where things stand

M1 is done and pushed to `main` at https://github.com/WillisLiao/chessanto.
The app builds, imports PGNs (file/drag-drop), persists games via GRDB,
and replays them move-by-move through a working SwiftUI board and move
list. None of that touches the engine yet.

`EngineKit`'s `AnalysisEngine` actor
(`Packages/EngineKit/Sources/EngineKit/AnalysisEngine.swift`) already
exists and is more finished than a typical M1 leftover - it wraps
`chesskit-engine`'s in-process Stockfish with:

- `start(multipv:)` - boots the engine with an explicit core count
  (needed - `chesskit-engine` defaults to single-threaded otherwise, see
  the doc comment).
- `setPosition(fen:moves:)` - stops any search, sets a new position,
  bumps and returns a `generation` counter.
- `goInfinite()` / `go(depth:)` / `stop()` / `shutdown()`.
- `updates: AsyncStream<EngineUpdate>` - yields `.info(EngineInfo)` and
  `.bestMove(generation:move:)`, each `EngineInfo` tagged with the
  generation it was computed under.

The generation-counter plumbing PLAN.md's risk section asks for (so a
scrubbing UI can drop stale results) is already implemented at the
EngineKit layer. **Nothing consumes this yet** - it isn't wired into the
app, there's no eval bar, no classification, no caching. That's all of M2.

`Persistence`'s schema (`Packages/Persistence/Sources/Persistence/Schema.swift`)
already has an `analysis` table (gameId, plyIndex, fen, depth,
scoreCentipawns, mateIn, principalVariation, multiPVRank) ready to receive
cached analysis - no `AnalysisRecord`/store methods exist yet, only the
table.

`chesskit-engine` 0.7.0's own Stockfish tests are disabled upstream since
Stockfish 17 ("failing in CI... to be investigated") - EngineKit's own
tests are intentionally structural only. **A live engine run has not been
verified in this repo yet.** First thing to check in M2: does
`AnalysisEngine.start()` + `setPosition` + `go(depth:)` actually produce
real `.info` responses when run for real (not just construct without
crashing)? If chesskit-engine's Stockfish integration is itself broken on
this version, that's a blocker worth surfacing immediately rather than
discovering it after building UI on top of it.

## What M2 needs (per PLAN.md)

1. Real engine verification first (see above) - a small throwaway or
   permanent integration test/manual run that starts the engine, feeds it
   the standard starting position, runs `go(depth: 15)`, and confirms a
   real centipawn score and PV come back. Do this before building UI on
   top of an unverified engine.
2. `AnalysisRecord`/store methods in `Persistence` to read/write the
   existing `analysis` table.
3. A background analysis queue (progress + cancellation) that walks a
   game's positions and analyzes each with `AnalysisEngine`, caching
   results by (FEN, depth).
4. Eval bar UI next to the board, and an eval graph across the game
   (click to jump to a move) - wire into the existing `GameReplayView`/
   `GameReplayViewModel` in `App/Sources/Chessanto/`.
5. Live infinite analysis of the currently displayed position while
   scrubbing: debounce quick navigation, call `setPosition` +
   `goInfinite()`, and use the generation tag on incoming `EngineInfo` to
   drop stale results - the mechanism exists in EngineKit, the debounce/
   drop logic on the consuming side does not yet.
6. Move classification (Best/Excellent/Inaccuracy/Mistake/Blunder/Missed
   Win) and per-game accuracy, using the win-probability and accuracy
   formulas spelled out in PLAN.md's Analysis pipeline section - these
   are exact formulas, don't re-derive them, use what's written there.
   Classification badges on the move list and board.

## Acceptance bar (from PLAN.md, M2)

Analyze a ~40-move game on Standard quality in under ~30s on an M-series
Mac; classifications broadly match what chess.com/Lichess report for the
same game (spot-check against 3 real games - `RealGameFixtureTests.swift`
in ChessCore already has one real chess.com game fixture with a verified
final FEN, reuse or extend it); re-opening an analyzed game shows results
instantly from cache; scrubbing rapidly through the game never shows a
stale eval for the wrong position.

## Working style notes from the M1 session (carry these forward)

- Verify third-party APIs against actual cloned source before writing
  code against them - guessing chesskit-swift/chesskit-engine's API
  surface wasted a full pass in M1; reading the real source got it right
  first time.
- Do real E2E verification, not just `swift test` - M1's real bug (a
  `.font(.system(size: 1000))` sizing hack producing degenerate
  accessibility geometry) was only caught by actually driving the built
  `.app` through its UI. For M2, that means actually running analysis on
  a real game and watching the eval bar/badges, not just unit-testing the
  math in isolation.
- Fetch a fresh real game from chess.com's public API for fixtures rather
  than fabricating PGN - `curl -H "User-Agent: ..." https://api.chess.com/pub/player/<username>/games/archives`
  then the last archive URL, real fixtures already proved their worth
  (chess.com's own `[CurrentPosition]` tag was free ground truth for
  cross-checking the PGN parser).
- Regenerate the Xcode project with `xcodegen generate` after adding/
  removing files - `Chessanto.xcodeproj` is gitignored and not committed.
- Commit and push when milestone work is done, alongside updated
  `handoffs/HANDOFF.md` and a dated `devlogs/` entry, per the standing
  convention for this project.
