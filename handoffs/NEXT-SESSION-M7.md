# Next session: M7 - position chat

This is a self-contained execution plan for a fresh session with no prior context.
It was prepared by a 2026-07-17 prep session (the same discipline as M6's prep) that read every source file M7 builds on in full, verified the new conversational mechanics against the live Ollama 0.31.2 server, and ran a real ChessCore scratch package to pin down the proposed-move precheck's behavior - the facts below are verified, not guessed.
Follow it step by step; the design decisions are already made, do not re-derive or re-litigate them.
Read `PLAN.md`'s "Position chat", "Verified Coach", and M7 milestone sections for product context, but where this file is more specific, this file wins (one deliberate deviation from PLAN.md's "Streaming responses" bullet is called out and justified in the design decisions).

The accept criterion (PLAN.md M7):

- Chat panel per the design: legality check, engine-tool loop, CoachVerifier gate, persistence, works from any explored variation position.
- Suggested starter questions per key moment.
- Ask "what if I played <legal move>?" and the answer cites the actual engine eval of that move.
- Ask about an illegal move and the app says it is illegal rather than sending it to the LLM.
- Ask an open question ("how do I attack here?") and watch the coach make at least one engine tool call before answering.

The M5/M6 discipline carries over unchanged: **nothing unverified ever renders.**

## Where things stand

M1-M6 are done and pushed to `main` at https://github.com/WillisLiao/chessanto.
The entire Verified Coach stack is real and working; M7 is mostly reuse plus one new orchestrator, one new persistence record, and one new UI panel.
What M7 builds on (every file below was read in full this prep session):

- **`CoachKit.OllamaClient`** (`OllamaClient.swift`, `OllamaModels.swift`): needs nothing new.
  Multi-turn history and tools-with-history were verified live this session (facts 1-2); the client's `chat(model:messages:tools:numCtx:temperature:)` already takes an arbitrary message list.
- **`CoachKit.CoachVerifier`**: reused as-is - its `Context`/`Anchor` types are already position-agnostic (any FEN can be an anchor), so chat only changes what context gets assembled per turn, not the verifier.
  Its tokenization regexes are `private`; step 2 exposes them (fact 4 shows they behave correctly on chat-style questions).
- **`CoachKit.CoachNarrator`**: its private `runConversation(messages:client:model:executor:toolCallBudgetRemaining:)` is already a complete single-turn engine (stream, detect tool calls, execute through the executor, collect anchors, budget cap) operating on an `inout` message list.
  The chat loop is this exact function called from a type that keeps the message list alive across turns - step 4 makes it `internal` and shares it rather than forking it.
  `CoachNarrator`'s own behavior must stay byte-identical (its tests plus `coach-grounding` lock it).
- **`CoachKit.EngineToolExecutor` / `App.EngineService.coachEvaluate`**: reused directly - this is PLAN.md's "validates legality via ChessCore, then evaluates ... with Stockfish" in one call.
  One real change is required: serialization of concurrent calls (fact 3).
- **`chatMessage` table** exists in the v1 migration (`Persistence/Sources/Persistence/Schema.swift` lines 51-59): `id`, `gameId` (FK, cascade delete), `plyIndex`, `role`, `content`, `createdAt`.
  No record type or `GameStore` CRUD exists yet; that is step 1, plus a v2 migration for a `source` column (fact 8).
- **`App.GameReplayViewModel`** already exposes `currentFEN`, `isExploringVariation`, `currentGraphPly` (the mainline ancestor ply of the displayed position), `report`/`reportInput`, and `userProfile()`/`userRatingInThisGame`.
  Moves-so-far including variation paths comes from `ChessGame.history(upTo:)` (fact 6); the VM needs only a small accessor since `chessGame` is private.
- **`App.GameReplayView`** has a two-segment right pane (`RightPaneTab`: Moves / Report); chat becomes the third segment.
- **`App.CoachService` / `CoachSettingsView` / `CoachModelCatalog`**: model/settings/health plumbing reused as-is (same `coachModel`/`coachEnabled`/`ratingBand`; `RatingRegister.resolve` unchanged).

## Verified facts (each was checked live or by a real scratch run this prep session)

1. **Multi-turn chat history round-trips on the live server (Ollama 0.31.2, `qwen3:0.6b`).**
   A 4-message conversation (`system`, `user`, `assistant`, `user`) with `think:false` and `num_ctx:8192` returned a correct recall of content stated two turns earlier:

   ```
   user:      "In this position the best move is Nf3 with eval +0.4. Remember that."
   assistant: "Understood: the best move here is Nf3 (+0.4)."
   user:      "Which move did you say was best, and what was its eval?"
   -> "The best move is **Nf3** with an **eval of +0.4**."   (prompt_eval_count: 93)
   ```

2. **Tool calls fire with conversation history present - and the model mangled its arguments again, live.**
   The same request shape chat will send (system + prior user/assistant turn + new question + the existing `evaluate` tool schema) produced a real `tool_calls` chunk, whose `fen` argument had the move list concatenated onto the FEN (`"...KQkq - 0 1. e2e4"`) while `moves` was correct.
   This is M6's fact 10 reproduced on demand: `coachEvaluate`'s replay-validation guard (invalid FEN -> typed error result) is load-bearing for chat too; never relax it.

3. **Concurrent LLM requests are safe server-side; the real hazard is `EngineService.searchOneShot`'s singleton collector state.**
   Two simultaneous `/api/chat` requests to the same loaded model both completed correctly (the short one even finished first - Ollama parallelizes or queues internally; either way no errors).
   But `EngineService.searchOneShot` stores its state in single `batchCollector`/`batchGeneration` fields on the `@MainActor` class; two interleaved `coachEvaluate` calls (a narration tool call and a chat tool call, both legal once chat exists) would clobber each other across suspension points.
   Fixed decision: serialize `coachEvaluate` app-side with a FIFO task chain (design decisions below); do not try to fix this with UI-level "disable chat while narrating" rules.

4. **The verifier's extraction regexes behave correctly on chat-style questions - and expose three real traps for the precheck.**
   Scratch run over the exact `private` patterns from `CoachVerifier.swift`:

   ```
   "what about Nf3?"                 -> [Nf3]
   "What if I played e4?"            -> [e4]
   "should I castle O-O here?"       -> [O-O]
   "what about Nf3 or Bc4?"          -> [Nf3, Bc4]     (two separate chains)
   "why not Qxg5??"                  -> [Qxg5]         (annotation suffixes stripped fine)
   "is e2e4 good here?"              -> [e2e4 as UCI]
   "can I promote with e8=Q?"        -> [e8=Q]
   "how do I attack here?"           -> []             (open question, nothing extracted)
   "what about nf3?"                 -> []             (lowercase piece letter never matches)
   "what if I take on d5?"           -> [d5]           TRAP 1
   "the knight on c6 looks strong"   -> [c6]           TRAP 1
   "was 24...Qd7 really a blunder?"  -> [Qd7]          TRAP 2
   ```

   TRAP 1: bare-square tokens are usually square *references*, but they extract like pawn moves; in the test FEN, `d5` was a legal pawn move (wrong meaning - the user meant capturing on d5) and `c6` was an illegal one (a naive precheck would answer "that's illegal" to a sentence proposing nothing).
   TRAP 2: a number-prefixed move (`24...Qd7`) references a move played earlier in the game; testing its legality against the *current* position and short-circuiting "illegal" would be wrong.
   The precheck rules in the design decisions are built around these three observed cases.

5. **The precheck's legality/replay sequence works from arbitrary mid-game FENs, and M6's suffix trap reproduces exactly as documented.**
   Scratch run against real ChessCore, from a mid-game black-to-move FEN: legal SAN (`Nd4`, `Bc5`, `d5`, `a5`) replays with correct UCI and resulting FEN; illegal SAN (`Nf3`, `O-O`, `Nxe4`) returns `nil` cleanly; multi-move chains (`Bc5 O-O d6`) derive a 3-ply UCI line that `replayLine` reproduces.
   From a position where Qxf7# is available: bare `Qxf7`, suffixed `Qxf7#`, and long-algebraic `Qf3f7` all replay to `san="Qxf7#", isCheckmate=true` via `replayLine` - and note `isCheck` is `false` when `isCheckmate` is `true` (the flags are exclusive in `ReplayedMove`; `CoachVerifier.checkSuffixClaim` already handles this).
   Bonus tolerance: a spurious capture marker is accepted (`Qxg5` on a non-capture plays as `Qg5`); the replay-derived SAN is always the canonical one.

6. **`ChessGame.history(upTo:)` returns the full path from the start through the given index, variation branches included** (`ChessGame.swift` line 74, mapping chesskit's `MoveTree.history(for:)`).
   This is exactly "moves so far + how the user got there" for the chat payload, with no new tree code.

7. **Chat payload size is a non-issue at `num_ctx` 8192.**
   120 plies of SAN is roughly 240 tokens; the M6 moment payloads plus ranked lines measure well under 2000 tokens; a 12-message history cap (design decisions) keeps the whole request comfortably inside 8192.
   Keep `runConversation`'s hardcoded `numCtx: 8192` unchanged.

8. **The `chatMessage` schema has no column for the source/honesty label - a v2 migration is needed.**
   M6's UI labels every rendered text "Coach" vs "Rule-based"; chat must preserve that honesty across relaunch (a fallback reply must not resurrect as coach prose).
   `Schema.swift`'s migrator is built for appending migrations ("never edit a migration that has already shipped"); this is the first post-v1 migration.

9. **`CoachNarrator`'s internals are refactor-safe for sharing.**
   `runConversation` takes `messages: inout [OllamaChatMessage]` plus client/model/executor/budget and returns `(text, toolCallsUsed, newAnchors)`; `toolResultJSON` and `errorMessage` are pure helpers.
   Changing these three from `private` to `internal` changes no behavior; CoachKit's 40 existing tests (which lock the narrate -> verify -> regenerate-once -> fallback state machine through the public API) are the gate that the refactor touched nothing.

## Fixed design decisions (use them everywhere)

### The four open questions from the old bootstrap, resolved

1. **How the loop becomes multi-turn: a new `CoachChat` actor in CoachKit, sharing `CoachNarrator`'s turn engine.**
   `public actor CoachChat` holds the durable conversation state: the LLM message list (system prompt + pruned prior turns), the accumulated verifier anchor pool, and the FEN the last context block was built for.
   Per turn, `send(...)` runs: precheck (decision 3) -> optional seed evaluation (below) -> `CoachNarrator.runConversation` (now `internal`; fresh tool budget of 6 per turn) -> `CoachVerifier.verify` -> regenerate once with violations fed back -> canned fallback on second failure.
   After the turn resolves, the message list is pruned to user text + final rendered reply only: tool round-trips, failed attempts, and violation-feedback messages are dropped (anchors they produced are kept in the pool), and history is capped to the last 12 messages.
   An actor serializes turns by construction; `CoachService` additionally disables Send while a turn is in flight.
   `CoachNarrator` itself is untouched in behavior; only `runConversation`/`toolResultJSON`/`errorMessage` go `private` -> `internal` (fact 9).

2. **The chat payload/prompt shape.**
   The app builds a `CoachChatContext` (plain values from the VM); `CoachPayloadBuilder.chatPayload(...)` turns it into a Codable `CoachChatPayload`:
   - current FEN and side to move; whether this is a mainline position or a user variation, and if a variation, the SAN path from the branch point (fact 6's `history(upTo:)`);
   - moves so far as numbered SAN (mainline up to the position, then the variation segment marked as such);
   - the current position's ranked lines: from `cachedAllRanksByPly` when the position is an analyzed mainline ply (same mapping `buildReport()` uses), otherwise from the seed evaluation below;
   - the key-moment one-liner (`ReportText.momentSummary`) when the current ply is one of the report's key moments;
   - players, result, and accuracies when the game is analyzed (all optional - chat must work on unanalyzed games).
   `CoachPrompt` gets `chatSystemPrompt(register:)` = the existing register text + the existing two grounding rules + two chat-specific sentences: answer the student's question about the current position, and for open questions ("how should I continue?") check at least one concrete line with the `evaluate` tool before answering.
   The JSON context block is injected into the user turn whenever the current FEN differs from the last turn's context FEN (first turn always); otherwise the user turn is just the question plus any precheck-verified data.
   **Seed evaluation**: when the payload has no ranked lines for the current position (variation or unanalyzed game), `CoachChat` runs one `executor.evaluate(fen, [])` before generating, injects the result into the payload, and adds it as an anchor - so the model always has at least one verified eval to cite; if the executor refuses (batch analysis running), proceed payload-only.

3. **User-proposed-move validation happens BEFORE the LLM, in code - not via the LLM's own tool call.**
   PLAN.md fixes this ("the app first validates legality via ChessCore, then evaluates ... and injects the verified eval and PV into the LLM prompt before it answers") and the accept criterion demands the illegal case never reaches the LLM.
   Expose the verifier's tokenization as `public static CoachVerifier.moveTokenChains(in:)` returning, per chain: raw tokens, the bare-square flag, and the leading-number-marker flag (a thin public wrapper over the existing private `citedLineChains`; `verify()` behavior unchanged).
   Precheck classification, built on fact 4's traps:
   - a chain that is a single bare-square token -> square reference, skip (TRAP 1; never precheck, never canned-illegal);
   - a chain with a leading number marker -> game-history reference, skip (TRAP 2; the payload's moves-so-far lets the LLM answer, the verifier still gates);
   - every other chain (piece moves, captures, castling, promotions, UCI) is a **proposal from the current position**: replay it fact-15-style (SAN legality -> UCI extraction -> `replayLine` re-replay).
   All proposals legal -> pre-evaluate up to 2 chains through the executor (`evaluate(currentFEN, uciLine)`), append the verified eval/PV to the user turn as data, and add each result as an anchor - this is what makes "what if I played <legal move>?" cite the actual engine eval.
   Any proposal illegal -> **short-circuit with a canned reply and no LLM call**: a closed template like "<token> isn't a legal move in the position we're looking at. If you meant a move from another point in the game, jump to that position and ask there." - persisted with source `precheck`.
   Lowercase/sloppy notation extracts nothing (fact 4) and simply falls through to the LLM + tool loop; the verifier still gates the answer.

4. **Chat replies buffer-then-render; they do not stream token-by-token to the screen.**
   This is a deliberate, documented deviation from PLAN.md's "Streaming responses (Ollama supports SSE-style streaming)" bullet, resolved by PLAN.md's own harder rule: "Nothing unverified ever reaches the screen."
   A token stream rendered live cannot be un-rendered when the verifier rejects it; M6 already resolved this the same way for narration.
   The transport still streams internally (that is how tool calls are detected mid-response and how cancellation stays responsive); the UI shows a phase indicator instead: "Coach is thinking..." -> "Coach is checking a line..." (during tool/seed/precheck engine calls) -> "Coach is writing...", then the verified text appears atomically.

### `CoachChatReply` and the fallback ladder for chat

- `public struct CoachChatReply`: `text`, `source` (enum: `coach` / `fallback` / `precheck`), `toolCallCount`, `violationCount`, `duration` - the chat analogue of `CoachNarration` (kept separate; narration's two-case `Source` is public API used by the app and there is no `KeyMoment` fallback text here).
- Verification double-failure -> canned fallback text (closed template): "I couldn't give you a verified answer to that - the lines I checked didn't support what I wanted to say. Try asking about a specific move or line."
- Client/stream errors mid-turn (Ollama died) -> the same fallback path with a connection-flavored template, and `CoachService` triggers a health recheck.
- Coach disabled, Intel default-off, or Ollama unreachable -> the chat tab renders a guidance state (pointer to Coach settings, "Check again") with the input disabled; unlike narration there is no rule-based chat to fall back to, so honesty means saying the coach is offline, not fabricating a degraded mode.
- Batch analysis running -> seed/precheck/tool evaluations return typed errors; turns still run payload-only (belt-and-braces; chat during a batch analysis is legal but rare).

### Persistence

- **v2 migration** `v2_chatMessageSource`: `ALTER TABLE chatMessage ADD COLUMN source TEXT` (nullable).
  Append-only in `Schema.migrator()`; never touch v1.
- **`ChatMessageRecord`** (exact `AnalysisRecord`/`VariationRecord` pattern - `Codable`, `Identifiable`, `FetchableRecord`, `MutablePersistableRecord`, `Sendable`, `didInsert`): `id`, `gameId`, `plyIndex`, `role`, `content`, `createdAt: Date`, `source: String?`.
  `role` is `"user"` or `"assistant"`; `source` is set only on assistant rows: `"coach"` / `"fallback"` / `"precheck"` (the `CoachChatReply.Source` raw values).
  `plyIndex` = the mainline ancestor ply of the position the message was asked at (`currentGraphPly`) - variation positions map to their branch point, since variation rows can be deleted and plys are the only stable coordinates.
- **`GameStore`**: `insertChatMessage(_:)` (insert-as-sent, same crash-safety pattern as variations), `chatMessages(gameId:)` ordered by `id`, `deleteChatMessages(gameId:)` (the Clear-chat affordance).
- On game load, `CoachService` seeds `CoachChat`'s LLM history from the last 12 persisted rows as plain prose turns (context blocks are not persisted and are re-injected with the next question anyway).

### The verifier context per chat turn

Assembled fresh each turn, mirroring `momentVerifierContext`'s shape:

- anchors: the current position's FEN (with its cached or seeded ranked lines), every precheck evaluation result, every anchor accumulated from prior turns this session (in-memory pool), plus whatever this turn's tool loop adds;
- `knownEvalsCentipawns`/`knownMates`: from all of the above lines/results;
- `knownWinProbabilities`: the current key moment's before/after percentages when present (the one-liner in the payload contains them, so the model will echo them);
- `engineExecutor` set, so the at-most-once fresh-verification hook keeps working.

### Engine serialization (fact 3's fix)

`EngineService.coachEvaluate` gets a FIFO chain: keep a `coachEvaluatePreviousTask` field, and each call first awaits the previous call's completion before running `searchOneShot` (all on the existing `@MainActor`; roughly ten lines).
The `isAnalyzing` refusal and the live-analysis stop/resume behavior stay exactly as they are.
Do not add queueing anywhere else; one chokepoint.

### App wiring and UI

- **`CoachService` additions**: `@Published chatMessages: [ChatMessageRecord]`, `@Published chatPhase` (idle / thinking / checkingLine / writing), a lazily created `CoachChat` per loaded game (recreated on `reset()`, model/register changes), `loadChat(gameId:)`, `clearChat(gameId:)`, and `sendChatMessage(text:context:executor:)` which persists the user row, runs the turn, persists the reply row, and publishes both.
  Sends are sequential (input disabled while a turn is in flight); narration generation and chat may overlap freely (fact 3's serialization makes the engine safe; Ollama is safe).
- **Chat panel**: third `RightPaneTab` segment ("Chat") in `GameReplayView`.
  Contents: a position chip showing what the chat is attached to ("Move 12. Nf3", "Start position", or "Variation after 12...Nf3"); a `List`-based message view (M5's AX lesson: `List` rows expose text where bare `ScrollView`/`VStack` did not) with user/assistant styling, a source caption on assistant rows ("Coach" / "Couldn't verify" / "Move check"), and an "at move N" jump `Button` per message (from `plyIndex`); a `TextField` + Send `Button` (real native controls only); the phase indicator while a turn runs; the offline/guidance state; a small Clear button.
- **Starter questions** (PLAN.md M7): when the displayed ply is a key moment, show suggestion chips as real `Button`s built from closed templates over the moment's facts - "Why was <playedSAN> a <classification>?", "What was the idea behind <betterMoveSAN>?" (when the fact exists) - plus a generic "How should <side to move> continue here?" chip whenever the chat is empty.
  Tapping a chip sends it through the normal pipeline as a user message.

### Grounding harness (the M7 gate)

- **Offline (always runs)**: CoachKit unit tests drive `CoachChat` with the scripted mock client + stub executor (same fixtures/patterns as `CoachNarratorTests`): happy path; illegal proposal -> canned reply with **zero client calls** (assert the mock was never invoked); legal proposal -> the pre-evaluated eval present in the outgoing user turn and the reply's cited eval verified against it; violation -> regeneration -> fallback; position change -> fresh context block; history pruning and the 12-message cap; mid-stream client death -> fallback.
- **Live (`coach-grounding`)**: extend the existing executable with a chat section after the narration runs: from the fixture's key moments, run a legal-proposal turn ("What if I played <a real rank-2 line's first move>?"), an illegal-proposal turn (a move verified illegal in that position; assert the reply came from the precheck), and an open question ("How should <side> continue here?"), N configurable; independently re-verify every rendered reply with a fresh context (the same leak check narration gets); also fire two `evaluate` calls concurrently and assert both return sane results (fact 3's FIFO gate); print per-turn source/tool-call/violation stats; exit non-zero on any leak.

## Known gaps and deliberate M7 v1 limitations

- Bare-square proposals ("what about c4?" meaning the pawn move) are not prechecked - fact 4's TRAP 1 makes bare squares unsafe to treat as moves; the LLM answers them with its tool loop and the verifier still gates.
  Document, don't fix, in v1.
- Sloppy notation (lowercase `nf3`) extracts nothing and goes to the LLM; same story.
- History-reference questions ("was 24...Qd7 a blunder?") skip the precheck; the payload's moves-so-far and the current-ply one-liner carry the data.
- M6's carried limitations apply to chat identically: eval claims verify against the known-good pool (misattribution possible, fabrication not), the bare-square exemption, and qualitative prose being out of scope.
- M5/M6 UI gaps unchanged: report-tab key-moment AX label gap (chat's `List`-based panel is also a live experiment for fixing it - if `List` exposes chat rows, consider migrating key moments later), "Starting engine..." never caught live, `-0.0` label quirk, M3/M4 leftovers.

## What to build, in order

Each step ends with a verification gate; do not continue past a failing gate.

### Step 0 - Preflight

1. `scripts/fetch-nnue.sh` (no-op if nets present), `xcodegen generate`, app builds.
2. `swift test` green in Persistence, CoachKit, ChessCore (others if cheap).
3. `curl -s http://127.0.0.1:11434/api/version` answers; `curl -s http://127.0.0.1:11434/api/tags | grep qwen3:0.6b` finds the harness model.

### Step 1 - ChatMessageRecord + v2 migration + GameStore CRUD (Persistence)

- The v2 migration, record type, and three `GameStore` methods per the persistence decisions.
- Tests (Swift Testing, in-memory store, same style as `PersistenceTests.swift`): round-trip in insertion order, `source` nullability on user vs assistant rows, delete-by-game, cascade on game delete.
- **Gate**: `swift test --package-path Packages/Persistence` green.

### Step 2 - Tokenizer exposure + proposal scanner (CoachKit)

- `CoachVerifier.moveTokenChains(in:)` public wrapper (no change to `verify()`), plus the precheck classification (proposal / square reference / history reference) and the fact-15 replay sequence as a small `ProposedLineCheck` helper (pure ChessCore, executor-free - it returns legal UCI lines or the illegal token; the engine call happens in `CoachChat`).
- Tests: every line of fact 4's table verbatim, including the three traps landing in the right buckets; legality outcomes from fact 5's FENs; the multi-move chain; a `CoachVerifierTests` guard that existing verification behavior is untouched.
- **Gate**: `swift test --package-path Packages/CoachKit` green, existing tests untouched.

### Step 3 - Chat payload + prompt (CoachKit)

- `CoachChatContext`/`CoachChatPayload`, `CoachPayloadBuilder.chatPayload`, `CoachPrompt.chatSystemPrompt`/`chatUserMessage(question:payload:includeContext:)`/the precheck-data block, per the payload decisions.
- Tests: golden chat-payload JSON for the fixture's first key-moment position (committed, M5/M6 precedent); a variation-position payload (path SAN present); an unanalyzed-game payload (no lines, no accuracies); context-block inclusion toggling on FEN change.
- **Gate**: CoachKit tests green.

### Step 4 - CoachChat actor (CoachKit)

- The `private` -> `internal` refactor of `runConversation`/`toolResultJSON`/`errorMessage` (nothing else changes in `CoachNarrator`), then `CoachChat` + `CoachChatReply` per decisions 1-3: precheck -> seed -> generate -> verify -> regenerate once -> fallback; anchor pool; pruning; history seeding and cap.
- Tests per the offline-harness list above (mock client + stub executor throughout).
- **Gate**: CoachKit tests green, including every pre-existing `CoachNarratorTests` case unmodified.

### Step 5 - Engine FIFO serialization (App)

- The `coachEvaluate` FIFO chain per the engine decision; no other `EngineService` changes.
- **Gate**: app builds, `xcodebuild test` green; the live concurrent-evaluate probe lands in step 6's harness (two overlapping `evaluate` calls both return sane, distinct results).

### Step 6 - coach-grounding chat section (CoachKit)

- Extend the executable per the live-harness decisions (chat turns + independent re-verification + the concurrent-evaluate probe), keeping the existing narration runs intact.
- **Gate**: `swift run --package-path Packages/CoachKit coach-grounding` exits 0 with qwen3:0.6b; the illegal-proposal turn shows source=precheck with zero LLM requests; stats show the verifier firing (zero violations across all runs with a 0.6b model would be suspicious - investigate if so).

### Step 7 - App wiring and chat UI

- `CoachService` chat state + `GameReplayViewModel`'s moves-so-far/variation-path accessor + the Chat tab per the UI decisions; starter chips; offline states; `xcodegen generate`.
- **Gate**: Release build; with Ollama running and the coach enabled, type a question about a fixture-game position in the real app and a verified reply renders with its source caption; the DB (`sqlite3` on the sandboxed store) shows both rows with correct `role`/`source`/`plyIndex`.

### Step 8 - Acceptance pass (PLAN.md M7 criteria, M5's zero-false-statement discipline)

1. Release build, the analyzed fixture game (`MagnusCarlsen vs artin10862`), coach on qwen3:0.6b (spot-check qwen3:8b if disk allows).
2. "What if I played <legal move>?" at a key moment: the reply cites the actual engine eval of that move (cross-check the injected precheck eval against a manual `evaluate` run); read every rendered sentence and verify it independently (the M5 method) - zero false statements in rendered text.
3. An illegal-move question produces the canned illegal reply, and Ollama's server log/`/api/ps` activity confirms no LLM request was made for it.
4. An open question ("how do I attack here?") produces at least one `evaluate` tool call before the answer (harness stats or stderr debug); if 0.6b will not tool-call on open questions in-app, verify the criterion with qwen3:8b and note it.
5. From a user variation position (play one first): the chat context correctly describes the variation path, and a proposed-move question works there.
6. Quit/relaunch: the full chat history renders from SQLite with source labels intact; "at move N" jump buttons work; Clear chat empties the table.
7. Kill Ollama mid-session (`kill -9`, the M6 lesson): in-flight turn resolves to the connection fallback, input degrades to the offline state, no crash/hang; restart + "Check again" recovers live.
8. AX pass over the new panel (element-reference clicks only): input field, Send, starter chips, jump buttons, Clear all drivable; note whether `List` rows expose their text (the M5 gap experiment).
9. `coach-grounding` exits 0; every package's `swift test` and the full `xcodebuild test` suite green.

### Step 9 - Wrap up

Update `handoffs/HANDOFF.md` (M7 done, decisions, gaps), append to `devlogs/<date>.md`, write `handoffs/NEXT-SESSION-M8.md` (polish and packaging per PLAN.md M8), commit and push code + docs together.

## Working style notes (carried forward; they keep paying off)

- Verify third-party APIs and regexes against real data before trusting them - this prep session's traps (bare-square proposals, history references, the FEN-mangling reproduction) all came from scratch runs, not from reading code.
- Real E2E through the built app via `osascript`/System Events **AX-element** references only; raw pixel clicks and screenshots are blocked in this sandbox.
- Any new interactive UI must be real `Button`s/native controls.
- After adding/removing files under `App/`, rerun `xcodegen generate`.
- Debug on stderr, never stdout (the engine hijacks stdout); Release builds for anything timing-sensitive.
- The sandboxed DB for E2E checks: `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
- Commit and push milestone work together with updated handoffs and a dated devlog entry.
