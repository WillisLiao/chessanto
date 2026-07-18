# Chessanto - Handoff

Living snapshot of project state.
Read this first at session start; update it at session end.

## Current state (2026-07-18)

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

## Future directions (explicitly out of v1)

Repertoire training, play-vs-engine, Lichess import, iCloud sync, Chess960, richer search/filtering, and a dedicated accessibility UI-test matrix.
Post-v1 priorities not yet decided with the user - ask before starting new work here.
