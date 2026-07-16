# Chessanto - Handoff

Living snapshot of project state.
Read this first at session start; update it at session end.

## Current state (2026-07-17)

- **M1 complete.** App builds, all tests pass, and the acceptance criteria in
  `PLAN.md` are met: a real chess.com PGN (fetched live from the public API,
  with `[%clk]` comments and both castling sides) imports through the actual
  UI, persists across quit/relaunch, and steps forward through the game move
  by move with the board and move list updating correctly.
- **M2 prep done (2026-07-17): live Stockfish verified in this repo.**
  `swift run --package-path Packages/EngineKit engine-smoke` runs a real
  in-process Stockfish 17 search and asserts real evals, the side-to-move
  sign convention, and mate detection (startpos depth 15 gave +38cp with
  pv e2e4...). The NNUE networks are mandatory (see below), fetched by
  `scripts/fetch-nnue.sh` into `App/Resources/` (gitignored) and verified
  to land in the built app bundle. `project.yml`'s resources block was
  silently dead (XcodeGen has no `resources:` target key) and is fixed.
  `AnalysisEngine` gained `EngineInfo.multiPVRank` and `setOption`.
- Project layout: `project.yml` (XcodeGen spec, regenerate with
  `xcodegen generate` after adding/removing files - `Chessanto.xcodeproj` is
  gitignored, not committed), `App/` (SwiftUI app target), `Packages/`
  (ChessCore, EngineKit, AnalysisKit, CoachKit, ChessComKit, Persistence -
  each a local SPM package per `PLAN.md`'s architecture).
- Git repo initialized and pushed: https://github.com/WillisLiao/chessanto
  (branch `main`, one commit so far). Commit and push again once M2 work
  is ready, following the same convention (working code + updated
  handoffs/devlog together).
- Next step: execute M2 (engine integration - Stockfish analysis, eval bar,
  move classification, live infinite analysis while scrubbing).
  `handoffs/NEXT-SESSION-M2.md` is a full, self-contained execution plan
  with verified engine facts, fixed conventions/formulas, and an ordered
  step list - follow it rather than re-deriving decisions.

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
