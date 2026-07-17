# Chessanto - Handoff

Living snapshot of project state.
Read this first at session start; update it at session end.

## Current state (2026-07-17)

- **M1 complete.** App builds, all tests pass, and the acceptance criteria in
  `PLAN.md` are met: a real chess.com PGN (fetched live from the public API,
  with `[%clk]` comments and both castling sides) imports through the actual
  UI, persists across quit/relaunch, and steps forward through the game move
  by move with the board and move list updating correctly.
- **M2 complete (2026-07-17): engine integration and move classification.**
  Followed `handoffs/NEXT-SESSION-M2.md` step by step; every step's
  verification passed. What's new:
  - `Persistence`: `AnalysisRecord` + `GameStore` analysis CRUD (async,
    delete-first replacement per ply - this is also crash/cancel resume).
  - `EngineKit`: `AnalysisEngine.go(movetimeMilliseconds:)`; `setPosition`
    now waits for an in-flight search's terminating `bestmove` before
    bumping the generation, closing the stale-tag window the prep session
    flagged. `engine-smoke` still exits 0 with this extended.
  - `ChessCore`: `ChessGame.uciMove(at:)` (chesskit-swift's `Move.lan` was
    already exact UCI) and `ChessGame.sanLine(fromUCI:startingFEN:)` for
    turning an engine PV back into SAN for the lines panel.
  - `AnalysisKit`: `WinProbability`, `MoveClassifier`, `Accuracy` - pure,
    engine/DB-free, exactly the Lichess-derived formulas fixed in the prep
    plan. 17 tests including the worked example and both perspectives.
  - `App`: `EngineService` (`@MainActor`, one shared `AnalysisEngine`,
    live infinite analysis and batch analysis mutually exclusive), wired
    into `GameReplayView` - eval bar, eval graph, move-list classification
    badges, Analyze/Re-analyze toolbar with quality picker and cancellable
    progress, and a display-only MultiPV lines panel. Live analysis follows
    ply changes (200ms debounced) and only trusts the engine's live eval
    when its FEN matches the currently displayed ply - cached DB values
    otherwise, so scrubbing never shows a stale eval.
  - Real E2E verification (Release build, driven via `osascript`/System
    Events accessibility introspection since Screen Recording permission
    wasn't available in this environment - see the 2026-07-17 devlog for
    the full method): Analyze on a real 55-ply chess.com game finished in
    a few seconds, DB rows had sane white-perspective evals, cache-instant
    reload was confirmed (accuracy + Re-analyze button appear before any
    engine interaction on relaunch), and stepping through plies showed the
    eval bar updating per-position rather than carrying over a stale value.
- **M3 complete (2026-07-17): Exploration Mode.** Followed
  `handoffs/NEXT-SESSION-M3.md`'s bootstrap; every accept-criterion step
  verified E2E through the built app. What's new:
  - `ChessCore`: `allIndices`, `isMainline(_:)`, `parent(of:)`,
    `mainlineAncestor(of:)` - tree navigation built on chesskit-swift's
    public API only, since `MoveTree` exposes no children/delete API.
    `playMove(from:to:at:)` auto-promotes (default queen); `PromotionKind`
    and `isPromotion(from:to:at:)` added for a future picker.
  - `Persistence`: `VariationRecord` (parent-pointer forest: root rows
    reference a mainline `parentPlyIndex`, other rows reference the
    preceding row via `parentVariationId`) + `GameStore.insertVariationMove
    /variations/deleteVariation` - delete cascades to the whole subtree
    via the schema's existing FK, tested with a 3-deep chain.
  - `App`: `GameReplayViewModel` rebuilds the variation tree in memory on
    load (replaying persisted rows onto `chessGame`) and persists each new
    move immediately as it's played (same crash-safety pattern as M2's
    analysis). `BoardView` squares are real tappable `Button`s (click to
    select, click a highlighted legal destination to play) - this also
    fixed a real accessibility gap, see devlog. `MoveListView` renders the
    variation tree (nested branches, delete-subtree, "back to game").
    `LinesPanelView` lines are clickable and adopt as a new variation.
  - Real E2E (same `osascript`/System Events method as M2, with one
    correction: raw pixel clicks are blocked in this sandbox, only
    AX-element-reference clicks work): played a 5-move variation plus a
    nested sub-variation via real board clicks, confirmed the DB rows and
    parent-pointer shape at each step, watched the live eval update for
    the explored position, deleted the sub-variation via its UI trash
    button, quit/relaunched, and confirmed the remaining 5-move variation
    reloaded correctly into both the DB and the live move list.
  - Known gaps (see devlog for detail): promote/collapse controls not
    built (only delete); no promotion picker UI; replaying a move that
    happens to equal the real mainline continuation still creates a
    redundant variation branch instead of being recognized; the
    lines-panel adopt buttons' accessibility exposure is unconfirmed.
- Project layout: `project.yml` (XcodeGen spec, regenerate with
  `xcodegen generate` after adding/removing files - `Chessanto.xcodeproj` is
  gitignored, not committed), `App/` (SwiftUI app target, with an
  `Analysis/` subfolder for M2's engine/eval-bar/graph/lines-panel code),
  `Packages/` (ChessCore, EngineKit, AnalysisKit, CoachKit, ChessComKit,
  Persistence - each a local SPM package per `PLAN.md`'s architecture).
- Git repo initialized and pushed: https://github.com/WillisLiao/chessanto
  (branch `main`). Commit and push M2 work alongside these docs.
- Next step: execute M4 (chess.com fetch). `handoffs/NEXT-SESSION-M4.md`
  has the bootstrap for that.

## Real dependencies resolved during M1 (verified against actual source, not guessed)

- [`chesskit-app/chesskit-swift`](https://github.com/chesskit-app/chesskit-swift)
  0.17.0 (MIT) - chess rules/PGN/FEN, wrapped by `ChessCore`.
- [`chesskit-app/chesskit-engine`](https://github.com/chesskit-app/chesskit-engine)
  0.7.0 (MIT wrapper; vendors Stockfish 17, GPLv3) - wraps Stockfish
  **in-process** via async/await, no subprocess/pipes. Wrapped by
  `EngineKit`'s `AnalysisEngine` actor, which already implements the
  position-generation-counter pattern from PLAN.md's risk section.
  **NNUE networks are required, not optional** (corrected 2026-07-17: the
  earlier "embedded default network" note was wrong for this build) -
  chesskit-engine compiles Stockfish with `NNUE_EMBEDDING_OFF`, and
  Stockfish 17 `exit()`s the whole host process if a search starts with no
  net loaded. `scripts/fetch-nnue.sh` fetches + hash-verifies both nets;
  chesskit-engine auto-loads them from `Bundle.main`.
  `chesskit-engine` 0.7.0's own Stockfish tests are commented out upstream
  (they need a free main run loop plus the nets, neither of which XCTest
  in CI gives them), so EngineKit's tests stay structural; the live-engine
  check in this repo is the `engine-smoke` executable, which works and is
  the thing to run after touching EngineKit.
- GRDB 7.11.1 for persistence.
- Stockfish being GPLv3 means public distribution of Chessanto needs a
  licensing decision (GPL compliance or isolating Stockfish as a separate
  component) - not an issue for local personal use, revisit before any
  release. See `PLAN.md`'s Architecture/Risks sections.

## Key decisions

- Native SwiftUI macOS app (macOS 14+), Apple Silicon primary.
- Verified Coach: rule-based facts + local LLM (Ollama), with a programmatic CoachVerifier gate on all output and an engine-tool loop; nothing unverified renders.
- Exploration Mode: chess.com-style analysis board - live eval bar while scrubbing, free variation play with variation tree, continuous engine analysis of the displayed position.
- chess.com public API fetch + offline PGN import; analysis fully local.
- RAM-based model picker; Intel Macs default to rule-based mode with a slow-inference warning.
- Position chat included in v1 (M6).
- Board pieces are placeholder Unicode glyphs sized via GeometryReader (not
  a fixed huge-font-plus-minimumScaleFactor hack - that produced degenerate
  accessibility geometry and was fixed during M1). Real piece artwork is
  M7 polish, per PLAN.md.

## Future directions (explicitly out of v1)

Mistake-derived puzzles, spaced repetition, repertoire training, play-vs-engine, Lichess import, iCloud sync, Chess960.
