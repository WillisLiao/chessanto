# Chessanto - Build Plan

A local-first macOS chess coach.
It imports your chess.com games (or any PGN), analyzes them with Stockfish on-device, and teaches you through rating-adaptive explanations and an interactive position chat powered by a local LLM.
It is also a full chess.com-style analysis board: scrub anywhere in the game with a live eval bar, and play out your own variations with the engine evaluating in real time.
No account, no cloud, no internet required for analysis.
The bar: the best modern local chess analyzer and teacher, not a toy.

This plan originally guided the initial milestone-by-milestone development of Chessanto.
Milestones M1 through M8, UI/UX clarity passes, active learning loop, and core Priority 1 through Priority 5 items are implemented in production.
See `handoffs/HANDOFF.md` for living status and active integration tracking.

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

Milestones M1 through M8 are completed and verified in production.

### M1 - Skeleton, board, and game replay [Completed]
- Xcode project and local SPM packages configured; GRDB persistence wired with migrations.
- Custom SwiftUI board view with piece rendering, coordinates, last-move highlights, board flip, and resizable layout.
- PGN import via file open, drag-drop onto window, and paste.
- Game replay with move list and keyboard navigation.

### M2 - Engine integration and move classification [Completed]
- EngineKit in-process Stockfish integration with MultiPV parsing and clean lifecycle management.
- Background analysis queue with progress reporting, cancellation, and SQLite caching.
- Live eval bar and whole-game eval graph.
- Live infinite analysis of the displayed position during scrubbing with generation-counter debouncing.
- Move classification and accuracy aggregation.

### M3 - Exploration Mode [Completed]
- Free variation play on the board, variation tree in the move list (delete subtree, back to game), and variation persistence.
- Engine lines panel with adoptable MultiPV lines.
- Promotion and collapse variation controls remain open.

### M4 - chess.com fetch [Completed]
- ChessComKit archive client with descriptive User-Agent.
- Game browser sheet with multi-select import and duplicate detection.

### M5 - Rule-based coaching report [Completed]
- Theme detection and key-moment selection pipeline.
- Game report view with accuracy summary, classification counts, opening book identification, and rule-based explanations from structured Facts.
- Whole-game takeaways summarizing recurring patterns.

### M6 - Local LLM coach [Completed]
- CoachKit with Ollama client, model catalog, and health checks.
- Verified Coach stack with structured payloads, CoachVerifier output gate, and fallback to rule-based explanations.
- Rating-adaptive prompt registers (beginner, intermediate, advanced).

### M7 - Position chat [Completed]
- Conversational chat attached to the displayed position with legality prechecks, evaluate tool loop, and CoachVerifier gate.
- Suggested starter prompts and chat history persistence per game.

### M8 - Polish and packaging [Completed]
- Onboarding flow with optional chess.com username, rating band, and model guidance.
- Settings window, light appearance lock, and sandbox entitlements.
- Player Brief improvement dashboard with accuracy history and recurring motifs.
### Post-M8 Extensions & Hardening [Completed]
- **Play vs Engine**: Full interactive match against Stockfish with 5 difficulty tiers (Beginner to Master), side selection (White, Random, Black), live thinking indicators, resignation, draw claims, and seamless transition to post-game review and analysis report.
- **Chess960 (Fischer Random)**: Full Chess960 support across board setup, move generation, castling contracts, Stockfish `UCI_Chess960=true` mode, FEN handling, and game reports.
- **Library Search & Multi-criteria Filter**: Sidebar search across opponents, opening names, and ECO codes, paired with a multi-criteria filter panel (Opponent, W/L/D Result, ECO Family, Time Control, Accuracy Band, Date Range).
- **Accessibility Matrix**: Comprehensive VoiceOver board semantics (64 individual square buttons announcing pieces, addresses, legal destinations, and move announcements), Full Keyboard Access movement (arrow navigation + Space/Return move execution), AA contrast compliance in light and dark modes, Dynamic Type support, and Reduced Motion integration.
- **Coach Real-Model Verification**: Grounding verification against local Ollama models (`llama3.1:8b`) ensuring zero hallucination leaks across moment narration and multi-turn position chat.
- **Opening Book Quality**: Bundled 3,803 ECO opening lines and 3,801 unique positions in `AnalysisKit`.
- **Release Packaging Pipeline**: Production-ready `scripts/release-build.sh` generating self-contained sandboxed `.app` bundles with embedded Stockfish 17 NNUE networks.

## Testing strategy

- Unit tests: win-probability and accuracy math, move classification thresholds, PGN edge cases, UCI response parsing, theme detectors, and chess.com API response decoding.
- Integration test: analyze a bundled fixture game end-to-end against a golden classification file.
- CoachVerifier unit tests: crafted outputs with illegal moves, invented lines, and wrong eval claims caught before display.
- LLM grounding test harness: tests narrations and chat turns against fixture payloads through CoachVerifier.
- Exploration mode stress test: rapid scrubbing and variation creation with generation-tagged analysis.
- Full automated test suite across packages and the macOS App target (260+ tests passing).

## Risks and mitigations

- **LLM chess hallucination** - addressed architecturally by the Verified Coach stack: structured input, the CoachVerifier hard gate, the engine-tool loop, and default-closed concreteness gating.
- **Engine session management** - chesskit-engine runs Stockfish in-process with generation counters on all results to prevent stale evals during scrubbing.
- **Stockfish is GPLv3** - repository is licensed under GPLv3.
- **RAM pressure** - modest default Stockfish hash and recommended model sizing by hardware tier.
- **chess.com API changes/rate limits** - wrapped in ChessComKit, cached locally, with offline PGN import as fallback.
- **chesskit-swift gaps** - wrapped behind ChessCore facade.

## Out of scope

The following remain explicitly out of scope:
- **iCloud sync** (data remains strictly local on-device).
- **Lichess account sync/import** (Chess.com and offline PGN import supported).
- **Opening repertoire tree training** (handled via calculated mistake-derived training cards and exploration mode).

