# Next session: M6 - local LLM coach

This is a self-contained execution plan for a fresh session with no prior context.
It was prepared by a 2026-07-17 planning session that verified every risky claim below against a live `ollama serve` instance (v0.31.2, real curl transcripts pasted in), the real Ollama model registry, and real scratch-package runs against ChessCore - the facts are verified, not guessed.
Follow it step by step; the design decisions are already made, do not re-derive or re-litigate them.
Read `PLAN.md`'s "Verified Coach", "Model Picker", and M6 milestone sections for product context, but where this file is more specific, this file wins (one deliberate deviation from PLAN.md's model table is called out in verified fact 11).

The accept criterion (PLAN.md M6): with Ollama running, key moments get natural coaching prose in which every cited line passes CoachVerifier; the grounding test harness passes; with Ollama stopped, the app silently falls back to rule-based text; Intel/no-Ollama paths show the right guidance.
The M5 discipline carries over unchanged: **nothing unverified ever renders.**

## Where things stand

M1-M5 are done and pushed to `main` at https://github.com/WillisLiao/chessanto.
What M6 builds on:

- **M5's report pipeline is the input.**
  `AnalysisKit` produces `GameReport` with `[KeyMoment]`, each carrying typed Facts (`EvalSwingFact`, `BetterMoveFact`, `PunishmentFact`, `MissedMateFact`, `AllowedMateFact`, plus `OpeningFact` at report level), already gated by `FactAuditor`.
  `GameReplayViewModel.buildReport()` (App) maps `AnalysisRecord`s into `ReportInput` (plies of `PlyRecord` with ranked `RankedLine`s) and holds both.
  The coach payload is a serialization of these same values - one source of truth, no re-derivation.
- **`CoachKit` is an empty placeholder** (`CoachKitPlaceholder` enum), but its `Package.swift` already depends on ChessCore, EngineKit, and AnalysisKit, and the App target already links CoachKit (`project.yml` line 64).
- **The replay primitives CoachVerifier needs already exist in ChessCore**: `ChessGame.replayLine(fromUCI:startingFEN:)` returning `[ReplayedMove]` (san, uci, check/mate flags, captures, resulting FEN), `playMove(san:at:)` returning `MoveIndex?`, `moveDetail(at:)`, `material(fen:)`, `epd(fromFEN:)`.
  Verified facts 15-16 below pin down exactly what each may and may not be trusted for.
- **The M2 engine facts still apply**: white-perspective DB values via `EngineScoreNormalizer`, exactly one `AnalysisEngine` per process owned by `EngineService` (@MainActor), NNUE nets required (`scripts/fetch-nnue.sh`), Debug-build Stockfish 5-10x slower, debug on stderr never stdout.

## Verified facts (each was checked against a live instance, the real registry, or a real scratch run this session)

1. **Ollama detection is an HTTP probe, not a binary check.**
   Ollama.app auto-serves on `127.0.0.1:11434`; `GET /api/version` returned `{"version":"0.31.2"}`.
   The Homebrew CLI on this machine is 0.30.10 while the serving app is 0.31.2 - the `ollama` binary's presence/version says nothing about the server, so health checks must curl the port.
   Connection refused = not running; that is the whole install/running detection story.

2. **`GET /api/tags` lists installed models with a `capabilities` array.**
   Real response shape (trimmed to one model, all fields real):
   ```json
   {"models": [{
     "name": "qwen2.5:0.5b-instruct",
     "model": "qwen2.5:0.5b-instruct",
     "modified_at": "2026-06-19T...+08:00",
     "size": 397821543,
     "digest": "a8b0c515...",
     "details": {"format": "gguf", "family": "qwen2", "parameter_size": "494.03M",
                 "quantization_level": "Q4_K_M", "context_length": 32768, "embedding_length": 896},
     "capabilities": ["completion", "tools"]
   }]}
   ```
   `capabilities` (also via `POST /api/show {"model": ...}`) is how the app checks tool support before enabling the engine-tool loop; observed values: `completion`, `tools`, `thinking`, `vision`, `insert`.
   This machine already had 7 models installed (llava:7b, three qwen2.5-coder sizes, hermes3:3b, two qwen2.5-instruct sizes) - the picker must handle a non-empty pre-existing library gracefully.

3. **`GET /api/ps` reports loaded models and their ACTUAL loaded context.**
   Real response fields: `name`, `size`, `size_vram`, `expires_at` (keep-alive expiry), and `context_length` - the context the model is currently loaded with, not the model's maximum.

4. **Ollama loads models with a 4096 default context regardless of the model's maximum.**
   Observed live: qwen3:0.6b (max 40960 per `/api/show` `model_info`) loaded at `context_length: 4096`.
   Passing `"options": {"num_ctx": 16384}` in the chat request reloaded it at 16384 - and grew its RAM footprint from 1.0 GB to 2.44 GB (`size_vram`), so context size is a real memory cost.
   The coach must set `num_ctx` explicitly (decision: 8192) or long payloads get silently truncated.

5. **`POST /api/pull` streams NDJSON progress, and mid-stream errors arrive inside an HTTP 200 stream.**
   Request: `{"model": "qwen3:0.6b"}`.
   Real success stream (statuses in order):
   ```
   {"status":"pulling manifest"}
   {"status":"pulling 7f4030143c1c","digest":"sha256:7f40...","total":522640096}
   {"status":"pulling 7f4030143c1c","digest":"sha256:7f40...","total":522640096,"completed":16368992}
   ... (repeated per layer with growing "completed") ...
   {"status":"verifying sha256 digest"}
   {"status":"writing manifest"}
   {"status":"success"}
   ```
   The very first real pull this session ended with `{"error":"503: "}` as the final stream line - **HTTP status was still 200**; per-line `error` keys are the only failure signal.
   The retry resumed the partial download (68 stream lines vs 543) and completed.
   The pull client must therefore: parse `error` lines, surface them with a retry action, and rely on Ollama's resume - progress = `completed/total` of the largest layer (the model blob dominates).

6. **Every PLAN.md model tag resolves in the registry, with real download sizes.**
   `https://registry.ollama.ai/v2/library/{model}/manifests/{tag}` with header `Accept: application/vnd.docker.distribution.manifest.v2+json` returns HTTP 200 + a manifest whose layer sizes sum to the download size (404 for unknown tags).
   Verified this session: qwen3:4b = 2.5 GB, qwen3:8b = 5.2 GB, qwen3:32b = 20.2 GB, llama3.2:3b = 2.0 GB, qwen2.5:14b = 9.0 GB, gemma3:27b = 17.4 GB, qwen2.5:32b = 19.9 GB, qwen3:0.6b = 0.5 GB.
   Decision: hardcode these sizes in the picker (labeled "approx."); do not fetch manifests at runtime.

7. **`POST /api/chat` streaming shape (NDJSON, one JSON object per line).**
   Real transcript lines:
   ```
   {"model":"qwen2.5:0.5b-instruct","created_at":"2026-07-17T12:10:52.787604Z","message":{"role":"assistant","content":"Hello"},"done":false}
   {"model":"qwen2.5:0.5b-instruct","created_at":"...","message":{"role":"assistant","content":" Coach"},"done":false}
   {"model":"qwen2.5:0.5b-instruct","created_at":"...","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop",
    "total_duration":331611625,"load_duration":154108625,"prompt_eval_count":33,"prompt_eval_duration":70693000,"eval_count":11,"eval_duration":105509000}
   ```
   Content arrives as deltas; the `done:true` line has empty content plus timing/token stats.

8. **Thinking models (the qwen3 family) emit a separate `message.thinking` field, never `<think>` tags in content.**
   Streamed as `{"message":{"role":"assistant","content":"","thinking":"Okay"},"done":false}` deltas; non-streamed responses carry the full `thinking` string next to clean `content`.
   `"think": false` in the request disables it entirely (verified: no thinking field, direct answer).
   Non-thinking models silently accept a `think` field (verified against qwen2.5: HTTP 200, normal answer), so the client can send it unconditionally.

9. **Tool calling: `arguments` is a JSON object (not an OpenAI-style string), and streamed tool calls arrive whole.**
   Request carries standard `tools: [{"type":"function","function":{"name","description","parameters":<JSON schema>}}]`.
   Real response:
   ```json
   {"message": {"role": "assistant", "content": "",
     "tool_calls": [{"id": "call_lex8r2fo",
       "function": {"index": 0, "name": "evaluate",
         "arguments": {"fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"}}}]},
    "done": false}
   ```
   In streaming mode the complete `tool_calls` array arrives in a single `done:false` chunk (arguments never fragment across chunks), followed by the `done:true` terminator.
   `done_reason` stays `"stop"` even for tool calls - detect them by the presence of `message.tool_calls`, never by `done_reason`.
   The round-trip is: append the assistant message (with its `tool_calls`) plus `{"role": "tool", "tool_name": "evaluate", "content": "<JSON string of the result>"}` and call `/api/chat` again - verified working on 0.31.2.

10. **Small models mangle tool arguments and hallucinate over verified data - observed live, twice.**
    qwen2.5:0.5b concatenated the move list into the FEN argument (`"fen": "rnbq.../ - 0 1.e4 1.e4 e7e5 g1f3"`), and separately narrated a verified `+0.35, best line e5 Nf3 Nc6` tool result as "this position is a stalemate ... the opponent has captured the piece in the center with their queen."
    This is the concrete justification for two hard rules below: validate every tool argument by ChessCore replay before touching the engine, and let CoachVerifier gate every rendered sentence.

11. **gemma3 has no `tools` capability - PLAN.md's 32 GB alternative cannot drive the engine-tool loop.**
    Checked on ollama.com's library pages this session: qwen3 = tools + thinking, llama3.2 = tools, qwen2.5 = tools, **gemma3 = vision only, no tools**.
    Deliberate deviation from PLAN.md's table: the 32 GB+ alternative becomes `qwen2.5:32b` (exists, 19.9 GB, tools - verified fact 6).
    If the user hand-picks a non-tools model anyway (fact 2's `capabilities` check), the coach still works payload-only: no tool loop, verification unchanged.

12. **Error shapes.** Chat against a missing model: HTTP 404, body `{"error":"model 'nonexistent-model:1b' not found"}`, identical for `stream:true` and `stream:false`.
    Mid-stream failures (pull, fact 5) come as NDJSON `error` lines inside an HTTP 200 stream; treat any line with an `error` key as terminal for that request.

13. **`userProfile` needs NO schema work - the M6 columns have existed since the v1 migration.**
    `Schema.swift` line 61-67: `ratingBand` (text, default "adaptive"), `coachModel` (text, nullable), `coachEnabled` (boolean, default false), and `UserProfileRecord` already maps all of them with matching defaults; `GameStore.userProfile()/saveUserProfile()` exist since M4.
    Do not write a migration; just read/write the existing fields.

14. **The app can already reach localhost: no entitlement or ATS work needed.**
    `project.yml` already sets `NSAppTransportSecurity.NSAllowsLocalNetworking: true` and `com.apple.security.network.client: true` (both shipped with M1's setup), and the App target already links CoachKit.
    Still verify live in step 7's gate - config being present is not the same as the request succeeding from the sandboxed app.

15. **SAN replay from an arbitrary mid-game FEN works - but the SAN path must never be trusted for board facts.**
    Real scratch run against ChessCore (from a black-to-move mid-game FEN): `playMove(san:at:)` played `cxd4 exd4 Be7 Nf3`, `moveDetail(at:)` returned correct UCIs/captures/FENs per step, and illegal (`Qxg5`) and nonsense (`Zz9`) tokens were rejected with `nil`, no crash.
    **The trap**: `playMove(san:)` does not derive check state from the board - from a position where Qh5 is checkmate, `"Qh5#"` returned `isCheckmate=true` but bare `"Qh5"` returned `isCheckmate=false`, and spurious suffixes are accepted and echoed uncorrected (`"e4+"` on a quiet move plays as `e4+`; `"Qh5+"` on the mate plays as `Qh5+`, `isCheckmate=false`).
    `replayLine(fromUCI:)` on the same move derived the truth (`san="Qh5#"`, `isCheckmate=true`).
    Therefore the fixed verification pattern is: SAN tokens -> `playMove(san:at:)` for **legality + UCI extraction only** -> re-replay the UCI line via `replayLine(fromUCI:startingFEN:)` -> take every fact (check, mate, capture, resulting FEN, canonical SAN) from the UCI replay only.
    Bonus tolerance verified: chesskit accepts long-algebraic-ish `Ng1f3` and zero-style `0-0` castling - both forms LLMs emit.

16. **The SAN <-> UCI bridge is exact.**
    The UCI line derived via `playMove(san:)`+`moveDetail` (`c5d4 e3d4 f8e7 g1f3`), re-replayed through `replayLine(fromUCI:)`, reproduced the identical SAN sequence - so cited-SAN-line vs stored-UCI-PV prefix comparison happens in UCI space, mechanically.

17. **This machine: Apple M1, 16 GB RAM, 8 cores.**
    `sysctl -n hw.memsize` = 17179869184, `sysctl -n hw.optional.arm64` = 1, `sysctl -n machdep.cpu.brand_string` = "Apple M1" - the picker's detection commands verified.
    Per the table this machine's default is qwen3:8b, but development and the harness use the model below.

18. **`qwen3:0.6b` is now installed locally (~0.5 GB) as the dev/harness model.**
    Pulled live this session; `capabilities: ["completion","tools","thinking"]`, family qwen3, max context 40960.
    It is deliberately in the same family as the picker defaults, tools-capable, cheap enough to run repeatedly in the grounding harness on this 16 GB machine, and bad enough at chess to exercise the verifier's failure paths constantly (fact 10) - which is exactly what a verifier harness wants.

19. **There is no CI system in this repo** (no `.github/workflows`).
    "Fails CI on any leak" (PLAN.md) therefore means: the CoachKit unit test suite (runs offline, always) plus a `coach-grounding` live executable following the established `engine-smoke`/`chesscom-smoke` precedent, run as the milestone gate.

20. **EngineService/AnalysisEngine internals (read in full this session), for the tool executor.**
    `EngineService` (@MainActor) routes engine updates to either a batch collector or live handling; batch searches run via a private `searchPly` (set position -> `go(movetimeMilliseconds:)` -> await terminating bestmove via continuation -> collect ranked infos -> normalize to white-perspective with `EngineScoreNormalizer.whitePerspectiveScore/Mate(_, fen:)`).
    `AnalysisEngine.setPosition` waits out any in-flight search's bestmove before bumping the generation (the M2 stale-tag fix), so sequential one-shot searches are safe by construction.
    Live analysis is stopped before batch and resumed after via `pendingLiveFEN`; the coach executor reuses exactly this pattern.

## Fixed design decisions (use them everywhere)

### Package layout and boundaries

- All coach logic lives in **CoachKit**; it imports ChessCore and AnalysisKit freely, and defines the engine dependency as a protocol so the package never touches the app's engine directly:
  ```swift
  public protocol EngineToolExecutor: Sendable {
      func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult
  }
  ```
  The app implements it on `EngineService`; CoachKit tests use a scripted stub.
  (The manifest's EngineKit dependency stays for the `coach-grounding` executable, which drives a real `AnalysisEngine` the way `engine-smoke` does.)
- CoachKit stays DB-free and UI-free, exactly like AnalysisKit in M5: the app maps `UserProfileRecord`/`ReportInput`/`GameReport` into plain values going in, and receives `CoachNarration` values coming out.
- New CoachKit components: `OllamaClient`, `OllamaModels` (request/response Codable types), `CoachModelCatalog` (the picker table), `CoachPayloadBuilder`, `CoachPrompt`, `CoachVerifier`, `CoachNarrator` (the orchestrator), `EngineToolExecutor`+`EngineToolResult`.
- App side: `CoachService` (@MainActor ObservableObject, owns an `OllamaClient` + narration state per game), `EngineService.coachEvaluate` (the executor), a Coach settings pane, and `GameReportView` narration slots.

### OllamaClient (native API, URLSession, NDJSON)

- Native `/api/*` endpoints only (verified shapes above); never the OpenAI-compat layer - the native API carries `thinking`, `capabilities`, `options`, and `keep_alive`, all of which M6 uses.
- Base URL fixed to `http://127.0.0.1:11434`.
- Streaming via `URLSession.bytes(for:)` + line-buffered NDJSON decode; every line decodes into one `OllamaChatChunk` (message content/thinking/tool_calls + done/done_reason/stats) or an `OllamaErrorLine` (`error` key - fact 12).
- `URLSessionConfiguration.timeoutIntervalForRequest = 300` - first-token latency includes model load, which can exceed 60 s for large models on modest hardware (fact 7's `load_duration` is real data).
- Chat requests always send: `"think": false` (fact 8; narration is templated-payload explanation, not open-ended reasoning - latency wins), `"options": {"num_ctx": 8192, "temperature": 0.2}` (fact 4 makes num_ctx mandatory; low temperature keeps narration close to the payload), `"stream": true`.
- Tool-call detection by presence of `message.tool_calls` (fact 9), accumulating `content` deltas otherwise.
- Pull: stream `OllamaPullEvent` lines (`status`/`digest`/`total`/`completed` or `error`), progress from the largest layer, retry surfaces Ollama's resume (fact 5).
- Health: `version()` probe (fact 1), `installedModels()` = `/api/tags` (fact 2), `capabilities(of:)` = `/api/show`.

### The model picker (revised table - fact 11's gemma3 deviation)

| RAM (Apple Silicon) | Default | Alternative |
|---|---|---|
| 8 GB | `qwen3:4b` (2.5 GB) | `llama3.2:3b` (2.0 GB) |
| 16 GB | `qwen3:8b` (5.2 GB) | `qwen2.5:14b` (9.0 GB, warn: tight if other apps are open) |
| 32 GB+ | `qwen3:32b` (20.2 GB) | `qwen2.5:32b` (19.9 GB) |

- Sizes hardcoded from fact 6, labeled approximate.
- RAM/chip detection per fact 17's verified `sysctl` calls; Intel (`hw.optional.arm64` != 1): coach defaults off with the slow-inference warning, still enableable (PLAN.md).
- The picker lists installed models too (fact 2), marking tool support from `capabilities`; picking a non-tools model shows a "coach will not calculate live lines" note and disables the tool loop only (fact 11).
- Free-text model entry stays allowed (any installed tag can be chosen); `coachModel` persists in `userProfile` (fact 13).

### The coach payload (Layer 1)

- `CoachPayloadBuilder` maps one `KeyMoment` + its `ReportInput` context into a compact Codable payload; the whole-game summary gets a variant with accuracies, classification counts, opening fact, and the per-moment one-liners.
- Per-moment payload fields (all copied or replay-derived, nothing new computed): move number label + mover + played SAN/UCI, classification, winP before/after (mover perspective), pre/post FEN, the pre-move position's ranked lines (rank, white-perspective cp/mate, `EvalLabel` string, PV as both UCI and SAN via `replayLine`, depth), and each attached Fact rendered as typed JSON (reuse the Fact structs; add `Codable` conformance in AnalysisKit - purely additive).
- Rating register from `userProfile.ratingBand`: `beginner` / `intermediate` / `advanced` map to three prompt registers; `adaptive` resolves per game from the user's rating in that game (`GameRecord.whiteRating/blackRating` matched via `chessComUsername`), bands: <1200 beginner, 1200-1800 intermediate, >1800 advanced, unknown -> intermediate.
- The prompt states the two rules the verifier will enforce mechanically: cite moves/lines only from the payload or from `evaluate` tool results, and attach an eval in parentheses (payload's `EvalLabel` format) immediately after any cited line.
  Layer 1 remains a quality aid; the gate is Layer 2.

### CoachVerifier (Layer 2 - the hard gate)

Verification context per response: the moment's pre-move FEN and post-move FEN (anchor positions), the payload's ranked lines, and every `EngineToolResult` returned during this response's tool loop (each result adds its own resulting FEN as an anchor).

Pipeline, in order:

1. **Token extraction** (regex pass over the final prose):
   - SAN candidates: `\b(?:O-O-O|O-O|0-0-0|0-0|[KQRBN][a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?|[a-h]x[a-h][1-8](?:=[QRBN])?|[a-h][1-8](?:=[QRBN])?)[+#]?\b`.
   - UCI candidates: `\b[a-h][1-8][a-h][1-8][qrbn]?\b`.
   - Move-number markers (`12.`, `12...`) chain adjacent tokens into cited lines; unnumbered adjacent tokens separated only by spaces/commas also chain.
   - **Bare-square disambiguation**: a lone `[a-h][1-8]` token with no capture/piece/suffix/promotion and no number marker is a *square reference* ("the knight on c6"), not a move claim - it is exempt from move verification in M6 v1.
     Every other token form is unambiguous and always verified.
     (Piece-on-square claims are a harness-growth item, per PLAN.md's residual-risk note.)
2. **Line verification** per cited line, tried from each anchor FEN until one passes:
   - Strip `+`/`#`/`!`/`?` decorations, replay tokens sequentially with `playMove(san:at:)` (UCI tokens via `replayLine` directly) - any rejection = illegal-move violation (fact 15's legality guarantee).
   - Derive the UCI line, re-replay via `replayLine(fromUCI:startingFEN:)`, and take all board facts from that replay only (fact 15's trap).
   - The UCI line must be a prefix of a payload ranked line's PV, a prefix of a tool-call result's PV, or - at most once per response - verified fresh through the `EngineToolExecutor`; otherwise it is an unverified-line violation.
   - If the prose claims check/mate for a cited move (suffix or words like "mate"), the claim must match the UCI replay's `isCheck`/`isCheckmate` - fact 15 makes suffix-trusting a real hallucination vector.
3. **Eval claims**:
   - Numeric tokens (`[+-]?\d+\.\d+` and `M\d+` / "mate in N") in parentheses/brackets after a verified line: must match that line's source eval within ±0.5 pawns (mate counts exact).
   - Unattached numeric evals: must match the payload's pre- or post-move eval (or a tool result's eval) within ±0.5 pawns; otherwise violation.
   - Percentage tokens: must match a payload winP within ±2 points.
   - "mate in N" phrasing must match a `MissedMateFact`/`AllowedMateFact` `mateInN` or a source line's mate count exactly.
4. **Verdict**: `verified(text)` or `violations([CoachViolation])`, where each violation carries a machine-readable description ("cited line 15.Bxc6 Qd7 does not appear in the engine data for this position").

Policy (PLAN.md, fixed): on violations, regenerate **once** with the violation descriptions appended as an extra user turn; on second failure, fall back to `ReportText`'s rule-based lines for that moment.
Nothing unverified ever renders - including mid-stream: tokens accumulate in a buffer behind a "Coach is writing..." state and the UI only ever shows verified full text (this is also why `think:false` and streaming progress states coexist fine).

### The engine-tool loop (Layer 3)

- One tool, exactly PLAN.md's: `evaluate(fen, moves)` - JSON schema: `fen` (string, required), `moves` (array of UCI strings, optional).
- `EngineService.coachEvaluate(fen:movesUCI:)` (the `EngineToolExecutor` impl):
  1. Validate `fen` parses (`Position(fen:)` via a ChessCore check) and replay `movesUCI` with `replayLine`; a short/failed replay returns a **typed error result** to the LLM (`{"error": "illegal move ... in position ..."}`) - fact 10 shows arguments will be garbage sometimes; the engine must never see garbage.
  2. Search the replay's resulting FEN (not `position fen ... moves ...` - the resulting FEN is needed anyway for `EngineScoreNormalizer`'s white-perspective conversion, fact 20).
  3. Reuse the batch one-shot machinery: stop live analysis, `setPosition` + `go(movetimeMilliseconds: 500)`, await bestmove, collect MultiPV ranks, normalize, resume pending live - extract the shared core from `searchPly` rather than duplicating it.
  4. Refuse (throw) while a batch analysis is running; narration generation is anyway only triggered on fully-analyzed games, so this is a belt-and-braces guard.
- `EngineToolResult`: resulting FEN, white-perspective cp/mate, `EvalLabel` string, PV as UCI + SAN (via `replayLine`), depth - the same vocabulary as `RankedLine`, and it feeds both the tool response JSON and the verifier's anchor set.
- Cap: 6 tool calls per response (PLAN.md); the 7th `tool_calls` chunk gets a tool-result of `{"error": "tool call limit reached, answer with what you have"}` and no engine run.

### Narration flow and fallback ladder

- `CoachService` generates narration sequentially (one moment at a time - one engine, one LLM, bounded memory): each key moment, then the game summary.
  Trigger: report built + `coachEnabled` + health probe OK; regenerate on re-analyze (report invalidation already exists in the VM).
- M6 keeps narration **in-memory per game** (no DB persistence; regeneration is cheap next to analysis, and M7's chat persistence will revisit storage).
- Fallback ladder, each level silent and additive (PLAN.md's "app remains fully usable"):
  1. Intel Mac -> coach defaults off, warning shown when enabling.
  2. Ollama not reachable -> guidance UI in settings (install instructions + "Check again"); report shows rule-based text.
  3. Reachable but `coachModel` missing from `/api/tags` -> picker prompts to pull (with fact 5's progress/retry).
  4. Model without `tools` -> payload-only narration, verification unchanged.
  5. CoachVerifier double-failure on a moment -> rule-based text for that moment (the rest keep their narration).
- The Report tab labels each moment's text source subtly ("Coach" vs rule-based) so fallback is honest but not alarming.

### Grounding harness (the M6 accept-criterion gate)

- **Offline (always runs)**: CoachKit unit tests with recorded/crafted LLM outputs against the committed real fixture (`Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/real-fixture-game-report-input.json` - copy it into CoachKit's test resources): planted violations (invented line, wrong eval, wrong mate count, suffix-only mate claim, illegal move, mangled tool args) must each be caught; known-good texts must pass; the regenerate-then-fallback state machine is driven by a scripted mock client.
- **Live (`coach-grounding` executable, `engine-smoke` precedent)**: real Ollama (qwen3:0.6b - fact 18) + real `AnalysisEngine`, run the full narrate->verify loop N times (default 10) over the fixture's key moments; exit non-zero if any rendered output fails an independent re-verification, and print violation/fallback/tool-call counts (fallbacks are *expected* with a 0.6b model - the invariant is zero unverified renders, not zero violations).

## Known gaps carried in from M5 (fix opportunistically, not blocking)

1. Report-tab key-moment buttons expose no AX label (everything tried is in the M5 devlog).
   M6 adds narration UI to these same rows - if a fix is found while in there (e.g. moving key moments into a `List`), take it; otherwise keep verifying via DB + visible-text checks.
2. "Starting engine..." toolbar state never caught live (engine starts too fast in Release) - unchanged, low priority.
3. `-0.0` eval-label cosmetic quirk - unchanged.
4. M3's variation-control gaps and M4's `invalidMove("Rb5")` parse failure + fetch pagination - unchanged.

## What to build, in order

Each step ends with a verification gate; do not continue past a failing gate.

### Step 0 - Preflight

1. `scripts/fetch-nnue.sh` (no-op if nets present), `xcodegen generate`, app builds.
2. `swift test` green in ChessCore, AnalysisKit, Persistence (others if cheap).
3. `curl -s http://127.0.0.1:11434/api/version` answers (start Ollama.app if not); `curl -s http://127.0.0.1:11434/api/tags | grep qwen3:0.6b` finds the harness model (re-pull per fact 5 if the user removed it).

### Step 1 - OllamaClient + types (CoachKit)

- `OllamaModels.swift` (Codable request/response types for chat/tags/ps/show/pull/version, mirroring the real JSON in facts 2-9 exactly), `OllamaClient.swift` (URLSession + NDJSON streaming per the client decisions).
- Unit tests with a `URLProtocol` stub replaying the real captured transcript lines from this file as fixtures: streaming content assembly, thinking-delta separation, whole-chunk tool-call decode, pull progress + mid-stream `error` line, 404 model-missing error mapping.
- **Gate**: `swift test` green in CoachKit; a 5-line scratch `swift run` (or test with `LIVE=1`) against the real server round-trips a `qwen3:0.6b` chat with `think:false` and gets a non-empty verified-shape response.

### Step 2 - CoachVerifier (CoachKit)

- Token extraction + line/eval verification + verdicts, exactly per the fixed decisions; pure ChessCore, no engine, no network (the one fresh-verification hook takes an `EngineToolExecutor?` and is stubbed in tests).
- Tests are the heart (use the fixture's real FENs/PVs): every planted-violation class from the harness decisions; the fact-15 suffix traps (bare `Qh5` mate claim missed, spurious `e4+`, wrong `Qh5+` on a mate) each verified through the UCI-re-replay path; bare-square exemption ("the knight on c6" passes without move verification, `15.Bxc6` never escapes it); `Ng1f3`/`0-0` tolerance; UCI-space prefix matching against real stored PVs (fact 16); eval tolerances at their boundaries.
- **Gate**: CoachKit tests green, including a test that runs the verifier over M5's golden rule-based report text (`real-fixture-game-golden-report.txt`) - the rule-based text must pass its own verifier with zero violations (if it does not, the extraction rules are wrong, not the report).

### Step 3 - CoachPayloadBuilder + CoachPrompt (CoachKit + tiny AnalysisKit addition)

- Add `Codable` to the Fact structs and `KeyMoment` in AnalysisKit (additive; existing tests untouched).
- `CoachPayloadBuilder` + the three prompt registers + the two prompt rules per the payload decisions; summary-payload variant.
- Tests: golden payload JSON for the fixture's first key moment (committed, like M5's golden report); register selection incl. the `adaptive` rating mapping; payload token-size sanity (< ~2000 words serialized).
- **Gate**: CoachKit + AnalysisKit tests green.

### Step 4 - Engine tool executor (App + CoachKit protocol)

- `EngineToolExecutor`/`EngineToolResult` in CoachKit; extract the one-shot search core from `EngineService.searchPly`; implement `coachEvaluate` per the tool-loop decisions (replay-validate first, typed error results, refuse during batch, live-analysis stop/resume).
- **Gate**: extend `engine-smoke` (or a new probe mode of `coach-grounding`) to run two real `evaluate` calls - one legal (start position, `e2e4`) checking sign conventions against M2's known values, one deliberately illegal (`e2e5` from the start) checking the typed error path - plus app build + existing tests green (the M2 eval-sanity values are in `NEXT-SESSION-M2.md`).

### Step 5 - CoachNarrator (CoachKit)

- The orchestrator: build payload -> chat stream with tools -> execute tool calls through the executor (cap 6) -> verify -> regenerate-once -> fallback verdict; returns `CoachNarration` (per-moment: verified text or `.fallback`, plus stats: tool calls, violations, duration).
- Tests with a scripted mock `OllamaClient` + stub executor: happy path; tool-call loop incl. cap enforcement and illegal-argument tool errors; violation -> regeneration with the violation text present in the second request; double failure -> `.fallback`; mid-stream Ollama death -> `.fallback` (never an exception to the UI).
- **Gate**: CoachKit tests green.

### Step 6 - coach-grounding executable (CoachKit)

- Per the harness decisions: real Ollama + real engine + committed fixture; N narrations; independent re-verification of every rendered text; non-zero exit on any leak; stats printed to stderr.
- **Gate**: `swift run coach-grounding` exits 0 on this machine with qwen3:0.6b; the printed stats show the verifier actually firing (with a 0.6b model, violation and fallback counts of zero would be suspicious - investigate if so).

### Step 7 - App wiring and UI

- `CoachService` (@MainActor): health monitoring, narration state per game, sequential generation per the flow decisions; wire into `GameReplayViewModel`'s existing report lifecycle (`buildReport()` already exists - narration keys off it).
- Coach settings pane (SwiftUI `Settings` scene): enable toggle, model picker per the table (installed models + pull-with-progress + retry, capability badges), teaching level, the Intel/no-Ollama/no-model guidance states - every control a real native control (M3 AX lesson).
- `GameReportView`: per-moment narration slot ("Coach is writing..." progress -> verified text, or the existing rule-based lines), source label, summary section; keep M5's rule-based path byte-identical when the coach is off.
- `xcodegen generate`; app + package tests green.
- **Gate (live sandbox check, fact 14)**: Release build; with Ollama running and coach enabled, a real narration appears for a fixture-game key moment - proving localhost HTTP works from the sandboxed app.

### Step 8 - Acceptance pass (PLAN.md M6 criterion, M5's zero-false-statement discipline)

1. Release build, real fixture game (`MagnusCarlsen vs artin10862`, already analyzed): enable coach (qwen3:0.6b for speed, then spot-check `qwen3:8b` - this machine's default - if disk allows), generate narration for all key moments + summary.
2. **Read every narrated sentence and verify it independently** (the M5 method: `sqlite3` rows, replay primitives, hand-computed winP) - zero false statements in *rendered* text; fallbacks are acceptable, unverified renders are not.
3. Kill Ollama mid-session (`osascript -e 'quit app "Ollama"'` or kill the process): the app silently shows rule-based text, no errors, no hang; restart Ollama, "Check again" recovers.
4. Settings states via the AX method: Intel warning (code-inspect only - no Intel machine here), no-Ollama guidance, model-missing pull flow with progress, non-tools model note (a qwen2.5-coder tag is installed - fact 2 - but has tools; `llava:7b` is the local no-tools specimen).
5. `coach-grounding` exits 0; all package + app tests green.

### Step 9 - Wrap up

Update `handoffs/HANDOFF.md` (M6 done, decisions, gaps), append to `devlogs/<date>.md`, write `handoffs/NEXT-SESSION-M7.md` (position chat: reuses the full stack - `CoachNarrator`'s loop becomes the chat turn loop, `chatMessage` table already exists in the v1 schema, streaming/persistence/legality-precheck per PLAN.md), commit and push code + docs together.

## Working style notes (carried forward; they keep paying off)

- Verify third-party APIs against a live instance before coding against them; this session caught the 4096-default-context trap, the mid-stream pull errors, the gemma3 no-tools gap, and the SAN-suffix trust trap that way.
- Real E2E through the built app via `osascript`/System Events **AX-element** references only; raw pixel clicks and screenshots are blocked in this sandbox.
- Any new interactive UI must be real `Button`s/native controls.
- After adding/removing files under `App/`, rerun `xcodegen generate`.
- Debug on stderr, never stdout (the engine hijacks stdout); Release builds for anything timing-sensitive.
- The sandboxed DB for E2E checks: `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
- Commit and push milestone work together with updated handoffs and a dated devlog entry.
