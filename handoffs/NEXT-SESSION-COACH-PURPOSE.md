# Next session - what the LLM Coach is for (P4.8)

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with three other sessions (fork detection, move-quality flags, multi-ply practice cards - separate worktrees/branches, do not read or wait on any of them, your work is independent).

You are working in a dedicated git worktree on branch `coach-purpose-p4.8`, checked out from `main`. Commit and push this branch when you are done; do not merge to `main` yourself; do not touch the primary checkout at `/Users/willis/Documents/chessanto` or any other worktree directory.

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.8 Decide what the LLM Coach is for" section, in full - this is the actual scope document; the recommended direction below is already written there, this session executes it.
3. `Packages/CoachKit/Sources/CoachKit/CoachPrompt.swift`, in full.
4. `Packages/CoachKit/Sources/CoachKit/CoachChat.swift`, in full.
5. `Packages/CoachKit/Sources/CoachKit/CoachVerifier.swift`, in full - this is the grounding gate every Coach response already passes through. Read `verify(text:context:)` closely; it already checks that cited lines replay legally and that numeric claims match known values, but it does not currently check whether a response actually says anything concrete at all.
6. `Packages/CoachKit/Sources/CoachKit/CoachPayloadBuilder.swift`, in full, for the typed payload shapes (`CoachMomentPayload`, `CoachChatPayload`, `CoachFactsPayload`) already assembled from audited report Facts - this is the "better than a 4B model's reasoning" data the backlog document refers to.
7. `Packages/CoachKit/Tests/CoachKitTests/` - read the existing test files for `CoachChat`/`CoachVerifier`/`CoachPrompt` to understand this package's established test patterns (it likely mocks an LLM client - find and understand that mock before designing new tests against it).
8. `App/Sources/Chessanto/Coach/CoachModelCatalog.swift` - confirms the default local model tier (`qwen3:4b` under 16GB RAM) that the backlog document specifically calls "far too weak for chess reasoning."

## The problem, concretely observed

From a real captured interaction in this app: asked "How should White continue here?", the Coach answered with tautologies ("e4 is a classic opening move for White, and it's a good choice to continue the game"), repeated the identical answer verbatim when asked the identical question again, and ended with "Let me check the evaluation to see which of these options is the best" without actually checking. `CoachVerifier` passed this response, because the moves mentioned were legal and no false evaluation was claimed - the verifier proves nothing false was said, but does nothing to ensure something useful was said.

## Scope for this session - implement the backlog's recommended direction, in its stated order of preference

The backlog document itself already ranks three options. Implement the first two; the third (raising the minimum model floor) is a product/UX decision about what hardware tier gets a working Coach at all, not a code change this session should make unilaterally - note it in your report as a live open question rather than deciding it.

### 1. Make the Coach a structured explainer over the app's own facts, using the LLM for phrasing only

The core idea: for the well-defined cases where this app already knows the answer as an audited Fact (asking about a specific key moment that already has a `CoachMomentPayload` with `CoachFactsPayload` attached - `betterMove`, `punishment`, `ignoredThreat`, `missedMate`, `allowedMate`), the LLM's job should be to phrase what the app already knows, not to reason freely about the position from scratch. This is not a proposal to remove the LLM - it's to constrain what it's being asked to invent.

Concretely: read `CoachPrompt.momentUserMessage(payload:)` and `CoachPrompt.systemPrompt(register:)` - decide whether the system prompt for a moment-specific question should more strongly instruct the model to *restate and phrase* the attached Facts rather than *reason freely*, and implement that prompt change. State exactly what you changed and why, the same way this codebase's other Coach-prompt work has documented tradeoffs (see `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md`'s note on `CoachVerifier`'s grounding guarantee needing explicit re-verification whenever the prompt changes, not just a visual/textual check).

For the open-ended chat case (`CoachChat.send(question:context:)`, no specific key moment, e.g. "how should White continue here?") - this is the harder case the observed bad example came from. Decide how "structured explainer" applies when there is no pre-computed Fact to phrase, i.e. whether this case should lean more heavily on option 2 below (forcing a real tool call) rather than trying to eliminate free reasoning entirely, since some free reasoning is unavoidable for a genuinely open question. State your reasoning.

### 2. Enforce concreteness in the verifier - make calling `evaluate` a hard gate for open-ended questions

`CoachPrompt.chatSystemPrompt`'s existing instruction (already present, read the exact text) tells the model to call the `evaluate` tool before answering an open-ended question - but nothing currently *enforces* this. The observed bad example said "Let me check the evaluation" and then didn't.

Add a real gate: for an open-ended chat question (not a moment-specific one, where the Facts are already provided), if the model's final response makes any concrete-sounding claim about the position (a move recommendation, an evaluation, a plan) **without having actually invoked the `evaluate` tool at least once during that turn**, treat this as a violation and force a regeneration - reuse `CoachVerifier`'s existing `Violation`/`Verdict`/regeneration mechanism (`CoachPrompt.regenerationUserMessage(violations:)` already exists for exactly this kind of "try again, here's what was wrong" flow) rather than inventing a new one.

You will need to determine, precisely, what counts as a "concrete-sounding claim" without over-triggering on genuinely tool-free responses (e.g. a purely conversational reply, or an answer to a question that isn't actually about the position) - state your exact rule and test it against both a real violation and real non-violations.

### 3. The model floor - report only, do not implement

State plainly in your report whether, having read `CoachModelCatalog` and the observed failure mode, you believe the `qwen3:4b` default tier is capable of following the strengthened structured-explainer instructions and correctly triggering the `evaluate` tool call reliably, or whether the backlog's suggestion to "state plainly that below 8B the Coach is disabled" deserves to be acted on later. This is a recommendation for the orchestrator to decide, not something to implement this session.

## Required rigor

- `CoachVerifier`'s grounding guarantee (nothing unverified renders) must not be weakened by anything in this session - if your prompt changes make the verifier reject more responses and fall back to rule-based text more often, say so explicitly and treat that as an expected, acceptable tradeoff of tightening the standard, not a regression to hide.
- Any Coach-prompt change must be re-verified against real model behavior, not just read for correctness - if you have access to a running Ollama instance with a model from `CoachModelCatalog`'s tiers, actually send real questions through `CoachChat` and observe real responses before and after your change (the same live-verification discipline this project applies everywhere else - a prompt change "should" work is not the same as verified). If you do not have a real LLM backend available in your environment, say so explicitly and rely on `CoachKit`'s existing mock-based test suite instead, clearly marking what is verified against a real model versus only against the test mock.
- TDD. Write the failing test before each piece of implementation.
- Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in long Markdown. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Test plan (minimum)

- A moment-specific question with a `CoachFactsPayload` attached - the response, under your strengthened prompt, stays grounded in the provided facts (test against the mock LLM client's existing pattern, and against a real model if available).
- An open-ended question where the mocked/real model's response makes a concrete claim without calling `evaluate` - triggers the new violation and a regeneration attempt, using the existing `Violation`/regeneration machinery.
- An open-ended question where the model correctly calls `evaluate` before answering - no violation, passes through normally.
- A genuinely non-concrete response (e.g. a clarifying question back to the user, or a conversational aside not about the position) - does not falsely trigger the new gate.
- Confirm the existing `CoachVerifier` test suite still passes unmodified (or, if you found a reason to change an existing test, report exactly why).

## Validation commands

1. `swift test` from `Packages/CoachKit/` - must pass. Report the baseline count first.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 179 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Fork/pin detection, move-quality flags, multi-ply practice cards (separate parallel sessions). Do not touch `Packages/AnalysisKit`. Do not raise the default model floor or change `CoachModelCatalog`'s tiers - report-only, per section 3 above. Do not redesign the Coach UI panel (a prior session already did entry-point clarity; this session is prompt/verification logic only).

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries.
Write a dated devlog at **`devlogs/2026-08-24-coach-purpose.md`** (this exact filename - three other sessions are writing their own devlogs today).
Commit on this branch (`coach-purpose-p4.8`) and push it to `origin` - do not merge to `main` yourself.
Report back plainly: the exact prompt changes you made, the concreteness-gate rule you implemented and why, whether you verified against a real model or only the test mock, your recommendation on the model floor, and validation results.
