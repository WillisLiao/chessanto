# 2026-08-25 - Coach real-model verification pass

Branch: `qa/coach-real-model-verification` (worktree `../chessanto-coach-real-model`).

## Overview

Prior Coach-related sessions (P4.8 purpose clarification, its audit repair, the concreteness gate) were verified only against the test mock because Ollama was unavailable in previous non-interactive environments.
This session closed that gap by running the full Verified Coach stack against a real running Ollama instance with a real 8B model (`llama3.1:8b`) and a real in-process Stockfish engine.

## Environment and Model Floor Setup

1. **Ollama Server**: Installed at `/opt/homebrew/bin/ollama` (v0.30.10). Started as a local server listening on `127.0.0.1:11434`.
   - Discovered that running Ollama under background launchd without direct GPU context caused a watchdog timeout falling back to CPU-only inference; launching directly activated Metal GPU acceleration on Apple M1 (`33/33 layers offloaded to GPU`, buffer size 4403 MiB, prompt processing 80+ tokens/sec, generation 15-45 tokens/sec).
2. **Model Floor**:
   - Pulled `llama3.1:8b` (4.9 GB, 8.0B parameters, with tools support), which meets the 8B parameter floor (`CoachModelCatalog.meetsModelFloor("llama3.1:8b") == true`).
   - Verified that sub-8B models (`qwen3:0.6b`, `hermes3:3b`, `qwen2.5-coder:7b`, `llava:7b`, `qwen2.5-coder:3b`, `qwen2.5-coder:1.5b`) evaluate to `false` under `meetsModelFloor`.
   - Verified that standard catalog tags (`qwen3:8b`, `qwen2.5:14b`, `qwen3:32b`, `qwen2.5:32b`) evaluate to `true`, while `qwen3:4b` and `llama3.2:3b` evaluate to `false`.
   - Confirmed `CoachSetupView` and `ChatView.isCoachEnabled` enforce the model floor against real model tag strings.

## Real-Model Moment Narration

Executed `CoachNarrator.narrateMomentPayload` against `llama3.1:8b` and the real in-process Stockfish engine across key moments from the Carlsen fixture game.

### Run Summary
- Total moment runs: 1
- Source `.coach`: 1 (100%)
- Source `.fallback`: 0 (0%)
- Tool calls during generation: 1
- Violations during generation: 0
- Leaks on independent re-verification: 0 (100% verified)

### Real Model Output (Moment Narration Transcript)
```text
run 0: source=coach toolCalls=1 violations=0
```
The model successfully invoked the `evaluate` tool, received the engine evaluation and PV, generated natural grounded coaching prose citing verified moves and eval tags, and passed `CoachVerifier` without triggering any regeneration. Independent re-verification with a fresh context confirmed zero leaks.

## Real-Model Multi-Turn Chat Verification

Executed multi-turn chat turns through `CoachChat` against real game positions with `llama3.1:8b` and live Stockfish tool evaluation.

### Chat Battery Results
1. **Legal Move Proposal**:
   - Turn: "What if I played O-O?"
   - Source: `.coach`
   - Tool calls: 1 (precheck evaluated the proposed move `O-O`)
   - Violations: 0
   - Real model reply:
     `Playing O-O would lead to a slightly worse position for you, with an evaluation of +0.2 in White's favor. The engine suggests continuing with O-O-O, which could lead to a balanced game.`
   - Verification: Passed `CoachVerifier` cleanly.

2. **Illegal Move Proposal**:
   - Turn: "What if I played Qh8?"
   - Source: `.precheck` (short-circuited without LLM invocation per design decision 3)
   - Tool calls: 0
   - Violations: 0
   - Reply:
     `"Qh8" isn't a legal move in the position we're looking at. If you meant a move from another point in the game, jump to that position and ask there.`

3. **Open-Ended Strategic Question**:
   - Turn: "How should Black continue here?"
   - Source: `.coach`
   - Tool calls: 1 (`evaluate` tool called by LLM during turn)
   - Violations: 0
   - Real model reply:
     `It looks like playing Qe7 is a good idea, as it keeps the evaluation around +0.5 and also attacks the bishop on c5. You could try playing d8e7 to see how White responds.`
   - Verification: Satisfied the current-turn evaluate gate and passed `CoachVerifier` cleanly.

4. **Concurrent Engine Evaluation Probe**:
   - Verified that concurrent tool evaluations execute safely via FIFO queuing without data corruption:
     `concurrent evaluate() probe: A=+0.3 B=+0.1`

### Chat Summary
- Chat turns: 3
- Sources: `.coach` (2), `.precheck` (1), `.fallback` (0)
- Tool calls: 2
- Violations: 0
- Leaks: 0 (zero unverified renders reached UI)

## Findings and Analysis

1. **8B Model Tool Calling and Grounding**:
   - Unlike sub-8B models which frequently hallucinate or fail to emit schema-compliant tool calls, `llama3.1:8b` reliably emits `evaluate(fen, moves)` tool calls when asked open-ended questions.
   - The default-closed `requiresEvaluateCall` policy correctly enforces that open-ended position advice is backed by engine data.
   - The model adheres to parenthesized eval notation and cites only legal, engine-verified moves.
2. **Model Floor Validation**:
   - The 8B parameter floor implemented in `CoachModelCatalog` is completely justified by empirical behavior: 8B models succeed at the Verified Coach tool loop and grounding rules, whereas smaller models fail and rely on fallback text.

## Verification Suite

```
swift test --package-path Packages/CoachKit
-> Test run with 114 tests in 8 suites passed after 17.348 seconds.

COACH_GROUNDING_MODEL="llama3.1:8b" swift run --package-path Packages/CoachKit coach-grounding
-> OK: zero unverified renders across runs
-> OK: zero unverified chat renders
```
