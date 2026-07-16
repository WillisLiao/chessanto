# Chessanto - Build Plan

A local-first macOS chess coach.
It imports your chess.com games (or any PGN), analyzes them with Stockfish on-device, and teaches you through rating-adaptive explanations and an interactive position chat powered by a local LLM.
It is also a full chess.com-style analysis board: scrub anywhere in the game with a live eval bar, and play out your own variations with the engine evaluating in real time.
No account, no cloud, no internet required for analysis.
The bar: the best modern local chess analyzer and teacher, not a toy.

This plan is written for Claude Sonnet to execute milestone by milestone.
Each milestone has acceptance criteria; do not move on until they pass.

## Product decisions (already made - do not re-litigate)

- **Platform:** Native macOS app, SwiftUI, macOS 14+. Apple Silicon is the primary target.
- **Engine:** Stockfish, bundled inside the .app, spoken to over UCI via subprocess pipes.
- **Teacher:** Hybrid, with hard verification. Deterministic rule-based analysis produces structured facts; a local LLM (via Ollama) turns those facts into coaching prose and powers chat. The LLM can call the engine as a tool to explore lines, and every chess claim in its output is programmatically verified before display (see Verified Coach below). Enforcement lives in code, not in prompts.
- **Exploration:** Full analysis-board experience. Scrubbing anywhere updates the eval bar live; the user can play any legal move at any point to branch into variations, with continuous engine analysis of the displayed position (see Exploration Mode below).
- **Game import:** Both chess.com public API fetch (online convenience, no login needed) and offline PGN import (file, paste, drag-drop). Analysis always runs 100% locally.
- **Teaching depth:** Adaptive. User sets a rating band (or it is inferred from their chess.com profile) and explanations adjust in vocabulary and depth.
- **LLM sizing:** User picks a model based on their RAM at onboarding (see Model Picker below). On Intel Macs, warn about slow inference and default to rule-based explanations with LLM off.
- **Position chat:** Included. Users can ask "why was this bad?" or "what if I played Nf3?" about any position; user-proposed moves are verified by Stockfish before the LLM answers.

## Architecture

```
Chessanto.app
├── App target (SwiftUI)          UI, navigation, onboarding, settings
└── Local Swift packages
    ├── ChessCore                 rules, PGN/FEN, move legality (wraps chesskit-swift)
    ├── EngineKit                 UCI process management, Stockfish analysis queue
    ├── AnalysisKit               move classification, accuracy, theme detection, key moments
    ├── CoachKit                  Ollama client, prompt building, chat orchestration
    ├── ChessComKit               chess.com public API client
    └── Persistence               GRDB (SQLite): games, analyses, chat history, user profile
```

Key third-party pieces (verified real, current packages as of this writing):

- [`chesskit-app/chesskit-swift`](https://github.com/chesskit-app/chesskit-swift) (MIT, SPM) for board representation, bitboard-based legal move generation, `MoveTree` variation branching, and PGN/FEN/SAN parsing. Wrap it behind ChessCore so it can be swapped later.
- [`chesskit-app/chesskit-engine`](https://github.com/chesskit-app/chesskit-engine) (MIT wrapper; vendors Stockfish 17, which is GPLv3) for the engine. It compiles Stockfish's C++ source in-process as part of the SPM build and exposes an async/await Swift API (`Engine(type: .stockfish)`, `engine.responseStream`, `.send(command:)`) - no subprocess, no pipes, no manual process lifecycle to manage. EngineKit becomes a thin wrapper around this: request queuing, MultiPV/generation-counter bookkeeping, and the infinite-analysis session for Exploration Mode.
  - Stockfish 17 ships with an embedded default network, so NNUE files are an optional strength upgrade, not a requirement - `EvalFile`/`EvalFileSmall` setoption calls only matter if `nn-1111cefa1111.nnue` (~40MB) / `nn-37f18f62d772.nnue` (~7MB) are bundled in `Contents/Resources/`. Defer bundling these to later polish; M1-M2 work with the embedded net.
  - **License note:** because Stockfish is GPLv3, distributing Chessanto publicly (outside personal/local use) requires the app to comply with GPLv3 (typically: ship under a GPL-compatible license, or isolate Stockfish as a separate GPL-licensed component with source offered). Not a blocker for building and running locally; flag before any public release.
- GRDB for SQLite persistence.
- Ollama is an external dependency the app talks to at `http://127.0.0.1:11434`. The app detects it, guides installation if missing, and pulls models through its API. (Embedding llama.cpp directly is a possible v2; do not do it in v1.)

### Analysis pipeline (the core of the product)

1. **Parse** the PGN into a position list (FEN per ply, plus clocks if present).
2. **Evaluate** every position with Stockfish, MultiPV 3, at a user-selectable quality level (Fast ~0.1s/move, Standard ~0.5s/move, Deep ~2s/move). Run evaluation as a background queue with progress UI; cache results in SQLite keyed by (FEN, depth) so re-analysis is instant.
3. **Convert** centipawn evals to win probability using the Lichess model: `winP = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)`.
4. **Classify** each played move by win-probability drop from the user's perspective: Best (played the top engine move), Excellent/Good (small or no drop), Inaccuracy (>= 10), Mistake (>= 20), Blunder (>= 30). Add special classes: Missed Win (had a mate or completely winning line and dropped it) and Brilliant (sound sacrifice that is also the only good move) - keep Brilliant conservative.
5. **Compute** per-player accuracy with the Lichess formula: per-move accuracy `= 103.1668 * exp(-0.04354 * winPDrop) - 3.1669`, aggregated over the game.
6. **Detect themes** deterministically from engine lines and board state: hanging piece, missed fork/pin/skewer, back-rank weakness, missed mate-in-N, losing an exchange, bad trade, time-trouble blunder (if clocks present), opening deviation (see opening book below). Each detection emits a structured `Fact` (type, square/pieces involved, refuting line from the engine PV).
7. **Select key moments:** the 3-8 positions with the largest win-probability swings, plus any Missed Win. These get full coaching treatment; other moves get one-line labels.
8. **Narrate:** for each key moment, send the LLM a structured JSON payload (position, move played, best move, engine lines, detected facts, user rating band) and have it write the lesson. Also generate a whole-game summary with 2-3 takeaways ("recurring pattern: you left pieces undefended on the queenside twice").

### Verified Coach (critical, applies everywhere the LLM speaks)

LLMs hallucinate chess: they invent lines, misjudge positions, and confidently misstate evals.
This is the top product risk, and it is solved architecturally with three layers of enforcement in code, not by prompt instructions alone.

**Layer 1 - Structured input.**
The LLM receives a JSON payload of engine-verified facts: the position, moves, MultiPV lines with evals, and detected themes.
Prompts state that concrete lines must come from this data, but this layer is a quality aid, not the safety mechanism.

**Layer 2 - Programmatic output verification (the hard gate).**
A `CoachVerifier` component in CoachKit parses every generated response before display:
- Extract every SAN/UCI move token and move sequence from the text (regex pass, then parse with ChessCore against the position under discussion).
- Every move must be legal in its claimed position, and every line must either appear in the engine payload or be sent to Stockfish for on-the-spot verification.
- Every eval claim ("this wins a piece", "+2.1", "this is losing") is cross-checked against the verified eval of the line it refers to, within tolerance bands.
- On violation: regenerate once with the specific error fed back ("the line 15.Bxc6 you cited does not exist in this position; use only verified lines").
- On second violation: fall back to the rule-based explanation for that moment.
Nothing unverified ever reaches the screen.

**Layer 3 - Engine as a tool (the LLM becomes an analyst, not just a narrator).**
In both narration and chat, the LLM runs in a tool loop: it can emit an `evaluate(fen, moves)` call, the orchestrator runs Stockfish and returns the eval and PV, and only then does the LLM continue writing.
This lets the coach actively explore ideas ("what happens if Black tries to defend with ...Ne7? let me check... it fails to the fork on d5") instead of being limited to a pre-built payload, while remaining physically unable to assert an unverified claim - anything it wants to say about a line, it must first look up.
Cap tool calls per response (e.g. 6) and stream a "coach is calculating..." state to the UI during calls.

An automated grounding test harness (see Testing) runs the verifier over batches of generated output and fails CI on any leak, so prompt changes cannot silently reintroduce hallucination.

### Exploration Mode (chess.com-style analysis board)

The report tells you what happened; exploration lets you find out why.
This is a first-class feature, not a bonus.

- **Live scrubbing:** click any move, use arrow keys, or drag along the eval graph, and the board, eval bar, and engine lines update instantly. Cached analysis renders with zero latency; a continuous "infinite analysis" engine session then refines the displayed position in real time (eval bar animates as depth increases, like chess.com/Lichess).
- **Free variation play:** at any position, the user can move any piece (legal moves only, with drag-and-drop and click-to-move). This branches off the game into a variation, which the engine immediately starts analyzing live. Variations nest (variations within variations).
- **Variation tree:** the move list becomes a tree - mainline plus indented, collapsible variation branches, rendered in standard notation style. Controls: promote variation, delete variation, "back to game" (jump to where you left the mainline). Variations persist with the game in SQLite.
- **Engine lines panel:** top 3 MultiPV lines for the displayed position, updating live, each line clickable to preview it on the board and playable to adopt it as a variation.
- **Coach everywhere:** any explored position - including deep inside user variations - can be sent to the chat ("explain this position") or given an on-demand coach annotation. The coach payload includes how the user got there, so answers have context ("in your variation where you tried the bishop sacrifice...").
- **Engine session management:** exactly one infinite-analysis session follows the displayed position; scrubbing quickly must debounce cleanly (stop, new position, go) without pipe deadlocks or eval flicker from stale results (tag results with a position generation counter and drop mismatches).

### Opening book (offline)

Bundle a compact opening database (ECO codes + names + main lines, e.g. derived from the public-domain eco.json datasets).
Use it to name the opening, mark where the player left known theory, and let the coach comment on the deviation.
Keep it small (a few MB); this is not a repertoire trainer.

### Model Picker (onboarding + settings)

Detect chip (arm64 vs x86_64) and physical RAM via `sysctl`.
Offer:

| RAM (Apple Silicon) | Default model | Alternative |
|---|---|---|
| 8 GB | `qwen3:4b` | `llama3.2:3b` |
| 16 GB | `qwen3:8b` | `qwen2.5:14b` (warn: tight if other apps are open) |
| 32 GB+ | `qwen3:32b` | `gemma3:27b` |

- Show approximate download size and RAM footprint for each option; let the user override the default freely.
- Intel Mac: show a clear warning that LLM inference will be slow, default the coach to rule-based-only mode, but still allow enabling the LLM.
- If Ollama is not installed: show install instructions (`brew install ollama` or the Ollama.app download) and a "check again" button. The app must remain fully usable in rule-based mode without Ollama.

### Position chat

- Chat panel attached to the currently viewed position (mainline or user variation), with game context (moves so far, evals, prior coaching) in the prompt.
- When the user proposes a move or line ("what about Nf3?"), the app first validates legality via ChessCore, then evaluates the resulting position with Stockfish, and injects the verified eval and PV into the LLM prompt before it answers.
- The chat runs the full Verified Coach stack: engine-tool loop for exploration, CoachVerifier gate on every response.
- Streaming responses (Ollama supports SSE-style streaming).
- Persist chat history per game in SQLite.

### chess.com integration

- Public API, no auth. Set a descriptive `User-Agent` header (chess.com asks for this).
- `GET https://api.chess.com/pub/player/{username}/games/archives` returns monthly archive URLs; each archive returns games with full PGN.
- Flow: user enters username once; app lists recent games (result, opponent, time control, date); user picks games to import. Also a "fetch new games" refresh button. No background auto-sync in v1.
- Optionally read the user's rating from their profile to seed the adaptive teaching level.
- All network failures degrade gracefully to the PGN import path.

## Milestones

Work in this order. Keep the app runnable at the end of every milestone.

### M1 - Skeleton, board, and game replay
- Xcode project + local SPM packages laid out as above; GRDB wired up with migrations.
- Custom SwiftUI board view: piece rendering (bundle an open-licensed SVG/PDF piece set, e.g. from Lichess's lila repo), coordinates, last-move highlight, board flip, resizable.
- PGN import via file open, drag-drop onto the window, and paste. Imported games persist and appear in a sidebar game list.
- Game replay: move list with keyboard navigation (arrow keys), click any move to jump.
- **Accept:** import a real chess.com PGN (headers, clocks, comments) and step through the full game with no parse errors; relaunch and the game is still there.

### M2 - Engine integration and move classification
- EngineKit: launch bundled Stockfish, UCI handshake, configure threads/hash sensibly for the machine, MultiPV parsing, clean shutdown, crash recovery (relaunch and resume queue).
- Background analysis queue with progress reporting and cancellation; results cached in SQLite.
- Eval bar next to the board; eval graph across the whole game (click to jump to a move).
- Live infinite analysis of the displayed position: eval bar and top engine lines refine in real time while scrubbing, with the debounced single-session design from Exploration Mode.
- Move classification and accuracy per the pipeline above; classification badges on the move list and board.
- **Accept:** analyze a ~40-move game on Standard quality in under ~30s on an M-series Mac; classifications broadly match what chess.com/Lichess report for the same game (spot-check 3 real games); re-opening an analyzed game shows results instantly from cache; scrubbing rapidly through the game never shows a stale eval for the wrong position.

### M3 - Exploration Mode
- Free variation play on the board, variation tree move list (promote/delete/collapse, "back to game"), variations persisted.
- Engine lines panel with clickable, adoptable MultiPV lines.
- **Accept:** from any game position, play a 5-move variation with a sub-variation inside it, watch the eval bar track every explored position live, delete the sub-variation, quit and relaunch, and the remaining variation is intact.

### M4 - chess.com fetch
- ChessComKit with the archive flow above; username stored in settings.
- Game browser UI for fetched games with multi-select import.
- **Accept:** enter a real username, fetch, import 5 games, analyze one; airplane-mode launch still works fully for PGN import and analysis.

### M5 - Rule-based coaching report
- Theme detection and key-moment selection.
- Game report view: accuracy summary, classification counts, opening name and deviation point, key moments list with rule-based explanation text ("14...Qd7 hangs the knight on c6; after 15.Bxc6 you lose a piece. Better was 14...Ne7, defending.") built from templates over the structured Facts.
- Whole-game takeaways section (rule-based aggregation of recurring themes).
- **Accept:** the report for a spot-checked game reads correctly with zero false statements; every claim traces to an engine line or board fact.

### M6 - Local LLM coach
- CoachKit: Ollama detection, model picker onboarding (table above), model pull with progress, health checks.
- The full Verified Coach stack: structured payloads, CoachVerifier output gate with regenerate-then-fallback, engine-tool loop with per-response call cap.
- LLM narration for key moments and game summary, rating-adaptive (three prompt registers: beginner, intermediate, advanced).
- Settings: teaching level, model choice, coach on/off (off = M5 rule-based text).
- **Accept:** with Ollama running, key moments get natural coaching prose in which every cited line passes CoachVerifier; the grounding test harness passes in CI; with Ollama stopped, the app silently falls back to rule-based text; Intel/no-Ollama paths show the right guidance.

### M7 - Position chat
- Chat panel per the design above: legality check, engine-tool loop, CoachVerifier gate, streaming, persistence, works from any explored variation position.
- Suggested starter questions per key moment ("Why was this a blunder?", "What was the idea behind the best move?").
- **Accept:** ask "what if I played <legal move>?" and the answer cites the actual engine eval of that move; ask about an illegal move and the app says it is illegal rather than sending it to the LLM; ask an open question ("how do I attack here?") and watch the coach make at least one engine tool call before answering.

### M8 - Polish and packaging
- Onboarding flow: welcome, chess.com username (optional), rating band, hardware detection + model picker.
- Settings window; analysis quality selector; light/dark board themes.
- Empty states, error states, and progress states everywhere; App sandbox enabled with only the entitlements actually needed (network client, user-selected file read).
- Player improvement dashboard (v1-simple): accuracy trend over imported games, most frequent mistake themes.
- Release build script; Developer ID signing + notarization steps documented in README (can be run by the user if they have a developer account; unsigned local builds must also work).
- **Accept:** a fresh user can go from first launch to a coached game report in under 5 minutes with no docs; full E2E pass of the flows in `handoffs/HANDOFF.md`.

## Testing strategy

- Unit tests: win-probability and accuracy math, move classification thresholds, PGN edge cases (annotations, variations, clock tags), UCI response parsing, theme detectors (feed crafted FENs with known tactics), chess.com API response decoding (fixture JSON).
- Integration test: analyze a bundled fixture game end-to-end against a golden classification file; runs in CI without Ollama.
- CoachVerifier unit tests: crafted LLM outputs with illegal moves, invented lines, and wrong eval claims must all be caught; clean outputs must pass untouched.
- LLM grounding test harness: runs N real narrations and chat turns against fixture payloads through CoachVerifier and fails CI on any unverified claim reaching output (catches hallucination regressions when prompts or models change).
- Exploration mode stress test: scripted rapid scrubbing and variation creation while the engine session runs, asserting no stale-eval rendering and no engine process leaks.
- Manual E2E per milestone as listed in acceptance criteria; be picky about UI details - misaligned squares, wrong piece scaling, or janky eval-bar animation are bugs, not polish items.

## Risks and mitigations

- **LLM chess hallucination** - the top product risk, addressed architecturally by the Verified Coach stack: structured input, the CoachVerifier hard gate (nothing unverified renders), the engine-tool loop, and a CI harness that fails on any leak. The residual risk is verifier gaps (claims phrased in ways the parser misses), so grow the verifier's claim-extraction tests with every new prompt or model.
- **Engine session management** - chesskit-engine runs Stockfish in-process (no subprocess/pipes to leak), but stale results during rapid scrubbing are still possible with an async response stream. Mitigate with a single owning actor in EngineKit and position generation counters on all results (drop anything not matching the currently displayed position).
- **Stockfish is GPLv3** via chesskit-engine - fine for local personal use; revisit licensing before any public distribution (see Architecture note).
- **RAM pressure** - running Stockfish (hash) + a 14B model + the app on a 16 GB machine. Keep Stockfish hash modest (256 MB default), and pause engine analysis while the LLM is generating if memory pressure is high.
- **chess.com API changes/rate limits** - the API is unofficial-but-public; wrap it thinly, cache aggressively, and always keep the PGN path as the reliable fallback.
- **chesskit-swift gaps** - if it lacks something (e.g. Chess960 or odd PGN variants), fix behind the ChessCore facade; do not leak the dependency into the app layer.

## Out of scope for v1

Puzzles/drills generated from your mistakes, spaced repetition, repertoire training, playing against the engine, Lichess import, iCloud sync, Chess960.
Note them in HANDOFF.md as future directions; do not build them.
