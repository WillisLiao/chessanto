# 2026-08-24 - What the LLM Coach is for (P4.8)

The initial P4.8 record below describes the pre-audit implementation and is superseded by the bounded audit repair section at the end of this file.

## Context & Problem

From a real captured interaction: asked "How should White continue here?", the Coach answered with tautologies ("e4 is a classic opening move for White, and it's a good choice to continue the game"), repeated the identical answer verbatim when asked the identical question again, and ended with "Let me check the evaluation to see which of these options is the best" without actually calling the evaluate tool.
`CoachVerifier` passed this response because the moves mentioned were legal and no false evaluation was claimed.
The verifier proves nothing false was said, but does nothing to ensure something useful was said.

The backlog document (P4.8 in `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`) ranked three options.
This session implemented the first two.

## Implementation

### 1. Structured-explainer prompting (CoachPrompt.swift)

**Moment-specific system prompt** (`CoachPrompt.systemPrompt`): added six new lines instructing the model that the JSON data contains verified facts (betterMove, punishment, missedMate, allowedMate), that its job is to restate and phrase those facts in coaching prose, and that it must not reason about the position from scratch or speculate beyond what the data says.
The LLM is explicitly told not to invent facts that aren't present in the data.

**Chat system prompt** (`CoachPrompt.chatSystemPrompt`): strengthened the existing rule 4 from a soft instruction ("call the evaluate tool to check at least one concrete line") to a hard directive ("you MUST call the evaluate tool to get concrete engine data before answering. Do not recommend moves, suggest plans, or state evaluations without first calling the tool. Never say 'let me check' or 'let me evaluate' without actually calling the tool.").
Added rule 5: if the position data already includes engine lines in the JSON, the model may cite those directly without a tool call.

**Design reasoning for the open-ended chat case:** for moment-specific questions, the structured-explainer approach works cleanly because there are pre-computed Facts to phrase.
For open-ended chat ("how should I continue?"), there is no pre-computed Fact, so some free reasoning is unavoidable.
The prompt change tells the model to call the tool, but the real enforcement comes from option 2 below, because a prompt instruction alone cannot prevent the observed failure - the model already had a prompt instruction to call evaluate and ignored it.

### 2. Concreteness gate (CoachVerifier + CoachChat)

Added `CoachVerifier.containsConcreteClaim(in:)` - a static method that detects whether response text makes concrete position claims.

The detection rule, designed to avoid false positives on genuinely non-concrete responses:

- A **numbered move chain** (e.g. "1. e4", "12... Nf6") is always concrete.
- A **move-recommendation phrase** ("you should play", "the best move", "I recommend", "consider playing", "is a good move", "is a classic opening", etc.) combined with any move token (including bare squares) is concrete.
- An **evaluation-assertion phrase** ("winning", "losing", "advantage", "better position", "the evaluation", etc.) combined with a *strong* (non-bare-square) move token is concrete.
Bare squares alone don't trigger on eval phrases to avoid flagging "the pawn on e4 controls important squares".
- **Bare conversational text** with no move tokens at all is never concrete.

The gate is wired into `CoachChat.send()`, between the existing `CoachVerifier.verify()` pass and the final response:
- If the response passes the verifier (no false claims) **but** the LLM made zero evaluate tool calls during its turn **and** no pre-existing engine data was available in the payload (no currentPositionLines, no precheck evaluations, no seed eval), **and** the response contains a concrete claim, then it is treated as a violation.
- The violation triggers regeneration using the existing `CoachPrompt.regenerationUserMessage(violations:)` machinery, with a message telling the model to call the evaluate tool first.
- If the second attempt also fails, the response falls back to the canned fallback text.

**Why `hadEngineData` matters:** when `CoachChat` provides engine lines to the model (from stored analysis, precheck evaluations of proposed moves, or the seed evaluation), the model legitimately has verified data to cite.
Blocking concrete claims in that case would break the normal happy path.
The gate only fires when the model had no data and didn't go get any.

### 3. Model floor recommendation (report only)

Having read `CoachModelCatalog`, the observed failure came from a `qwen3:4b` model (the default for machines with under 16GB RAM).
The strengthened structured-explainer prompt gives the model clearer instructions, and the concreteness gate mechanically prevents ungrounded answers from rendering.
However, `qwen3:4b` is likely too weak to reliably follow the strengthened instructions or correctly trigger tool calls.
The concreteness gate means the failure mode shifts from "tautological advice rendered to the user" to "frequent fallback to canned text", which is a better failure mode but still a degraded experience.

**Recommendation:** the backlog's suggestion to disable the Coach below 8B deserves to be acted on.
A model that routinely falls back to canned text is worse than clearly telling the user their hardware doesn't support the Coach.
This is a product/UX decision, not implemented this session.

## Tradeoffs

- **The verifier may reject more responses and fall back more often** with these changes.
The strengthened prompt asks the model to do more (call tools, stick to facts), and the concreteness gate adds a new failure mode.
This is an expected, acceptable tradeoff: a canned "I couldn't give you a verified answer" is better than the observed "e4 is a classic opening move" tautology.
- **CoachVerifier's grounding guarantee is not weakened.**
The concreteness gate adds a new check on top of the existing verification, never bypasses it.
All existing verification (cited-line replay, numeric claim matching, suffix checking) runs unchanged.
- **Concreteness detection is heuristic, not semantic.**
The phrase lists cover the observed failure modes but could miss novel phrasings.
This is acceptable because the existing verifier already catches false factual claims; the concreteness gate only catches the case where the model says something that sounds like advice without having checked.

## Verification

- **Verified against the test mock only, not against a real model.**
No running Ollama instance was available in this environment.
All new behavior is verified through CoachKit's mock-based test suite.
- Packages/CoachKit: 86 tests across 8 suites (was 74). All pass.
- The 12 new tests cover:
  - Concreteness detection: numbered chains, recommendation phrases, eval assertions, bare squares, conversational text, clarifying questions, the observed tautology case, the "let me check" case.
  - Concreteness gate integration: concrete claim without tool call triggers fallback, concrete claim after tool call passes, non-concrete response passes, pre-existing engine data allows concrete claims.
- All existing tests pass unmodified.

## Test plan results

| Scenario | Result |
|---|---|
| Moment-specific question with CoachFactsPayload - response stays grounded in facts | Existing narrator tests pass; prompt change is additive |
| Open-ended question, model makes concrete claim without calling evaluate | New test: triggers violation, regeneration, fallback (CoachChatTests) |
| Open-ended question, model correctly calls evaluate before answering | New test: passes through normally (CoachChatTests) |
| Non-concrete response (clarifying question, conversational aside) | New test: no violation (CoachChatTests + CoachVerifierTests) |
| Existing CoachVerifier test suite | All 20 original tests pass unmodified |

## Bounded audit repair (2026-08-24)

The independent audit found that the first P4.8 implementation let pre-existing payload lines, precheck evaluations, and seed evaluations bypass the required chat-turn evaluate call, and that attempted tool calls were counted even when evaluation failed.
`CoachChat` now gates every concrete position claim on at least one successful `evaluate` invocation performed by the model's tool loop during the current user turn.
`CoachNarrator.ConversationResult.successfulEvaluateCalls` increments only after the `evaluate` executor returns successfully, so invalid or failed calls do not satisfy the gate.
`CoachChat` carries that successful-call signal across its one regeneration attempt and resets it for every new user turn.
The contradictory `hadEngineData` bypass and the chat prompt's payload exception were removed.

`CoachVerifier.containsConcreteClaim` now covers concrete evaluation assertions without move tokens, bounded tactical and plan language without move tokens, and developmental claims such as `Nf3 develops naturally` while keeping greetings, square references, and genuine clarifying questions tool-free.
The deterministic plan phrases include ordinary inflections such as `developing your pieces` and `controlling the center` or `controlling the centre`, while a narrow explicit-opening and terminal-question predicate exempts pure clarifying questions such as `Are you asking whether White is winning?` without exempting declarative advice followed by a question.
`CoachFactsPayload` now carries the audited `ignoredThreat` fact, and the moment prompt names and explains all five supported fact families: betterMove, punishment, ignoredThreat, missedMate, and allowedMate.

The repair is verified against the CoachKit mock client only because no Ollama service was available at `127.0.0.1:11434` during this session.
CoachKit now passes 102 tests across 8 suites, and the root macOS suite passes 179 tests across 34 suites.
The root macOS build ends with `** BUILD SUCCEEDED **`, the root macOS test ends with `** TEST SUCCEEDED **`, and `git diff --check` is clean.
The model-floor question remains report-only, and the current evidence still supports evaluating an 8B minimum later rather than changing `CoachModelCatalog` in this repair.
