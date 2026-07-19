# Chessanto - Handoff

Living snapshot of project state.
Read this first at session start; update it at session end.

## Current state (2026-07-19)

- **User-selectable move notation complete (2026-07-19).**
  - General Settings now lets the user choose standard SAN such as `Nf3` or full piece names such as `Knight f3`.
  - The choice is persisted by the append-only `v8_moveNotationStyle` migration and is applied consistently to the move ledger, Report, Practice, engine lines, line playback, the comic Coach, and Coach responses.
  - Full-name mode uses a one-move-per-row ledger so expanded moves remain readable, while standard mode keeps the compact two-column scoresheet.
  - This is a presentation-only boundary.
    Canonical SAN in PGNs, analysis, variations, engine input, Coach grounding, and user-authored chat is never rewritten.
  - VoiceOver receives semantic move names in both visual modes.
  - The complete app suite passes with 98 tests across 23 suites, the persistence migration and round-trip tests pass, the universal Release build passes, and native QA covered both notation modes plus automatic better-line playback.
  - Native QA used the isolated database at `~/Library/Containers/com.chessanto.app/Data/tmp/notation-choice-final-20260719-1752/chessanto.sqlite`.
    The live database was restored from its preserved backup, passed `PRAGMA integrity_check`, and matches that backup at SHA-256 `5112ee500dd1c249bad5ccca9ea61e2681176141572c9051dd765457c0bc976e`.

- **UI/UX clarity phase 2 complete (2026-07-19): synchronized Coach stage and playable analysis.**
  - `LinePreviewController` is a small, DB-free replay module built on `ChessGame.replayLine`.
    It cannot access `GameStore`, the variation tree, or `adoptLine`.
  - Report key moments now start the full stored rank-1 line automatically on the board.
    Report also offers a separate read-only playback of the moves that actually followed in the game.
  - Practice feedback and Reveal start the full stored better line automatically.
    Nothing is previewed before the learner has answered or revealed the card.
  - Both surfaces retain manual pause, replay, previous, next, jump-to-start, jump-to-end, and Done controls.
  - The narrow Review and Practice panes no longer print long Coach paragraphs.
    A purpose-built comic Coach portrait and speech bubble sit with the board and update with each demonstrated SAN move.
  - The bubble uses verified local Coach narration when available and otherwise labels deterministic report text as `Engine verified`.
  - The original phase 2 plan's manual-only and sentence-fragment presentation decisions were superseded by the user's explicit autoplay and comic-stage direction.
  - App coverage increased from 75 tests across 19 suites to 91 tests across 22 suites.
  - Native Release QA exercised better-line autoplay in Review and Practice plus the real played continuation.
    The QA database had one variation row before and after, and the protected live database was restored byte-for-byte from its preserved backup after QA.

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
- **M7 complete (2026-07-18): position chat.** Followed
  `handoffs/NEXT-SESSION-M7.md` step by step; every step's verification
  gate passed, including two real bugs found live and fixed before
  moving on. Full detail in the devlog's "M7" section. What's new:
  - `Persistence`: a `v2_chatMessageSource` migration (the first
    post-v1 migration) plus `ChatMessageRecord` and
    `GameStore.insertChatMessage`/`chatMessages`/`deleteChatMessages`.
  - `CoachKit`: `CoachVerifier.moveTokenChains(in:)` (public tokenizer
    exposure, `verify()` itself unchanged) and `ProposedLineCheck`
    (the precheck classifier: bare-square/history-reference/legal-
    proposal/illegal-proposal, built around the prep session's TRAP 1/
    TRAP 2 findings); `CoachChatContext`/`CoachChatPayload`/
    `CoachPayloadBuilder.chatPayload`/`CoachPrompt.chatSystemPrompt` etc;
    `CoachChat` (a `public actor`, the multi-turn analogue of
    `CoachNarrator` - precheck -> seed eval -> generate -> verify ->
    regenerate once -> fallback, history pruned to bare turns and capped
    at 12 messages, `CoachNarrator.runConversation` shared via a
    `private` -> `internal` refactor with all 7 of its own tests
    unmodified). 40 new CoachKit tests.
  - `App`: `EngineService.coachEvaluate` gets a FIFO chokepoint
    (`coachEvaluateTail`) so a narration tool call and a chat tool call
    can't clobber `searchOneShot`'s shared state - **the first attempt
    at this was wrong** (a placeholder-task chain that only waited for
    the previous placeholder, not the previous call's actual engine
    work, serializing nothing) and wasn't caught by any offline test;
    only the live concurrent-evaluate probe in `coach-grounding`
    deadlocked and surfaced it. `GameReplayViewModel.chatContext()`/
    `chatPositionLabel`; `CoachService` chat state
    (`chatMessages`/`isSendingChatMessage`/per-game cached `CoachChat`);
    a new `ChatView` (third `RightPaneTab` segment) - `List`-based
    message view, position chip, source captions, per-message jump
    buttons, starter chips, single-phase "Coach is thinking..."
    indicator (a documented scope-down - no real progress-reporting
    hook exists to back the plan's 3-phase design honestly), offline
    guidance state.
  - `coach-grounding` grew a chat section (legal/illegal/open-question
    turns plus the concurrent-evaluate probe) - this is what caught the
    FIFO bug above, and also caught a harness-side bug (independent
    re-verification was re-checking `.precheck` canned-template replies
    as if they were LLM prose, false-flagging the very token the
    template declines as an unverified citation) - both fixed, second
    run exits 0.
  - Real E2E verification (Release build, `osascript`/System Events, the
    real analyzed `MagnusCarlsen vs artin10862` fixture): found and fixed
    a real bug before functional testing could even start (Chat tab
    never triggered a health check, stuck on "Checking..." forever);
    then confirmed live - illegal-move precheck (instant, zero LLM
    calls), legal-move proposal (verified eval injected and cited,
    `source=coach`), variation-position chat (correct branch-ply
    `plyIndex` mapping), quit/relaunch persistence (14 messages
    round-tripped, jump buttons work), Clear chat, and the
    coach-disabled offline state. `coach-grounding` exits 0; all 160
    package tests plus the 10 app tests green throughout.
  - Known gaps for a future session (not blocking, all quality/UX/
    robustness, not safety - nothing unverified ever rendered in any
    live test): open-question tool-calling didn't clearly fire live with
    either `qwen3:0.6b` or a `qwen2.5-coder:7b` spot-check (no
    `qwen3:8b` on this machine); prose quality with non-frontier models
    is weak/repetitive (same documented M6 residual risk, not new);
    `List` produces a real `AXOutline`/`AXRow` structure (a genuine, if
    partial, improvement over `MoveListView`'s bare `ScrollView`) but
    row text/button labels still don't expose via `name` in this AX
    bridge, so the M5 AX gap isn't fully resolved; `OllamaClient` has no
    request timeout, so a genuinely-*unresponsive*-but-not-torn-down
    Ollama (simulated via `SIGSTOP`, as opposed to `kill -9` which this
    machine's Ollama.app auto-respawns too fast to observe) hangs chat
    indefinitely rather than falling back in a reasonable time - a
    pre-existing characteristic shared by M6's narration path, only now
    exercised by this specific failure mode.
- **M8 prep complete (2026-07-18): polish/packaging surface verified live,
  execution plan written.** A prep-only session (no app code changes) read
  every file M8 touches in full, overturned two carried-forward claims by
  measuring (OllamaClient's 300s timeout exists and fires at 301.0s
  against a frozen Ollama - the real fix is shorter differentiated
  timeouts; and the M5/M7 "List AX text gap" was the AppleScript bridge,
  not the app - full text is present in `AXDescription` via the raw AX
  API, so `scripts/axprobe.swift` becomes the E2E read method), settled
  the Stockfish licensing question with the user (**the app will be
  licensed GPLv3**; LICENSE/README/release script land in M8), fixed the
  board scope (cburnett GPLv2+ SVGs, verified live, plus three square
  themes and three dormant M1 board features: coordinates, flip,
  last-move highlight), measured the dashboard cheap enough to compute
  live (3.55 ms/game release-mode ReportBuilder run - no rollup table),
  and pinned mixed-ELO acceptance data across every rating band per the
  user's request (the user is chess.com `WillisLiao`, blitz ~231; plus
  verified accounts at ~750, ~1200, 1819-2241, 2533, and the existing GM
  fixtures). One v3 `userProfile` migration
  (`hasCompletedOnboarding`/`analysisQuality`/`boardTheme`) is the only
  schema work. Full detail in the devlog's "M8 prep" section and the
  rewritten `handoffs/NEXT-SESSION-M8.md`.
- **M8 complete (2026-07-18): polish and packaging - v1 complete per
  PLAN.md.** Followed `handoffs/NEXT-SESSION-M8.md` step by step; every
  step's verification gate passed, full detail in the devlog's "M8
  execution" section. What's new:
  - `Persistence`: a `v3_m8Settings` migration
    (`hasCompletedOnboarding`/`analysisQuality`/`boardTheme` on
    `userProfile`), `UserProfileRecord` extended, a real partial-then-full
    migration test plus a live check against a copy of the real dev DB.
  - `CoachKit`: `OllamaClient` no longer clobbers an injected session
    config's timeout; per-request timeouts (5s probes/120s chat/300s
    pull) replace one 300s-for-everything default; `.timedOut` mapping.
    Live-verified against a real frozen (`kill -STOP`) Ollama: `version()`
    failed at 5.0s, a chat turn at 121.0s, clean recovery on
    `kill -CONT`, `coach-grounding` still green after.
  - `App`: real cburnett piece artwork (`App/Resources/Pieces.xcassets`,
    fetched by `scripts/fetch-pieces.sh`, GPLv2+) replaces the Unicode
    glyph placeholders; `BoardTheme` (classic/green/blue); the three M1
    board debts closed (file/rank coordinates, a flip-board toolbar
    button, `lastMove` highlighting). Settings became a tabbed scene
    (General + Coach); a new `CoachSetupView` is shared between
    `CoachSettingsView` and a new 4-page `OnboardingView` (welcome ->
    chess.com username -> rating band -> coach), gated on
    `hasCompletedOnboarding`. A new `DashboardView` ("Progress" toolbar
    button) shows an accuracy trend chart and mistake-theme aggregation
    across analyzed, user-matched games, computed live off the main actor
    via a new shared `ReportBuilding` helper (also now used by
    `GameReplayViewModel`, replacing duplicated inline mapping code). The
    `-0.0` eval-label bug is fixed (`EvalLabel.format`); `ChessantoApp`
    no longer replaces the default "New Window" menu item, restoring an
    in-app recovery path from the zero-window state.
  - Packaging: `LICENSE` (GPLv3), `README.md` (what the app is, build
    steps, dependency/license table, signing/notarization steps
    documented but never auto-run), `scripts/release-build.sh`
    (produces an unsigned Release build; verified from a fully wiped
    `DerivedData`).
  - New E2E tooling, committed: `scripts/axprobe.swift` (reads via raw
    `AXUIElementCopyAttributeValue`, the fix for the M5/M7 "AX gap" which
    turned out to be the AppleScript bridge's limitation, not the app's),
    `scripts/axclick.swift` (presses via `AXUIElementPerformAction`),
    `scripts/axclickat.swift` (real `CGEvent` clicks at screen
    coordinates - the only thing that reliably hands a SwiftUI text field
    real keyboard focus), `scripts/axfocus.swift`/`scripts/axsettext.swift`
    (built this session but found NOT to reliably drive real SwiftUI
    `@State` bindings when writing text directly via the AX API - kept,
    but documented as unreliable for that specific purpose in the
    devlog). Reads and button/menu presses work without the app being
    frontmost; sheets don't even render while backgrounded, and real
    text entry needs the app frontmost plus a real `CGEvent` click.
  - Real E2E verification (Release build): the full fresh-user flow
    against the live chess.com API and a live Ollama - onboarded as the
    user's real account `WillisLiao`, fetched and imported a real recent
    game, analyzed it, read the real coached report, drove Chat for real
    (a real coach-narrated answer and a real illegal-move precheck
    reject) on this real beginner-band game (not just the GM fixture),
    and cross-checked the dashboard's numbers directly against
    `sqlite3`. All package tests (177), `xcodebuild test` (11 app
    tests), and `coach-grounding` (10/10 zero-leak runs) green.
  - Known gap: M3's promote/collapse variation controls and the
    promotion-picker UI are still absent (out of M8's PLAN.md scope, not
    a regression). Prose quality with small local models remains the
    documented M6/M7 residual risk, not something M8 could or should fix.
- **v1 is feature-complete per PLAN.md.**
- **UI/UX audit + redesign plan complete (2026-07-18, planning only, no code).**
  The audit followed `handoffs/NEXT-SESSION-UIUX.md`, built and ran the app, screenshotted every screen and state live, and produced the signed-off `handoffs/NEXT-SESSION-UIUX-EXECUTE.md` plan with verified facts, fixed decisions, and 12 staged gates.
  The audit reproduced 12 real problems, including toolbar overflow hiding Import PGN at 1400px, a single-column move list with a badge on every move, classification labels wrapping mid-word in the narrow Report pane, literal Coach markdown syntax, Chat replacing Moves with no position pin, a stark eval bar and graph, a broken-looking one-point dashboard chart, and sidebar rows with truncated names and raw-seconds time controls.
  The board artwork, themes, coordinates, last-move treatment, and flip behavior were explicitly protected.
  The recorded user decisions were a light and white-forward appearance, a brass accent, no green, near-monochrome warm chrome, and a Coach slide-over or wide dock that never hides the board or move context.
  The user later superseded the planned dark support by explicitly requiring a forced-light palette during execution.
  The implementation target was visual and information-architecture improvement without a new schema or unrelated feature expansion.
- **UI/UX redesign execution complete (2026-07-18).**
  The paused Sonnet task was reconstructed from its local session log and continued from Step 11 through acceptance.
  A shared design system now governs warm-neutral surfaces, graphite text, brass accents, spacing, typography, cards, chips, and primary controls.
  The user explicitly corrected the earlier plan and required the app to force the light palette even when macOS is dark, so `ChessantoApp` intentionally pins Aqua and `.light`.
  The sidebar now has room for real names and metadata, a stable Progress/Add bottom bar, and richer game rows.
  Empty selection and onboarding use a code-native Chessanto emblem and clearer value messaging.
  A generated macOS app icon carries the same ivory, graphite, brass, tilted-board, and improvement-line identity into Finder and the Dock.
  The replay workspace now has a quieter eval bar and graph, two-column notation, compact classification marks, polished controls, card-based reports, and a clear text-labeled Coach entry point.
  Coach is no longer a third tab.
  It docks as a third column when wide and slides over the right pane when narrow, while leaving the board visible.
  Coach can follow the board or pin to an exact position, and move/report entry points open it already pinned.
  Markdown now renders as formatting rather than literal asterisks.
  A regression test found and fixed an existing chat-context bug where move paths omitted White's first move and could subscript an empty history at the start position.
  The live grounding gate also exposed a mismatch between production chat verification and the independent harness.
  Fresh re-verification now recreates legal-proposal anchors, and trusted PV prefixes carry their resulting position forward.
  Full package tests, the app tests, a universal Release build, and `coach-grounding` all pass.
  The final product audit and next implementation plan are in `handoffs/NEXT-SESSION-LEARNING-LOOP.md`.
  Large UI audit screenshots remain local and are intentionally ignored because the capture set exceeds 160MB.
  M3's promote/collapse variation controls remain intentionally deferred because the wrapped move tree exposes no public child reordering, promotion, or deletion mutation API, while the current parent-pointer persistence model has no branch-order semantics.
  Implementing promotion correctly therefore requires a small domain and persistence design rather than a cosmetic control, and pairing collapse with that work avoids creating a partial editor that suggests unsupported branch management.
  Engine arrows are an intentional visual-aid extension within the user's request to improve graphics and helpfulness.
  Report prose continues to use `you`, `White`, and `Black` rather than exposing opponent usernames, which preserves an earlier user decision and keeps fixture reports legible.
  The grounding-harness change is a release-safety correction that makes independent verification faithfully recreate production's legal-proposal anchors.

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
- Stockfish being GPLv3: **resolved 2026-07-18 (M8 prep, user decision) -
  Chessanto itself is licensed GPLv3** (`LICENSE`, shipped M8), making
  distribution compliant; the README's dependency/license table and
  `scripts/release-build.sh` also shipped in M8. See `PLAN.md`'s
  Architecture/Risks sections for the original analysis.

## Key decisions

- Native SwiftUI macOS app (macOS 14+), Apple Silicon primary.
- Verified Coach: rule-based facts + local LLM (Ollama), with a programmatic CoachVerifier gate on all output and an engine-tool loop; nothing unverified renders.
- Exploration Mode: chess.com-style analysis board - live eval bar while scrubbing, free variation play with variation tree, continuous engine analysis of the displayed position.
- chess.com public API fetch + offline PGN import; analysis fully local.
- RAM-based model picker; Intel Macs default to rule-based mode with a slow-inference warning.
- Position chat included in v1 (M7, complete 2026-07-18).
- Board pieces render real cburnett artwork (GPLv2+, shipped M8) sized to
  the square, replacing M1's placeholder Unicode glyphs; three square
  themes (classic/green/blue) and file/rank coordinates, flip, and
  last-move highlighting all shipped alongside them.
- The app is licensed GPLv3 (user decision, 2026-07-18): Stockfish
  compliance resolved, binaries distributable, cburnett artwork
  compatible. `LICENSE`/`README.md`/`scripts/release-build.sh` shipped M8.
- E2E/acceptance data spans all rating bands, beginner through pro (user
  request, 2026-07-18): the user's own `WillisLiao` account (~231 blitz)
  plus pinned accounts per band in `NEXT-SESSION-M8.md` fact 12, not just
  the GM fixtures - M8's acceptance pass used a real live `WillisLiao`
  game end to end (fetch, analyze, report, chat), not a GM fixture.
- A one-time onboarding flow (M8) and a live-computed player-progress
  dashboard (accuracy trend + mistake themes, M8) round out PLAN.md's v1
  scope. **v1 is now feature-complete.**

## Active Learning Loop completion (2026-07-18)

Implemented the Active Learning Loop vertical slice from `handoffs/NEXT-SESSION-LEARNING-LOOP.md`.

### Product behavior

Analyzed reports now generate persistent practice cards from audited key moments.
The Report tab has a primary `Practice key moments` action plus a small `Practice` action on each key moment.
The primary action opens the full game key-moment queue.
The row action opens that single source ply.

The Progress dashboard now surfaces a `Next lesson` card.
When due cards exist, its primary action is `Review next lesson`.
When nothing is due, it shows the next review date when available and offers a secondary `Practice any position` action against existing saved training cards.

The practice sheet reuses the real board, board theme, legal-move selection, and side-to-move orientation.
It prompts with `Find the move you wish you had played.`
It supports hint, reveal, try again, next, skip, and completion states without changing the approved warm-neutral and brass design system.

### Domain and persistence

Added a focused training domain under `App/Sources/Chessanto/Training`.
The core types are `TrainingCard`, `TrainingAttempt`, `TrainingOutcome`, `MasteryState`, `TrainingMoveEvaluator`, and `ReviewScheduling`.
`DefaultTrainingMoveEvaluator` rejects illegal moves with `ChessCore`, accepts cached ranked-line first moves, evaluates other legal attempts through the engine, compares white-perspective scores from the mover perspective, and keeps mate scores separate from centipawn scores.
The deterministic scheduler implements the current review policy: incorrect and inaccurate are due now, playable is due tomorrow, one strong recall is due in three days, two strong recalls are due in seven days, and three or more strong recalls become mastered with a fourteen-day review.

Persistence now has forward-only migration `v4_trainingLoop`.
It adds `trainingCard` and `trainingAttempt`.
Cards are unique by `gameId` plus `sourcePly`, persist the pre-move FEN and ranked-line facts needed for practice, and cascade with deleted games.
Attempts cascade with deleted cards.
`GameStore` exposes card upsert, game-card lookup, due-card lookup, any-card fallback lookup, next-due lookup, attempt save, and attempt history methods.

### Verification

Focused training app tests passed:
`xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/PracticeSessionViewModelTests -only-testing:ChessantoTests/TrainingDomainTests`.

Full app tests passed:
`xcodebuild test -scheme Chessanto -destination 'platform=macOS'`.
That run executed 23 tests in 10 suites.

Persistence package tests passed after the migration and store changes:
`swift test --package-path Packages/Persistence`.

The existing broader package and release gates also passed during this session before the final row-filter and card-count polish:
`swift test --package-path Packages/ChessCore`,
`swift test --package-path Packages/AnalysisKit`,
`swift test --package-path Packages/CoachKit`,
`swift test --package-path Packages/EngineKit`,
`swift test --package-path Packages/ChessComKit`,
`swift run --package-path Packages/EngineKit engine-smoke`,
`swift run --package-path Packages/CoachKit coach-grounding`,
and `scripts/release-build.sh`.

`git diff --check` is clean.

### Notable fix outside the practice feature

The live `coach-grounding` harness initially failed independent chat verification because its fresh audit context rebuilt anchors but did not seed the known eval and mate arrays from those anchors the way production `CoachChat` does.
`Packages/CoachKit/Sources/coach-grounding/main.swift` now seeds `knownEvalsCentipawns` and `knownMates` from the fresh anchors before the independent verification pass.
After that fix, `coach-grounding` passed with zero leaks.

### Remaining gap

This session did not capture a fresh native screenshot of the completed practice flow.
The implementation was verified by focused view-model tests, domain tests, persistence tests, full app compilation and tests, source review, and prior release gates.
The next visual QA pass should open a generated-card practice session in the Release app and capture the prompt, feedback, reveal, and completion states at normal and narrow widths.

## V1 hardening slice complete (2026-07-18)

The first execution slice from `handoffs/NEXT-SESSION-V1-HARDENING.md` is complete.
The exact implementation and native QA record is in the `V1 hardening execution` section of `devlogs/2026-07-18.md`.

Move-quality abbreviations were replaced with familiar chess-review marks.
Best uses a green star, Excellent uses a green thumbs-up, Good uses a neutral check, and the remaining classifications use familiar punctuation or symbols in their reserved semantic colors.
Every compact mark exposes the full classification through accessibility.

Training-card generation now uses the exact position immediately before the audited missed move.
When the configured username identifies White or Black, report and Dashboard generation keep only that learner's key moments.
Neutral game-scoped Report practice remains available for explicitly opened unmatched study games.

Persistence now performs transactional per-game reconciliation.
It validates candidate ownership, source-ply uniqueness, FEN, mover, legal best move, the complete persisted ranked-line shape, rank-one consistency, themes, classifications, and progress enums before writing.
It inserts new cards, updates retained cards, deletes obsolete cards, preserves scheduling when the answer is unchanged, and resets progress plus attempts when the position, mover, or answer changes.
Unchanged reconciliation is idempotent and preserves `updatedAt`.

The forward-only `v5_trainingIndexes` migration adds queue and attempt-history indexes without modifying the shipped v4 migration.
The upgrade tests preserve seeded v4 training progress, verify both indexes and the latest migration identifier, and require an empty `PRAGMA foreign_key_check`.

Report readiness is now a generation-safe state owned by `TrainingCardSynchronizer`.
Practice stays in a preparing state until reconciliation succeeds, exposes Retry after a real failure, shows a non-action state when the learner has no owned cards, and enables per-moment Practice only for reconciled source plies.
Tests cover readiness, cancellation, stale-generation rejection, failure, retry, and a real analyzed-report path that creates the exact learner-owned pre-move card without seeded SQL.

Dashboard performs a cancellable historic-game backfill before reading one consistent personalized queue snapshot.
It reports the exact due count, reloads after practice dismissal, loads fresh cards when a session opens, excludes unmatched games when a username is configured, and withholds stale actions when preparation or queue loading fails.
Dashboard failure chrome uses a dedicated error token rather than a reserved move-classification color.

Native QA used disposable copies under the sandbox container and never mutated the live database.
The live sandbox database backup path and disposable QA paths are recorded in the devlog.
The repaired Report opened a real middlegame at move 9 instead of the starting position.
The repaired Dashboard opened a developed position at move 4 and excluded the deliberately seeded unmatched move-1 card.
Valid local evidence remains at `/tmp/chessanto-v1-practice-insight-after.png`, `/tmp/chessanto-v1-classification-marks-wide-after.png`, and `/tmp/chessanto-v1-dashboard-practice-final.png`.

The final app suite passed 31 tests across 13 suites.
The final Persistence suite passed 29 tests.
The next planning task for Claude Opus is described in `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md`.
That planning task should produce one bounded implementation plan for a Claude Sonnet medium session and must treat the remaining engine, grading, practice-state, presentation, responsive, accessibility, and release gates in `handoffs/NEXT-SESSION-V1-HARDENING.md` as still open.

## V1 hardening phase 2 complete (2026-07-19)

Followed `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md` step by step; all six steps landed and every gate passed.
Full detail, including the live diagnosis evidence and the native E2E acceptance record, is in the `V1 hardening phase 2` section of `devlogs/2026-07-19.md`.
This checkout still has no physical `AGENTS.md`; the session prompt's repository rules remained authoritative.

### What changed

`AnalysisEngine` now stamps engine updates with the generation the search actually started under (`searchGeneration`) rather than the generation current at delivery time, closing the bulk of F2's cross-position score contamination.
That fix alone was insufficient in live testing: chesskit-engine dispatches each raw response through its own unstructured `Task` with no ordering guarantee, so `setPosition` now also waits for a UCI `isready`/`readyok` round trip plus a 30ms settle window before bumping the generation, unconditionally (not just when a search was in flight, since the reproduced race had `isSearching` already false at the point of entry).
This is documented in code as an empirically-verified mitigation, not a proof; 14 consecutive `engine-smoke` runs (70 repeated iterations of a new live generation-isolation assertion) passed clean after the fix.

A new `BoundedSearchSession` (`App/Sources/Chessanto/Analysis/BoundedSearch.swift`) is a `@MainActor`, engine-free coordinator that latches a search's outcome exactly once, closing F1 (a terminating bestmove arriving before anything was waiting for it, which previously hung forever).
`EngineService.searchOneShot` installs the session before sending `go`, races it against a deadline (`movetimeMilliseconds * 4 + 3000`), and both the timeout and cancellation paths now resolve with typed `EngineSearchError`s and tell the engine to stop.
`coachEvaluate`'s FIFO chokepoint (`coachEvaluateTail`) got a real cancellation-propagation fix (F4): a cancelled caller now actually cancels the queued work via a shared `runOnFIFOTail` helper, instead of the work running to completion unobserved.
`evaluateTrainingPosition` replaces `trainingEvaluationAfterMove`, sharing the same FIFO chokepoint without coupling the training domain to the Coach tool's `EngineToolResult` shape.

`WhitePerspectiveScore` (`App/Sources/Chessanto/Training/WhitePerspectiveScore.swift`) replaces the old `TrainingEngineEvaluation` two-optional pair throughout the training domain and both production call sites.
It cannot represent "both centipawns and mate" or "neither" at once, which is what let a forced mate compare against a `nil` best value and fall through to `.incorrect` (F7).

`DefaultTrainingMoveEvaluator` now short-circuits terminal positions (checkmate, stalemate) via `ChessCore` alone before any engine call (F3), grades a cached lower-ranked line against the cached rank-one score instead of blanket-accepting any cached line as strong with zero loss (F6), and implements a total mate-vs-centipawns comparison with no unrepresentable case (F7).
Two thresholds in that comparison are this evaluator's own judgement calls, not values the plan fixed: the mate-distance playable/inaccurate tiering beyond "shorter or equal is strong," and 200 centipawns as "clearly winning" when a forced mate was lost for a merely-good move.
Both are commented inline as deliberate choices.

A bounded-search failure during grading (`EngineSearchError`) is now recoverable: `PracticeSessionViewModel.submit` returns to `.prompt` with the card and board intact, records no attempt, advances no scheduler state, and surfaces a short retryable message via a new `promptError` field, rendered in `DesignColors.error`.
`.failed` stays reserved for a failure to load the lesson at all.

### Verification

The final app suite passed 55 tests across 15 suites (up from the phase-1 baseline of 31/13).
All package suites, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` passed.
`git diff --check` was clean.
`mattpocock-skills:code-review` ran against `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md` as the spec axis before the final commit; both real Standards findings (an unnamed magic-number deadline formula, an uncalled-out mate-threshold behavior change) were fixed, and the Spec axis's three "under-specified" findings were confirmed as deliberate judgement calls and documented inline rather than changed.

Native E2E acceptance used a disposable database copy under the sandbox container and the freshly built universal Release app; the live sandbox database was confirmed byte-identical (via `md5`) to the pre-session backup both mid-session and at the end.
Live-verified: F6's fix (a cached rank-3 line grades `Inaccurate`/`Engine loss: 99 centipawns`, not a blanket-accepted strong move), F1's fix (a real, non-cached move reaches the engine and returns bounded feedback, `Inaccurate`/`Engine loss: 217 centipawns`, with no hang), a genuine fresh `Analyze` pass (222 plies persisted in ~28s on a previously-unanalyzed game, after an initial false-positive test against an already-analyzed game that the skip-logic made a no-op), and Coach chat continuing to work through the shared FIFO after training evaluations had already run in the same process.
F7 (the mate-grading fix) was not exercised through native play, exactly as the plan anticipated, since it needs a cached card whose position admits a mate that is not the rank-one move; it is covered by the Step 5 tests only.
One unrelated, pre-existing bug was found along the way and not fixed (out of scope): the `Hikaru vs Casablanca` chess.com import (gameId 2 in the QA snapshot) fails to parse with `ChessKit.PGNParser.Error error 2`, matching the parser edge case already logged in the 2026-07-17 M4 devlog section.

### What's still open

The next planning task is described in `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md`.
It carries forward the full practice render-state machine, non-disclosing incorrect feedback and the distinct Reveal state, duplicate-submit rejection, review decisions for Reveal and Skip, Dashboard/practice presentation ownership, the 900-point replay and practice layout, accessibility coverage, promotion moves in practice, README/version alignment, a project-level `CLAUDE.md` (Follow-up A), and a root `CONTEXT.md` (Follow-up B) - all of which were out of scope for phase 2 and remain not started.

## UI/UX clarity planning complete (2026-07-19, planning only, no code)

An Opus planning session executed `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md` and produced three phase documents.
Full detail, including every live reproduction, is in the `UI/UX clarity: Opus planning session` section of `devlogs/2026-07-19.md`.

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` is a fully specified execution plan for one Claude Sonnet medium session.
`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` and `-PHASE-3.md` are deliberate scoping stubs, not designed in advance, because phase 1 restructures the surfaces they build on.

Everything was reproduced live in the Release app against a disposable database copy; the live sandbox database was confirmed byte-identical before and after.

Two findings overturned assumptions the bootstrap carried:

- The key-moment row hit-target bug is **not** a missing width modifier.
  Clicking the far right of the row already works; clicking the prose below the header line does not, because the `Button` wraps only the header line while the summary, narration, and caption are siblings outside it.
  A confident source-reading diagnosis was wrong for the second consecutive planning cycle.
- Playable variations need **no** schema migration.
  `RankedLine.principalVariationUCI` already persists a full PV, verified directly against `trainingCard.rankedLinesJSON`.

Pin and favorite, by contrast, genuinely have no data model in any migration `v1` through `v5` and would need a forward-only `v6`.

The user added one feedback item mid-session and resolved its ambiguity directly: practice must run inline on the existing full-size board with no modal sheet, while the training-card model, the spaced-repetition scheduler, and the Progress queue stay exactly as they are.
That decision is the structural anchor of phase 1.

`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains separately open and is not superseded.

## UI/UX clarity phase 1 complete (2026-07-19)

Followed `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` step by step; all six build steps and full verification landed.
Full detail, including live E2E evidence and one real bug found and fixed during native testing, is in the `UI/UX clarity phase 1` section of `devlogs/2026-07-19.md`.

### What changed

- `ChessGlossary` (`App/Sources/Chessanto/Training/ChessGlossary.swift`), a pure lookup mapping `en prise`, `hanging`, `forced mate`, `O-O`, `O-O-O`, and the eight `MoveClassification` cases to a one-sentence plain-language gloss, term kept beside its real name rather than replacing it (DD2).
- `BoardTheme.hint` and `BoardView.hintSquares` render the practice hint's target square as a fourth, distinct board channel (brass accent plus a stroked ring), never overloading last-move/selected/destination (DD3).
  `PracticeSessionViewModel.hintSquares` exposes the best move's origin square once `hintCount >= 2`.
- `GameReportView.keyMomentRow` was restructured (DD4) so the entire block - header, summary, Coach narration, source caption - is the jump target, via a `KeyMomentRowButtonStyle` that adds a hover/pressed `surface1` background where a bare `.plain` style would show none.
  A prior planning session's confident source-reading diagnosis of this exact code (a missing `.frame(maxWidth: .infinity)`) was wrong for the second consecutive planning cycle; the real defect was vertical (the `Button` wrapped only a 20pt header line), not horizontal, and was found only by a real click test.
- `BoardIdentityStrip` (`App/Sources/Chessanto/Board/BoardIdentityStrip.swift`) is a pure helper plus `BoardIdentityStripView`, rendering compact name/rating/"You" strips above and below the board, bound to screen position (top/bottom) rather than color so they swap correctly on flip (DD5).
- Inline practice mode (DD1): `PracticeSessionView.swift` is now `PracticeContentView.swift` (prompt/hints/feedback/progress only, no board, no frame); `PracticeBoardSection` is a new `@ObservedObject`-driven board wrapper.
  `GameReplayView.RightPaneTab` gained a programmatic-only `.practice` case; the fixed 420pt board and 760x560 sheet minimum are deleted, not enlarged.
  `GameReplayViewModel.isPracticeActive`/`enterPractice()`/`exitPractice()` suspend live engine analysis while practice shows a position that isn't a ply of this game.
  The Dashboard's practice entry points no longer own a `.sheet`; `DashboardView.onOpenPractice` and `ContentView`'s new `pendingPracticeGameID`/`pendingPracticeLoadCards` hand the session to `GameReplayView`, which owns game selection already.
- Plain language (D1/DD2): the practice prompt's classification chip now renders its word alongside the glyph (`PracticeSessionViewModel.classificationLabel`), and theme hints gloss their term (`themeHintTextIgnoringHintCount` - see the bug note below for why it's not just `themeHintText`).
- DD6 (stable hint layout): both hint lines reserve real, final-content height from the start of a card rather than a shorter placeholder, so a second `Hint` press at the same screen point lands correctly.

### A real bug found and fixed during native E2E, not caught by unit tests or code review

The first DD6 implementation swapped between a short placeholder string (hidden via opacity 0) and the real hint text (shown via opacity 1) to "reserve space."
This does not work when the real text is longer and wraps to more lines than the placeholder: native testing (two real `cliclick` presses at one fixed, un-recomputed screen coordinate) showed the `Hint` button shifting downward after the first press, so the second press missed.
Fixed by adding `PracticeSessionViewModel.themeHintTextIgnoringHintCount`, which is always the real, final gloss text; the view renders it unconditionally and only toggles opacity by `hintCount`, so the reserved height is the actual height.
Re-tested with the same fixed-coordinate double-click and confirmed both presses landed, including the level-2 hint's board-square highlight.

### Verification

The final app suite passed 70 tests across 17 suites (up from the phase-2 baseline of 55/15): `ChessGlossaryTests` (4), `BoardIdentityStripTests` (5), 4 new `PracticeSessionViewModelTests`, and 2 new `GameReplayViewModelTrainingTests`.
All package suites (`ChessCore`, `AnalysisKit`, `CoachKit`, `EngineKit`, `ChessComKit`, `Persistence`), `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` passed.
`Packages/Persistence` was unchanged, as expected (no schema migration in this phase).
`git diff --check` was clean.

Native E2E acceptance used a disposable database copy under the sandbox container (game 9, `adamzainuri vs WillisLiao`) and the freshly built universal Release app.
All seven acceptance scenarios from the plan were reproduced live: no `AXSheet` anywhere in the practice flow; the key-moment block's summary prose (not just its header) now jumps the board, and the nested `Practice` button still opens a single-card session independently; the identity strips render and swap correctly on flip; hint clarity/stability including the board-square highlight; plain-language classification on a correct answer; the Dashboard's "Review next lesson" opening inline practice on the correct game with no nested sheet; and the live sandbox database confirmed byte-identical (`md5`) before and after the whole session.

### What's still open

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` (playable variations, Coach text density) has been expanded with what phase 1 actually built, and is the next planning task.
`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-3.md` and `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remain open and untouched by this phase.
Not done and not claimed: playable variations, Coach text density, sidebar select/delete/pin/favorite, the richer player dashboard, chess.com identity confirmation in onboarding, and the remaining V1 hardening phase 3 backlog.
One cosmetic, out-of-scope gap noticed live and not fixed: the practice session-complete screen shows an empty board (no pieces) since `currentCard` is `nil` at that state; carry into a future polish pass if it comes up again.

## UI/UX clarity phase 2 planning complete (2026-07-19, planning only, no code)

A Claude Sonnet session expanded `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` from a scoping stub into a fully specified execution plan, the way the Opus session expanded phase 1.
No product code changed; this was planning and live verification only.
Full detail is in the `UI/UX clarity phase 2 planning` section of `devlogs/2026-07-19.md`.

Verified live against a read-only copy of the real production database (never written to, md5 confirmed unchanged before and after): card 6's rank-1 engine line is 15 plies deep while its rendered explanation shows only 6 SANs, confirming the "better line" data already exists in full on both the Practice and Report models with no schema change needed.

One real trap found and corrected: the stub's "actual bad continuation that was played" could be misread as `PunishmentFact.refutingSAN`, but that fact is the engine's hypothetical best reply to a mistake, not a record of what the opponent actually played in the game.
The plan sources the real continuation from the game's own mainline instead.

The design locks a single new module, `LinePreviewController` (pure, `ChessGame.replayLine`-backed, no persistence), owned independently by `PracticeSessionViewModel` and by `GameReplayView`, explicitly never touching `GameReplayViewModel`'s persisted `variation` table - reusing `adoptLine` for this would have silently written DB rows for every line the learner previews.

Coach text density: `card.explanation` (Practice's post-answer feedback) and the Report's rule-based fallback text share the same underlying string, so one rendering-only fix (sentence-level chunking, not truncation, not a new disclosure affordance) fixes both surfaces at once.
`CoachVerifier` was confirmed to check numeric claims anywhere in the response text rather than requiring the parenthetical-eval format the prompt asks for, so the rendering fix cannot weaken grounding; any `CoachPrompt` wording change stays conditional on that rendering fix proving insufficient, and is gated on a real fallback-rate measurement, not a single run.

This historical planning note is superseded by the completed phase 2 and phase 3 implementation records below.

## UI/UX clarity phase 3 and visual-system redesign complete (2026-07-19)

Phase 3 is implemented and verified.
Phase 2 was subsequently implemented on 2026-07-19, as recorded at the top of this handoff.
Full implementation and native E2E detail is in the `UI/UX clarity phase 3 and visual-system redesign` section of `devlogs/2026-07-19.md`.

### Library organization and recoverable deletion

- A forward-only `v6_gameOrganization` migration adds `pinnedAt`, `isFavorite`, and `deletedAt` to `game`, plus the active-library ordering index.
- A forward-only `v7_confirmedChessComIdentity` migration records whether the saved chess.com username completed the explicit account-proof flow.
- `GameStore` now exposes atomic pin, favorite, move-to-Recently-Deleted, restore, and permanent-delete commands.
- Normal game navigation remains single-selection, while a separate Organize mode owns multi-selection so bulk actions never destabilize the open replay detail.
- The sidebar has persistent All Games, Favorites, Player Brief, and Recently Deleted sources, plus explicit pinned and favorite controls.
- Moving games to Recently Deleted supports immediate undo and preserves analysis, variations, training cards, chat, and all other dependent data.
- Permanent deletion is isolated inside Recently Deleted and requires typed confirmation before the existing cascade can run.
- Deleted games are excluded from the active library and training queue.

Two source-level assumptions from the stub were corrected during implementation.
The existence of a cascading `deleteGame` data-layer method did not make direct destructive deletion an appropriate UI primitive, so the shipping flow is recoverable by default.
The main `selectedGameID` binding did not need to become a `Set<Int64>` to support bulk work, because a separate organization selection preserves the detail pane's navigation contract more cleanly.

### Evidence-based Player Brief

- The former Progress destination is now a persistent, labeled Player Brief source rather than a hidden chart icon.
- `PlayerInsightBuilder` derives the current finding, costly-move count, phase distribution, color and time-control context, repeated lesson themes, and classification counts only from stored analyzed-game evidence.
- The brief names a strength only when both sides of a comparison have at least three games and differ by at least five accuracy points.
- Sparse samples show explicit thresholds and caveats instead of decorative empty charts or invented tactical and positional claims.
- Equal thirds are labeled First, Middle, and Final third, with a methodology note that they are game-relative segments rather than formal chess phases.
- The presentation is a compact analysis memo with aligned registers and ruled sections rather than a dashboard of floating cards.

### Confirmed chess.com identity

- `ChessComProfile` and `ChessComStats` decode the public account proof needed for confirmation, including profile URL and available ratings, while allowing the stats request to fail without discarding a valid profile.
- `ChessComAccountLookupModel` separates candidate lookup from explicit confirmation, rejects stale asynchronous results, and never persists an unconfirmed username.
- The same text-only account proof and confirmation flow is shared by onboarding and Settings.
- Legacy saved usernames migrate as unconfirmed and are never labeled Connected or accepted by Player Brief until the user confirms the account once.
- The design deliberately does not fetch the remote avatar, preserving the app's local-first posture while still showing enough account evidence to make the identity choice explicit.

### Company-designed native visual system

- The entire app now follows a native macOS scorebook and analysis-desk direction: flat ruled sections, dense aligned rows, restrained brass selection, square analytical instruments, system typography, and clear hierarchy.
- Rounded display type, generic emblem tiles, capsules, gradients, decorative shadows, and floating card chrome were removed from the shared design system and major app surfaces.
- The library, replay workspace, report, Coach, onboarding, Settings, evaluation graph, evaluation bar, move classifications, and player identity treatments now use the same visual grammar.
- The analysis workspace now presents a compact Game audit, Key-moment register, Review notes, and a quieter Review toolbar.
- The prior narrow-width evaluation label wrap was fixed as part of the whole-app polish request.

### Verification and database safety

The final app suite passed 75 tests across 19 suites.
All package suites passed: `ChessCore` 21, `AnalysisKit` 63, `CoachKit` 74, `EngineKit` 1, `ChessComKit` 4, and `Persistence` 35.
`engine-smoke` passed every real-engine and generation-isolation check.
`coach-grounding` completed 10 Coach runs with zero violations and zero leaks.
`scripts/release-build.sh` produced a successful universal arm64 and x86_64 Release build.
`git diff --check` was clean.

Native E2E ran only against a disposable database copy under the app container.
It verified bulk recoverable deletion, Recently Deleted selection, restore, retained analysis after restore, Player Brief recomputation, the library, replay workspace, onboarding, and Settings.
A finite-height bug in the first Recently Deleted implementation was visible only in the running app and was fixed by replacing the nested `List` with a bounded selectable `ScrollView`.

The final safety check detected that the live database had received only the new v6 schema migration during the build and test cycle.
All user-data table counts matched the pre-session backup exactly.
With no Chessanto process running, the live file was restored from the mandatory pre-session backup and its md5 returned to the original `1d218f0371a61f85bc682cc43acb9af5`.

### What's still open

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` now preserves the investigation and records the completed implementation.
`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains a separate unstarted backlog and was not superseded.
The phase 3 document now records the locked design decisions, test-first sequence, and native acceptance record.
The Codex briefing remains as the historical input this implementation followed and re-verified.

## iPhone-first companion complete (2026-07-19)

The approved iPhone-first companion is implemented across the Mac app, the new iPhone target, and the new shared `CompanionKit` package.
The complete execution and verification record is in `handoffs/IPHONE-COMPANION-EXECUTION.md`.

Secure pairing uses signed five-minute invitations, a matching phrase, explicit Mac approval, wrapped content keys, authenticated encryption, replay defense, rotation, and revocation.
The phone can request the Mac's local analysis, receive exact progress and terminal status, cancel work, receive the completed portable report, and retain encrypted reports for offline review.
Local and remote analysis now share one application service, and a durable ledger prevents redelivery from starting duplicate engine work.

The Coach now has explicit speech controls on Mac and iPhone plus six deterministic emotional portraits.
Speech uses an original slower, lower-pitched sage delivery and never starts automatically.

The user corrected key-moment behavior during implementation.
Selecting a key moment now only jumps to the position and stops an existing preview.
Only Show better line or Replay better line starts playback.

Native Release QA used only `/Users/willis/Library/Containers/com.chessanto.app/Data/tmp/iphone-companion-20260719-211052/chessanto.sqlite`.
The live database MD5 remained `26f0882ad0e3ffdfc7a065a5791f8b5f` before and after QA.

The macOS suite passes 104 tests across 27 suites, `CompanionKit` passes 29 tests across 10 suites, the iPhone target passes 3 tests across 2 suites, every existing package suite passes, and the universal Release build succeeds.

Physical CloudKit pairing remains an external provisioning acceptance step.
This checkout has no Apple Developer team or private iCloud container, so the apps show an honest blocker until the owner configures the same container and `ChessantoCloudKitContainerIdentifier` for both targets.

## Final companion hardening and Kokoro TTS integration (2026-07-19)

The companion implementation has been fully audited, finalized, committed, and pushed. On top of that, Kokoro TTS has been integrated as the primary natural-sounding voice for the Coach.

### Companion Delivery
- The companion work was committed under hash `c2e349d1140950d1e6457cc1e4916fcb5f4a21a7` and pushed to remote `main`.
- Pre-commit audits verified no secrets, no trailing whitespaces, and no accidental files.
- The live SQLite database was restored to its backup state with MD5 `26f0882ad0e3ffdfc7a065a5791f8b5f` and WAL/SHM sidecars were removed.
- All test counts are fully verified:
  - macOS app: 107 tests in 27 suites.
  - CompanionKit: 32 tests in 11 suites.
  - iPhone app: 4 tests in 3 suites.
  - Local packages and grounding/smoke targets all green.

### Kokoro TTS Integration
- **Selected Voice:** George (`bm_george` preset), British male (deeper, measured).
- **Server:** A local lightweight HTTP server (`server.py` in `.voice-demo/`) exposes `/tts` (and `/v1/audio/speech`) running on port `8888` using the Kokoro-82M ONNX model.
- **Client:** `DesktopCoachSpeechController.swift` (macOS) and `OfflineReportReader.swift` (iOS) check if `http://127.0.0.1:8888/tts` is active. If so, they send a POST request with text, stream audio via `AVAudioPlayer`, and support standard speech controls.
- **Fallback:** If the server is offline or fails to respond within 1.2s, the app falls back seamlessly to the native Apple `AVSpeechSynthesizer` voices.
- Committed under hash `dc52df8076935cae2030ee28929e00db7583641b` and pushed to remote `main`.
- Physical CloudKit pairing remains blocked on Apple Developer team and container setup.
- The latest compiled Release app is located at:
  `/Users/willis/Library/Developer/Xcode/DerivedData/Chessanto-dvybgihmaxaffpbutfmycvjeqlkn/Build/Products/Release/Chessanto.app`



## Future directions (explicitly out of v1)

Repertoire training, play-vs-engine, Lichess import, iCloud sync, Chess960, richer search/filtering, and a dedicated accessibility UI-test matrix.
Post-v1 priorities not yet decided with the user - ask before starting new work here.
