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
- **M4 complete (2026-07-17): chess.com fetch.** Followed
  `handoffs/NEXT-SESSION-M4.md`'s bootstrap. What's new:
  - `ChessComKit` got real coverage: a fixture-based decode test (a
    trimmed real archive response) plus `chesscom-smoke`, a live
    executable (mirroring `EngineKit`'s `engine-smoke`) that round-trips
    `profile`/`archiveURLs`/`recentGames` against the real chess.com API.
  - `Persistence`: `UserProfileRecord` + `GameStore.userProfile()`/
    `saveUserProfile()` - the settings-storage question from the M4
    bootstrap resolved in favor of the existing `userProfile` table over
    `UserDefaults`, since M6 will need `ratingBand`/`coachModel`/
    `coachEnabled` there anyway.
  - `App`: `ChessComFetchView` - a sheet with username entry, fetch,
    a checkbox-selectable game list (already-imported games marked and
    disabled), and multi-select import via the existing
    `GameLibrary.importPGN(_:source:sourceURL:)` path. Wired to a new
    "Fetch from chess.com" toolbar button next to "Import PGN". Also
    fixed a real bug in `GameLibrary.alreadyImported(sourceURLs:)`,
    which ignored its parameter and returned every imported URL instead
    of intersecting with the games actually being shown.
  - Real E2E verification (same `osascript`/System Events method as
    M2/M3): fetched a real, very active chess.com account
    (`hikaru`, 991 games in the default 2-month window - which is also
    why the fetch view now defaults to *no* games pre-selected rather
    than "select all"), imported 5 games, confirmed via `sqlite3` they
    landed with the right `source`/`sourceURL`, quit/relaunched and
    confirmed both the username and all 6 games (1 original + 5 new)
    persisted, ran a full Analyze pass on one of the imported games (238
    analysis rows, accuracy `White 94.5 / Black 91.2` rendered
    correctly), and confirmed an invalid username surfaces the existing
    chess.com error alert cleanly rather than crashing.
  - Two real bugs found and logged (see the 2026-07-17 devlog's M4
    section for full detail, not fixed this session): one of the 5
    imported games fails to parse (`chesskit-swift`
    `invalidMove("Rb5")` on an otherwise ordinary game - a pre-existing
    parser edge case, not a chess.com-specific or M4 regression, and it
    already degrades correctly via the existing load-error alert); and
    the Analyze button has no "engine still starting" state, so clicking
    it before `EngineService.isStarted` flips true silently does
    nothing instead of showing a real error.
- Project layout: `project.yml` (XcodeGen spec, regenerate with
  `xcodegen generate` after adding/removing files - `Chessanto.xcodeproj` is
  gitignored, not committed), `App/` (SwiftUI app target, with an
  `Analysis/` subfolder for M2's engine/eval-bar/graph/lines-panel code),
  `Packages/` (ChessCore, EngineKit, AnalysisKit, CoachKit, ChessComKit,
  Persistence - each a local SPM package per `PLAN.md`'s architecture).
- Git repo initialized and pushed: https://github.com/WillisLiao/chessanto
  (branch `main`). Commit and push M2 work alongside these docs.
- **M5 complete (2026-07-17): rule-based coaching report.** Followed
  `handoffs/NEXT-SESSION-M5.md` step by step; every step's verification
  passed. What's new:
  - `ChessCore`: `ReplayedMove`, `ChessGame.replayLine(fromUCI:startingFEN:)`
    (generalizes `sanLine`, also returns check/mate flags, captures, and
    resulting FEN), `moveDetail(at:)`, `material(fen:)`, `epd(fromFEN:)`.
  - `AnalysisKit` (DB-free, ChessCore-only): a real lichess CC0 opening
    book (`OpeningBook`, 3,803 entries via `scripts/fetch-eco.sh`, indexed
    by replaying every line and keying on final-position EPD; ships a
    **precomputed** `eco-index.json` since replaying the raw dataset at
    launch measured ~7.5s, well past budget). The Facts/detector/report
    pipeline: `ReportInput`/`PlyRecord`/`RankedLine`,
    `EvalSwingFact`/`BetterMoveFact`/`PunishmentFact`/`MissedMateFact`/
    `AllowedMateFact`/`OpeningFact`, `ThemeDetector` (replay-based, never
    string-matching), `KeyMomentSelector`, `ReportBuilder`, `ReportText`
    (closed templates only), `FactAuditor` (independently re-derives and
    drops any fact that fails to match - the seed of M6's
    `CoachVerifier`). `EvalLabel` extracts eval-string formatting
    previously duplicated in `GameReplayViewModel`.
  - `App`: fixed the M4-logged "Analyze silently no-ops before the engine
    finishes starting" bug (a real "Starting engine..." toolbar state).
    `GameReplayViewModel` retains full per-ply ranked rows and builds a
    `GameReport` once analyzed; the right pane is now a "Moves"/"Report"
    segmented tab; `GameReportView` renders it with real, board-jumping
    `Button`s for each key moment.
  - Two real bugs found by the E2E pass and fixed (see the 2026-07-17
    devlog's M5 section for full detail): `ContentView`'s detail pane
    wasn't recreated when switching between two already-selected games
    (missing `.id(game.id)` - the `if let` branch never changes identity),
    so the whole replay pane (including the new Report tab) silently kept
    showing the *previous* game; and the Takeaways section falsely
    claimed "a clean game" whenever no *aggregate* pattern fired, even on
    games with real, individually-flagged blunders.
  - Real E2E verification (Release build, `osascript`/System Events):
    every claim in all 3 key moments of the real 55-ply fixture game was
    manually cross-checked against the actual `sqlite3` analysis rows and
    hand-computed win-probability math - zero false statements found. A
    committed golden test (`real-fixture-game-report-input.json` +
    `real-fixture-game-golden-report.txt`, both real chess.com/Stockfish
    data) locks this in.
  - Known gaps for a future session (not blocking): the Report tab's
    key-moment `Button`s are fully clickable via AX-element reference
    (role `AXButton`, click-to-jump confirmed working) but their text
    isn't exposed through any AX attribute this session could find,
    unlike `MoveListView`'s structurally similar buttons - possibly
    related to `MoveListView` living inside a `List`/`AXOutline` and the
    report's key moments being a bare `ScrollView`/`VStack`, but
    unconfirmed. The new "Starting engine..." toolbar state is
    structurally correct but wasn't caught live in automation (the
    Release-build engine now starts faster than System Events can query
    the window after launch).
- **M6 prep complete (2026-07-17): live Ollama verification and execution
  plan.** A planning session (no app code changes) verified everything M6
  will code against and rewrote `handoffs/NEXT-SESSION-M6.md` as a
  self-contained execution plan (verified facts with real curl
  transcripts, fixed design decisions, 9 build steps each with a
  verification gate). Highlights, full detail in the devlog's "M6 prep"
  section and the plan itself:
  - Live-verified Ollama 0.31.2's real API end to end: tags/ps/show
    (including the `capabilities` array the picker needs for tool
    support), chat streaming NDJSON, thinking-model handling (`qwen3`
    emits a separate `message.thinking` field; `think:false` disables),
    tool calling (arguments arrive as a JSON object; streamed tool calls
    arrive whole in one chunk; round-trip via `role:"tool"` messages
    verified), pull-with-progress (a real mid-stream `{"error":"503: "}`
    inside an HTTP 200 stream was observed live, and retry resumes), and
    the 4096-default-context trap (`options.num_ctx` is mandatory).
  - All PLAN.md model tags resolve in the registry with real sizes - but
    **gemma3 has no tools capability**, so the 32GB alternative becomes
    `qwen2.5:32b` (19.9 GB, tools). `qwen3:0.6b` (~0.5 GB, tools +
    thinking) was pulled and stays installed as the dev/harness model.
  - Scratch-run against ChessCore proved SAN replay from arbitrary
    mid-game FENs works and exposed a real trap: `playMove(san:)` trusts
    `+`/`#` suffixes instead of deriving check state (bare `Qh5` on a
    mate reports `isCheckmate=false`; spurious `e4+` is echoed back).
    CoachVerifier's fixed pattern: SAN path for legality + UCI extraction
    only, then re-replay via `replayLine(fromUCI:)` for every board fact.
  - No schema work needed: `userProfile` has had `ratingBand`/
    `coachModel`/`coachEnabled` since the v1 migration, and
    `UserProfileRecord` already maps them. `project.yml` already carries
    `NSAllowsLocalNetworking` + the network-client entitlement, and the
    App target already links CoachKit.
- **M6 complete (2026-07-17): local LLM coach.** Followed
  `handoffs/NEXT-SESSION-M6.md` step by step; every step's verification
  gate passed. Full detail in the devlog's "M6 execution" section. What's
  new:
  - `CoachKit` is no longer a placeholder. `OllamaModels`/`OllamaClient`
    (native `/api/*` only, explicit `CodingKeys` throughout, a plain
    `Sendable` class rather than an actor), `CoachVerifier` (Layer 2's
    hard gate: regex token extraction, SAN-legality-then-UCI-re-replay
    per fact 15, PV-prefix or landed-on-known-anchor line verification,
    exact check/mate suffix matching, tolerance-based eval/mate/percentage
    checks, an at-most-once-per-response fresh-verification hook via
    `EngineToolExecutor`), `CoachPayloadBuilder`/`CoachPrompt` (Layer 1),
    `EngineToolExecutor`/`EngineToolResult` (Layer 3's protocol),
    `CoachNarrator` (the orchestrator: generate -> verify -> regenerate
    once -> fallback), `CoachModelCatalog` (the picker table). 40 tests,
    including a gate that runs the real M5 golden rule-based report text
    through `CoachVerifier` expecting zero violations.
  - `AnalysisKit`/`ChessCore`: `Codable` added to the Fact structs,
    `KeyMoment`, `ClassificationCount`, `MoveClassification`, `PieceKind`,
    `PieceColor` (additive); `ReportText.momentSummary(_:report:)`
    (public, reuses the existing private renderer) and
    `ChessGame.isValidFEN(_:)` added.
  - `App`: `EngineService.coachEvaluate` (the `EngineToolExecutor` impl,
    replay-validates args before touching the engine, refuses during
    batch analysis, stop/resume around live analysis like `analyze()`);
    `CoachService` (`@MainActor`, health checks, sequential per-game
    narration generation), `CoachSettingsView` (a real `Settings` scene:
    enable toggle, teaching level, Intel warning, Ollama guidance +
    recovery, installed-model picker with tool-capability badges,
    free-text pull with progress), `MachineProfile` (sysctl detection).
    `GameReplayViewModel` keeps `reportInput` alongside `report`;
    `GameReportView` triggers narration via `.task(id: viewModel.report)`
    and renders a labeled ("Coach" vs "Rule-based") text slot per key
    moment plus a summary section - the rule-based path is byte-identical
    when the coach is off.
  - `coach-grounding` (new CoachKit executable, `engine-smoke` precedent):
    a standalone `GroundingEngine` actor drives a real in-process
    Stockfish directly (duplicates `EngineScoreNormalizer`'s ~10 lines
    since it can't import the App target); runs the full narrate->verify
    loop against real Ollama + the real fixture, independently
    re-verifying every rendered "coach" text with a fresh context (not
    the in-generation tool-call anchors); also carries step 4's live
    "one legal + one illegal `evaluate()` call" gate. `swift run
    coach-grounding` exits 0; multiple live runs show the verifier
    genuinely firing (violations/fallbacks with `qwen3:0.6b`, zero leaks
    every time).
  - Real E2E verification (Release build, `osascript`/System Events, on
    the real `MagnusCarlsen vs artin10862` fixture game): real narration
    rendered for all 3 key moments + summary, every cited move/eval
    grounded (including one moment's `Ka2` getting grounded through the
    verifier's live fresh-verification tool call - Layer 3 confirmed
    working end to end in production); prose *reasoning* quality is
    often weak with this harness model, which is the documented,
    expected tradeoff - the architectural guarantee (no invented
    moves/evals) held in every rendered sentence, general commentary
    accuracy was never part of that guarantee. Killed Ollama outright:
    all moments/summary fell back to the exact M5 rule-based text,
    correctly labeled, no crash/hang. Restarted Ollama: Settings'
    "Check again" recovered live. Settings guidance states (no-Ollama,
    non-tools-model note via the locally-installed `llava:7b`, model
    recommendation matching this machine's real 16 GB) all verified via
    AX. `coach-grounding` + every package's `swift test` + the full
    `xcodebuild test` app suite all green.
  - Known limitations carried forward (not blocking, documented
    deliberate simplifications - see the plan's CoachVerifier design and
    the devlog): eval/mate/percentage claims are checked against a pool
    of known-good values rather than strictly tied to the specific cited
    line they follow, so a real number can occasionally be misattributed
    (never fabricated); the bare-square exemption occasionally exempts a
    genuine single-word move reference (e.g. a played move stated with no
    leading number marker) from verification rather than checking it;
    general prose/qualitative-claim accuracy (as opposed to moves/lines/
    evals) is explicitly out of scope for M6 v1 per PLAN.md's residual-risk
    note.
- **M7 prep complete (2026-07-17): chat mechanics verified live, execution
  plan written.** A prep-only session (no app code changes) read every
  source file M7 builds on in full, verified the new conversational
  mechanics against the live Ollama 0.31.2 server, scratch-ran the
  proposed-move precheck against real ChessCore, and rewrote
  `handoffs/NEXT-SESSION-M7.md` from a rough bootstrap into a
  self-contained execution plan (9 verified facts, fixed design decisions,
  10 build steps each with a verification gate). Highlights, full detail
  in the devlog's "M7 prep" section and the plan itself:
  - Live-verified: multi-turn chat history round-trips; tool calls fire
    with history present (and the model mangled its FEN argument again
    live - the replay-validation guard is load-bearing for chat too);
    concurrent requests are safe on Ollama's side, so the real hazard is
    `EngineService.searchOneShot`'s singleton collector state - the plan
    serializes `coachEvaluate` with a FIFO chain.
  - Scratch-run against real ChessCore found three precheck traps before
    any code: bare-square tokens ("take on d5", "knight on c6") must
    never be treated as move proposals, and number-marker chains
    ("24...Qd7") are game-history references that must skip the precheck.
  - The bootstrap's four open design questions are now fixed decisions:
    a `CoachChat` actor sharing `CoachNarrator`'s (made-internal) turn
    engine; a chat payload with context-block-on-FEN-change injection and
    a seed evaluation; in-code proposed-move validation before the LLM
    with a canned illegal-move short circuit; buffer-then-render replies
    (a documented deviation from PLAN.md's "Streaming responses" bullet,
    resolved by its own "nothing unverified renders" rule).
  - One schema change is planned (the first post-v1 migration): a
    nullable `chatMessage.source` column so the Coach/fallback honesty
    label survives relaunch.
- Next step: **M7 - position chat**, executing
  `handoffs/NEXT-SESSION-M7.md` step by step (the design decisions there
  are fixed; do not re-derive them).

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
