# Next session: M7 - position chat

This is a bootstrap, not a fully de-risked execution plan like M6's -
read it, then re-derive the details from the current code and `PLAN.md`
rather than treating every line here as fixed.
Given how much M6's own prep session paid off (it caught the
4096-default-context trap, the mid-stream pull errors, the gemma3
no-tools gap, and the SAN-suffix trust trap before any code was written),
strongly consider running a similar prep-only session for M7 first -
rewriting this file into a verified execution plan - rather than
executing straight from this bootstrap.

## Where things stand

M1-M6 are done and pushed to `main` at
https://github.com/WillisLiao/chessanto.
Read `handoffs/HANDOFF.md`'s current-state section (M6's entry in full)
and `PLAN.md`'s "Position chat" section before starting:

> Chat panel attached to the currently viewed position (mainline or user
> variation), with game context (moves so far, evals, prior coaching) in
> the prompt. When the user proposes a move or line ("what about Nf3?"),
> the app first validates legality via ChessCore, then evaluates the
> resulting position with Stockfish, and injects the verified eval and PV
> into the LLM prompt before it answers. The chat runs the full Verified
> Coach stack: engine-tool loop for exploration, CoachVerifier gate on
> every response. Streaming responses. Persist chat history per game in
> SQLite.

## What already exists to build on

- **The entire Verified Coach stack is real and working** (M6, full
  detail in the devlog's "M6 execution" section and
  `handoffs/NEXT-SESSION-M6.md`'s design decisions, which still describe
  the current architecture accurately):
  - `CoachKit.OllamaClient` - native `/api/chat` streaming, `think:false`,
    explicit `num_ctx`, tool-call decode. Chat just needs another caller;
    the client itself needs nothing new.
  - `CoachKit.CoachVerifier` - the hard gate (SAN/UCI token extraction,
    legality-then-UCI-re-replay, PV-prefix or landed-on-known-anchor line
    verification, eval/mate/percentage tolerance checks, an
    at-most-once-per-response fresh-verification hook). Position chat
    needs the **same** verifier; only the `Context` (anchors) it's
    constructed with will differ per turn (the position being discussed,
    plus whatever the tool loop looks up).
  - `CoachKit.EngineToolExecutor`/`EngineToolResult` - the `evaluate(fen,
    moves)` tool contract. `App.EngineService.coachEvaluate` already
    implements it live (real Stockfish, replay-validated args,
    stop/resume around live analysis). Chat's "validate legality, then
    evaluate, then inject into the prompt" requirement (PLAN.md) is
    *exactly* what this executor already does - reuse it directly rather
    than writing a second engine-tool path.
  - `CoachKit.CoachNarrator` - PLAN.md's own words for M7 point here
    directly: "CoachNarrator's loop becomes the chat turn loop". Its
    generate -> verify -> regenerate-once -> fallback shape is a turn
    loop already; what's missing is multi-turn *conversation* state
    (accumulating prior chat messages as context across turns, not just
    within one narration's own tool-call sub-loop) and a chat-specific
    prompt/payload (position + moves-so-far + evals + prior coaching,
    per PLAN.md, rather than a `KeyMoment`).
  - `CoachKit.CoachModelCatalog`, `App.CoachService`,
    `App.CoachSettingsView` - model/settings plumbing chat can reuse
    as-is (same `coachModel`/`coachEnabled`/`ratingBand` from
    `userProfile`).
- **`chatMessage` table exists in the schema** since the v1 migration
  (`Persistence/Sources/Persistence/Schema.swift` lines 51-59):
  `id`, `gameId` (FK, cascade delete), `plyIndex`, `role`, `content`,
  `createdAt`. **No `ChatMessageRecord` type or `GameStore` CRUD methods
  exist yet** - this is real M7 work, following the exact pattern of
  `AnalysisRecord`/`VariationRecord` (a plain `Codable`/
  `FetchableRecord`/`MutablePersistableRecord` struct + `GameStore`
  insert/fetch/delete methods, tested the same way
  `PersistenceTests.swift` tests the existing record types).
- **`GameReplayViewModel`/`GameReplayView`** already track
  `currentIndex`/`currentFEN`/`isExploringVariation` for whatever
  position is displayed (mainline or a variation) - the chat panel's
  "currently viewed position" context (PLAN.md) is already available
  here, no new position-tracking needed.
- **Exploration Mode (M3)** already validates user-proposed moves via
  ChessCore (`ChessGame.playMove`/`legalMoves`) before playing them on
  the board - the same legality-validation primitive PLAN.md wants for
  chat's "user proposes a move" flow (`playMove(san:at:)` for legality,
  then `replayLine(fromUCI:)` for board facts, per fact 15's fixed
  pattern - do not trust the SAN path's own check/mate flags).

## What M7 needs to build, roughly (verify/re-derive before executing)

1. **`ChatMessageRecord` + `GameStore` CRUD** (Persistence) - plain
   record + insert/fetch/delete-by-game, tested like the existing
   records.
2. **A chat payload/prompt variant** (CoachKit) - `CoachPayloadBuilder`
   needs a chat-turn payload (current FEN, moves-so-far, prior coaching
   context if any, the user's message) alongside its existing
   moment/summary payloads; `CoachPrompt` needs a chat system/user
   message pair. Reuse `RatingRegister` as-is.
3. **A multi-turn conversation orchestrator** (CoachKit) - likely a
   `CoachChat` type sitting next to `CoachNarrator` (or an extension of
   it) that keeps a running message list across turns, appends the
   user's new message, runs the same generate -> verify ->
   regenerate-once -> fallback shape per turn, and returns a
   `CoachNarration`-shaped result per turn. Decide whether fallback on a
   chat turn should be a rule-based sentence (there's no `KeyMoment` to
   derive one from - probably a fixed "the coach couldn't verify a
   confident answer" message) rather than `ReportText` output.
4. **User-proposed-move validation** (App or CoachKit) - PLAN.md:
   "validates legality via ChessCore, then evaluates ... with Stockfish,
   and injects the verified eval and PV into the LLM prompt before it
   answers." This sounds like: before sending the user's chat message to
   the LLM, if it contains a proposed move/line, pre-run it through
   `EngineService.coachEvaluate` (or a ChessCore legality check first,
   short-circuiting on illegal moves with a canned response - no LLM
   call needed for "that's illegal") and fold the verified result into
   the payload, rather than relying on the LLM to call the tool itself
   every time. Needs a design decision, not just an execution step.
5. **Streaming UI** - `OllamaClient.chat` already streams; the coach
   narration UI so far only ever showed a fully-verified final text
   (`CoachNarrator` buffers internally, per the "nothing unverified
   renders, including mid-stream" rule). Chat likely wants the same
   buffer-then-render discipline per turn (a "Coach is typing..." state,
   then the verified text appears atomically) rather than streaming raw
   unverified tokens to the screen - re-confirm this against PLAN.md's
   intent before building a token-by-token UI.
6. **Chat panel UI** (App) - a new view (sheet or side panel?) attached
   to `GameReplayView`, message list rendered from persisted
   `chatMessage` rows + in-flight turns, a text input, wired to
   whatever `CoachService` extension step 3 produces. Follow the M3
   accessibility lesson: real native controls only.

## Working style notes (carried forward; they keep paying off)

- Verify third-party APIs and regexes against real data before trusting
  them - M6's biggest catches (the context-window trap, the mid-stream
  pull errors, the `\b`-can't-match-a-suffix regex defect) all came from
  testing against real transcripts/text, not from reading documentation.
- Real E2E through the built app via `osascript`/System Events
  **AX-element** references only; raw pixel clicks and screenshots are
  blocked in this sandbox.
- Any new interactive UI must be real `Button`s/native controls.
- After adding/removing files under `App/`, rerun `xcodegen generate`.
- Debug on stderr, never stdout; Release builds for anything
  timing-sensitive.
- The sandboxed DB for E2E checks: `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
- Commit and push milestone work together with updated handoffs and a
  dated devlog entry.
