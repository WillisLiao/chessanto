# Next session: M2 - engine integration and move classification

This is a self-contained execution plan for a fresh session with no prior context.
It was prepared by a session that read all the relevant source (including the chesskit-engine internals) and did a real, live Stockfish run in this repo, so the facts below are verified, not guessed.
Follow it step by step; the design decisions are already made, do not re-derive or re-litigate them.
Read `PLAN.md`'s "Analysis pipeline" section and M2 milestone for product context, but where this file is more specific, this file wins.

## Where things stand

M1 is done and pushed to `main` at https://github.com/WillisLiao/chessanto.
The app builds, imports PGNs (file/drag-drop), persists games via GRDB, and replays them move-by-move through a SwiftUI board and move list.

A prep session (2026-07-17) then de-risked M2 before this session:

- **A live Stockfish run has been verified in this repo.**
  `swift run --package-path Packages/EngineKit engine-smoke` boots the real in-process Stockfish 17 and asserts real search output.
  Verified output on this machine: startpos depth 15 gave `cp +38, pv e2e4 e7e5 g1f3 b8c6 f1b5 g8f6`; a white-to-move position without the white queen gave `cp -725` (proving the side-to-move sign convention below); a black-to-move mate-in-1 gave `mateIn 1, bestmove d8h4`.
  Run the smoke first thing this session; it should print `OK: live Stockfish verified ...` and exit 0.
- **The NNUE networks story is solved** (see engine fact 1 below - they are mandatory, not optional).
  `scripts/fetch-nnue.sh` downloads and hash-verifies both networks into `App/Resources/`; the files are gitignored, so run the script if they are missing.
  `project.yml` now has a working resources build phase (the old `resources:` key was silently ignored by XcodeGen and has been fixed), verified to copy both `.nnue` files into `Chessanto.app/Contents/Resources/`, which is exactly where chesskit-engine's `Bundle.main` auto-lookup finds them.
- `AnalysisEngine` gained `multiPVRank` on `EngineInfo` (without it you cannot tell line 1's score from line 3's) and a `setOption(name:value:)` passthrough.

## Verified engine facts (each one is a landmine if forgotten)

These were verified against chesskit-engine 0.7.0's actual source (checked out at `Packages/EngineKit/.build/checkouts/chesskit-engine/`) and confirmed by the live smoke run.

1. **The NNUE files are required, and a missing net kills the whole app.**
   chesskit-engine compiles Stockfish with `NNUE_EMBEDDING_OFF` (its `Package.swift`), and Stockfish 17 has no classical-eval fallback: starting a search with no net loaded prints "The engine will be terminated now." and calls `exit(EXIT_FAILURE)` **in-process** (`src/nnue/network.cpp:258`), killing Chessanto itself.
   The app side is already handled: the nets are bundle resources, and `EngineType.stockfish.setupCommands` auto-sends `EvalFile`/`EvalFileSmall` pointing at any `nn-1111cefa1111.nnue`/`nn-37f18f62d772.nnue` found in `Bundle.main`.
   Still, guard it: before starting the engine, check both files exist in `Bundle.main` and surface a clear "analysis unavailable" error instead of booting the engine if not.
   (The earlier M1-era note that "Stockfish 17 has an embedded default network" was wrong for this build and has been corrected in `HANDOFF.md`.)
2. **Engine scores are side-to-move relative, not white-relative.**
   `score cp X` / `mate N` are from the perspective of the side to move in the position you sent (empirically: white to move without his queen reported `cp -725`; black to move with mate-in-1 reported `mate +1`).
   Every consumer in M2 must normalize; the rule in this plan is: **normalize to white-perspective once, at write time, and store only white-perspective values in the DB** (see step 4).
   Sign bugs here are the classic chess-tool bug; the unit tests in step 5 must include black-to-move cases.
3. **Starting the engine hijacks the process's stdout.**
   `Engine.start()` `dup2()`s stdout into the engine's read pipe, so `print()` stops reaching the terminal for the rest of the process's life.
   Debug with stderr (`FileHandle.standardError`) or `os_log`, never `print()`; the smoke harness does this.
4. **Engine responses need a free main run loop.**
   Engine output is delivered via `NSFileHandle` run-loop notifications scheduled on the main thread; if the main thread is blocked, responses never arrive.
   This is why chesskit-engine's own Stockfish tests are disabled upstream, and why our live verification is an executable (`engine-smoke`, synchronous `main.swift` + detached task + `RunLoop.main.run()`) rather than an XCTest.
   In the GUI app this is free (AppKit runs the main run loop), but never block the main thread waiting on engine output.
5. **Only one live engine instance can exist per process.**
   The stdout/stdin `dup2` is process-wide, so a second `Engine.start()` steals the first engine's I/O.
   Consequence: one shared `AnalysisEngine` owned by one app-level service; batch analysis and live infinite analysis must share it, never run two engines.
6. **`AnalysisEngine.updates` is a single-consumer stream.**
   Exactly one task may iterate it (the service's routing loop in step 6); everything else observes published state derived from it.
7. **MultiPV rank arrives per info line.**
   With `start(multipv: 3)` each depth iteration emits up to 3 `.info` updates; `EngineInfo.multiPVRank` is 1-based and `nil` means rank 1 (Stockfish omits it when MultiPV is 1).
   Rank 1 is the eval and best move; ranks 2-3 exist for the lines panel and future coach payloads.
8. **Generation tags are applied at receipt time.**
   `setPosition` bumps the generation and sends `stop`, but an info already in flight from the old search would be tagged with the new generation.
   Step 2 closes this hole inside `AnalysisEngine` itself (wait for the old search's terminating `bestmove` before bumping), which is what makes "never show a stale eval" achievable.
9. **Thread count quirk.**
   chesskit-engine sets Stockfish's `Threads` to `coreCount - 1` from whatever `coreCount` you pass, and its own default resolves to 1 thread on every machine.
   `AnalysisEngine.start()` already passes `activeProcessorCount - 1`; leave that alone.
10. **Debug builds of Stockfish are roughly 5-10x slower** (SPM/Xcode compile the vendored C++ with -O0 in Debug).
    Functional work can happen in Debug, but do the ~30s-per-game acceptance timing on a Release build, or you will chase a fake performance problem.

## Fixed conventions for M2 (decided; use them everywhere)

- **plyIndex**: 0 is the starting position; position `p` is the position after mainline move `p`; move `p` (1-based) transitions position `p-1` to position `p`.
  This matches `GameReplayViewModel.moveIndices`, whose element 0 is `game.startIndex`.
- **DB stores white-perspective values.**
  `analysis.scoreCentipawns` and `analysis.mateIn` are white-perspective (positive = good for White, `mateIn` positive = White mates in N).
  Normalize at write time using the side to move of the FEN you searched: if the FEN's second field is `b`, negate both `cp` and `mate` before storing.
- **`analysis.principalVariation`** is the UCI moves of the line from that position, space-joined (e.g. `"e2e4 e7e5 g1f3"`).
- **Quality levels** (UCI `go movetime`): Fast = 100 ms, Standard = 350 ms, Deep = 2000 ms, always MultiPV 3.
  Standard at 350 ms keeps an ~80-ply game under the ~30 s acceptance bar while staying within PLAN.md's "~0.5s/move".
- **Cache rule**: a ply is analyzed if any rank-1 row exists for `(gameId, plyIndex)`; a game is analyzed if every ply 0..N has one.
  Skip analyzed plies during a run (this is also crash/cancel resume for free).
  Quality upgrades happen only via an explicit "Re-analyze" action that deletes the game's analysis rows first; no depth-floor heuristics.
- **Win probability (Lichess model)**, applied to white-perspective cp, yielding White's win probability in 0..100:
  `winP = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)`
  For mate scores skip the formula: white-perspective `mateIn > 0` means `winP = 100`, `mateIn < 0` means `winP = 0`.
  The mover's win probability is `winP` if White moved, else `100 - winP`.
- **Per-move accuracy (Lichess formula)**, where `drop` is the mover's win-probability drop clamped to >= 0:
  `accuracy = 103.1668 * exp(-0.04354 * drop) - 3.1669`, clamped to 0..100.
  Game accuracy per player = arithmetic mean of that player's per-move accuracies.
- **Classification of move `p`** (uses only rank-1 rows): let `before` = mover's winP at position `p-1`, `after` = mover's winP at position `p`, `drop = max(0, before - after)`.
  - **Best**: the played move's UCI equals the first move of position `p-1`'s rank-1 PV.
  - **Missed Win** (overrides the drop bands when it fires): `before >= 90` (or position `p-1`'s rank-1 line was mate for the mover) and `after <= 70` and the move was not Best.
  - Otherwise by drop: **Excellent** < 2, **Good** < 10, **Inaccuracy** < 20, **Mistake** < 30, **Blunder** >= 30.
  - **Brilliant** is deliberately out of M2 (needs sacrifice detection; revisit with M5's theme detection). Keep a `brilliant` enum case reserved but never assigned.
  - Worked example: White's move with stored evals +50cp before and -250cp after gives winP 54.6 then 28.5, drop 26.1, so Mistake.
- **Terminal positions**: if the game's last SAN ends with `#`, do not search the final position (a mated position has no meaningful search).
  Synthesize its rank-1 record instead: `scoreCentipawns = nil`, `mateIn = (white delivered mate ? +99 : -99)`, `principalVariation = ""`, `depth = 0`; treat `|mateIn| == 99` as "game over" in UI labels (bar pinned full, graph pinned to 100/0).
  Also guard the collector against `bestmove "(none)"` (Stockfish emits it if a search is somehow started in a terminal position): treat it as search end with whatever infos arrived.

## What to build, in order

Each step ends with a verification; do not continue past a failing verification.

### Step 0 - Preflight (15 min)

1. `scripts/fetch-nnue.sh` (no-op if nets present), then `xcodegen generate`.
2. `swift run --package-path Packages/EngineKit engine-smoke` - must end with `OK: live Stockfish verified` and exit 0.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto build` - must succeed.
4. `swift test` in `Packages/ChessCore`, `Packages/EngineKit`, `Packages/Persistence` - all green.

### Step 1 - Persistence: `AnalysisRecord` + store methods

New `Packages/Persistence/Sources/Persistence/AnalysisRecord.swift` mirroring the existing `analysis` table (see `Schema.swift`; the table already exists, add no migration):
`id: Int64?`, `gameId: Int64`, `plyIndex: Int`, `fen: String`, `depth: Int`, `scoreCentipawns: Int?`, `mateIn: Int?`, `principalVariation: String`, `multiPVRank: Int` - `Codable, FetchableRecord, MutablePersistableRecord` with `databaseTableName = "analysis"` and the same `didInsert` pattern as `GameRecord`.

Store methods on `GameStore` (use GRDB's async API, e.g. `try await dbQueue.write {...}`, so callers never block the main thread):

- `saveAnalysis(_ records: [AnalysisRecord], gameId: Int64, plyIndex: Int) async throws` - in one transaction, delete existing rows for `(gameId, plyIndex)`, insert the new ones (the unique key on `(gameId, plyIndex, multiPVRank, depth)` makes blind re-insert throw, hence delete-first).
- `analysis(gameId: Int64) async throws -> [AnalysisRecord]` ordered by `plyIndex, multiPVRank`.
- `analyzedPlyIndices(gameId: Int64) async throws -> Set<Int>` (plies having a rank-1 row).
- `deleteAnalysis(gameId: Int64) async throws` (for Re-analyze).

Tests in `PersistenceTests` against the in-memory `GameStore()`: round-trip, delete-first replacement at same depth, `analyzedPlyIndices`, cascade on game delete.

### Step 2 - EngineKit: `go(movetime:)` and airtight generations

In `AnalysisEngine`:

- Add `public func go(movetimeMilliseconds: Int) async` sending `.go(movetime: ms)`.
- Track `private var isSearching = false`: set true in `go(...)`/`goInfinite()`, false when the listen task sees a `bestmove` (add an actor method the listen task calls).
- In `setPosition`: if `isSearching`, send `.stop` and poll-wait (10 ms steps, 300 ms cap) until `isSearching` is false, **then** bump the generation and send the new position.
  This closes engine fact 8's stale-tag window: after the bump, nothing from the old search can still arrive.

Keep `EngineKitTests` structural (constructing/awaiting APIs), and extend `engine-smoke` with one `go(movetimeMilliseconds: 300)` search asserting a scored rank-1 info and a bestmove arrive.
Verify: `swift run engine-smoke` still exits 0.

### Step 3 - ChessCore: UCI bridging

chesskit-swift already has what's needed; wrap it in the facade (verify signatures against `Packages/ChessCore/.build/checkouts/chesskit-swift/Sources/ChessKit/` as you go, per working style):

- `public func uciMove(at index: MoveIndex) -> String?`: from `game.moves[index.raw]`, return `start.notation + end.notation + (promotedPiece?.kind.notation.lowercased() ?? "")`.
  Castling is already king-from/king-to (e.g. `e1g1`) in chesskit-swift, which matches UCI; pawn `notation` is `""` so only real promotions append a letter.
- `public static func sanLine(fromUCI moves: [String], startingFEN fen: String) -> [String]`: start from `Position(fen:)`, repeatedly `EngineLANParser.parse(move:for:in:)` (it is `public`, takes the mover's color and position), collect `move.san`, apply the move via `Board(position:)` + `board.move(pieceAt:to:)` (complete promotions with the parsed `promotedPiece` via `board.completePromotion` if that is the API - check the source), stop at the first unparseable move.
  Known cosmetic gap: `EngineLANParser` never sets check state, so these SANs lack `+`/`#`; acceptable for the M2 lines panel.

Tests in `ChessCoreTests`: `uciMove` over the real fixture in `RealGameFixtureTests.swift` (assert ply 1 is `d2d4`, and the castling plies `10. O-O-O`/`10... O-O` yield `e1c1`/`e8g8`), a crafted promotion PGN asserting the trailing letter, and `sanLine` round-tripping the smoke run's PV `e2e4 e7e5 g1f3 b8c6 f1b5 g8f6` from the start FEN into `["e4", "e5", "Nf3", "Nc6", "Bb5", "Nf6"]`.

### Step 4 - AnalysisKit: pure math (no engine, no DB imports)

New files in `Packages/AnalysisKit/Sources/AnalysisKit/` (delete the placeholder `AnalysisKit.swift` content; keep the code dependency-free even though the manifest lists deps):

- `WinProbability.swift`: the winP formula + mate mapping + mover-perspective helper, all `public` pure functions over white-perspective values.
- `MoveClassification.swift`: `public enum MoveClassification: String, CaseIterable, Sendable { case best, brilliant, excellent, good, inaccuracy, mistake, blunder, missedWin }`.
- `MoveClassifier.swift`: input is per-ply `public struct PlyEvaluation: Sendable { let scoreCentipawns: Int?; let mateIn: Int?; let bestMoveUCI: String? }` (white-perspective, rank-1) plus per-move `playedUCI` and mover color; output `[MoveClassification]` for plies 1..N, exactly per the rules in "Fixed conventions".
- `Accuracy.swift`: per-move and per-player aggregation.

Tests are the heart of this step: winP known values (cp 0 -> 50; the worked example numbers 54.6/28.5), black-to-move normalization cases (classifier consumes white-perspective inputs, so test that a Black blunder computes the drop from Black's side), each band boundary (drop 1.99/2/9.99/10/20/30), Best-by-UCI-match, Missed Win firing and not firing, mate-score plies, accuracy formula values (drop 0 -> 100 after clamp, drop 20 -> ~40.0).

### Step 5 - App: `EngineService` (the single engine owner)

New `App/Sources/Chessanto/Analysis/EngineService.swift`, `@MainActor final class EngineService: ObservableObject`, created once in `ChessantoApp` as a `@StateObject` and injected via `.environmentObject` (engine facts 5 and 6; the service is the only consumer of `engine.updates`).

- Lazy `start()`: check both nets exist in `Bundle.main` (else set `@Published var unavailableReason: String?` and never boot), `await engine.start(multipv: 3)`, `setOption("Hash", "256")`, spawn the single routing task over `engine.updates`.
- Routing: if a batch collector is installed, feed it; else treat updates as live (drop anything whose `generation != liveGeneration`, publish rank-1 eval/depth and the top-3 PVs).
- Live API: `func showPosition(fen: String)` - debounce 200 ms (cancel-and-restart `Task.sleep`), then `liveGeneration = await engine.setPosition(fen:)`, `goInfinite()`; also `func stopLive()`.
- Batch API: `func analyze(record: GameRecord, fens: [String], quality: Quality) async throws` - walks plies, skips cached ones (`analyzedPlyIndices`), for each: `setPosition` -> install collector (a `CheckedContinuation` + last-info-per-rank dictionary keyed by `multiPVRank ?? 1`) -> `go(movetimeMilliseconds:)` -> await collector result -> normalize to white-perspective -> `saveAnalysis` (per ply, so cancel/crash resumes) -> update `@Published var batchProgress: (done: Int, total: Int)?`.
  Resume the continuation exactly once (guard a `resumed` flag), including on `bestmove "(none)"` and on cancellation (`stop()` the engine, let the terminating bestmove resume it, then rethrow `CancellationError`).
  Batch and live are mutually exclusive: `analyze` stops live first; `showPosition` during a batch only records the desired fen without touching the engine (the UI shows cached evals meanwhile), and live resumes when the batch ends.
- Throttle published live updates to ~10/s (engine infos can arrive far faster; unthrottled `@Published` writes will churn SwiftUI).

Factor the pure decision "is this update for the current live generation" and the collector's rank bookkeeping into small structs unit-testable in `ChessantoTests` without an engine.

Verification (E2E, not just tests): temporarily log to stderr, run the app from Xcode, open the fixture game, trigger Analyze, watch rows appear: `sqlite3 ~/Library/Containers/com.chessanto.app/Data/Library/Application\ Support/Chessanto/chessanto.sqlite 'select plyIndex, multiPVRank, depth, scoreCentipawns, mateIn from analysis order by plyIndex, multiPVRank' | head -30` (the app is sandboxed, so the DB lives under `~/Library/Containers`; if that path doesn't exist, check the non-sandbox `~/Library/Application Support/Chessanto/`).
Confirm white-perspective signs: plies where Black is to move must not flip sign in the stored column (e.g. a roughly equal opening stays within +-100 for both parities).

### Step 6 - App: analysis UI (eval bar, graph, badges, progress)

Wire into `GameReplayView`/`GameReplayViewModel` (`App/Sources/Chessanto/`):

- `GameReplayViewModel` additions: precompute `fens: [String]` aligned with `moveIndices`; `playedUCIs: [String?]` via `uciMove(at:)`; load cached analysis on init (via the store; inject `GameStore` alongside the record - `GameLibrary` owns the store today, pass it through) and derive `classifications`, `whiteAccuracy`, `blackAccuracy` with AnalysisKit; expose `evalForCurrentPosition` preferring live (when generation-current) over cached.
- `EvalBarView`: vertical bar the height of the board, ~24 pt wide, white fill fraction = white winP / 100 from the bottom, 0.25 s ease animation, small label with pawns (`+0.4`, `-1.2`) or `M5`/`-M3` (white perspective).
- `EvalGraphView`: full-game strip under the board; y = white winP (invert so 100 is top), area fill split at the 50 line, vertical marker at current ply, click/drag maps x to ply and calls `viewModel.jump`.
- Move list badges: colored capsule per move using the classification (system colors are fine for M2: best/excellent green, good gray, inaccuracy yellow, mistake orange, blunder red, missedWin purple); also a small badge on the board's destination square for the currently shown move.
- Toolbar: Analyze button with a quality picker (Fast/Standard/Deep), determinate progress + Cancel while running, and a Re-analyze menu item (calls `deleteAnalysis` then analyze).
  Accuracy summary ("White 87.2 · Black 74.9") above the move list once analyzed.
- Lines panel: three rows under the board - eval + first ~6 SAN moves of each MultiPV line (via `sanLine`), display-only in M2.

Verification is visual and picky (per the project's standard): bar direction matches who is better, graph matches the game's story, badges sit aligned in the move list, no layout jump when analysis completes.

### Step 7 - Live analysis while scrubbing

- On `currentIndex` change (and on view appear), call `engineService.showPosition(fen:)`; on view disappear, `stopLive()`.
- The eval bar/lines panel show live values only when `update.generation == liveGeneration` (already enforced in the service); on position change, immediately show the cached eval for the new ply (never a stale live one) while the live search spins up.
- Acceptance drill: hold the right-arrow key through the whole fixture game and back; the bar must never show the previous position's eval against the new position (engine fact 8's fix + generation filtering is what makes this pass), and depth/eval should visibly refine when you stop on any position.

### Step 8 - Acceptance pass and spot-check

From `PLAN.md` M2, all of:

1. ~40-move game on Standard in under ~30 s on this machine - time it in a **Release** build (engine fact 10), stderr-log the wall time around `analyze`.
2. Classifications broadly match chess.com/Lichess for 3 real games.
   Fetch fresh ones like M1 did: `curl -H "User-Agent: Chessanto dev" https://api.chess.com/pub/player/<user>/games/archives`, take a recent archive, import 3 games that chess.com has Game Review data for (or run them through Lichess analysis), and compare blunder/mistake counts and locations.
   Broadly match means: the same moves flagged as blunders/mistakes within one severity step; exact counts need not match (chess.com's exact thresholds are proprietary).
   If systematically off, the only knobs to touch are the Excellent/Good boundary and the Missed Win thresholds; do not touch the published formulas.
3. Re-opening an analyzed game shows evals, badges, and accuracy instantly (from cache, before any engine start).
4. The rapid-scrub drill from step 7 shows no stale evals.
5. All package tests + app tests green; `engine-smoke` exits 0.

### Step 9 - Wrap up

Update `handoffs/HANDOFF.md` (M2 done, key decisions), append `devlogs/<date>.md`, write `handoffs/NEXT-SESSION-M3.md` (Exploration Mode: variation play, tree, lines-panel adoption - see PLAN.md M3), commit and push working code + docs together.

## Working style notes (carried forward from M1/prep, they keep paying off)

- Verify third-party APIs against the checked-out source in `.build/checkouts/` before writing code against them; both prior sessions caught wrong assumptions this way (M1: chesskit API surface; prep: the NNUE and stdout facts above).
- Do real E2E verification through the built app, not just `swift test` (M1's only real bug was found that way); for M2 that means watching the eval bar and badges against a real game, and reading actual DB rows.
- Fetch real chess.com games for fixtures/spot-checks rather than fabricating PGNs.
- After adding/removing files in `App/`, rerun `xcodegen generate` (the `.xcodeproj` is gitignored); package-internal files need no regen.
- Debug engine issues on stderr, never stdout (engine fact 3).
- Commit and push milestone work together with updated handoffs and a dated devlog entry.
