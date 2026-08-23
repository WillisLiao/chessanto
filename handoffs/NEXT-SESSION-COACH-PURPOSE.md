# Coach purpose handoff (P4.8 complete)

P4.8 is complete on branch `coach-purpose-p4.8` in the dedicated Coach worktree.
The Coach uses audited moment facts for moment-specific phrasing, including betterMove, punishment, ignoredThreat, missedMate, and allowedMate.
The moment prompt tells the model to phrase supplied facts rather than reason about the position from scratch.
`CoachChat` requires a successful current-turn `evaluate` invocation before any non-empty final response that is not explicitly whitelisted as tool-free.
`CoachNarrator.ConversationResult.successfulEvaluateCalls` increments only after a successful `evaluate` executor result, excludes invalid or failed calls, survives one regeneration attempt, and resets for each new user turn.
Pre-existing payload lines, precheck evaluations, seed evaluations, and fresh verifier evaluations do not satisfy the current-turn model-tool requirement.
`CoachVerifier.requiresEvaluateCall` normalizes case, punctuation, and whitespace, then permits only a deliberately tiny exact whitelist of greetings, thanks, acknowledgments, and pure clarifying questions.
The required safe clarifier `Are you asking whether White is winning?` is whitelisted after normalization, while close variants and clarifiers containing advice require evaluation.
All other non-empty responses require evaluation, including general chess instruction, board facts, plans, tactics, nuanced evaluations, and advice followed by a question.
The existing grounding verifier remains authoritative for legal lines, suffixes, and numeric facts, and the stricter evaluate gate may regenerate or fall back more often by design.
The CoachKit mock suite passes 109 tests across 8 suites, and the root macOS suite passes 179 tests across 34 suites.
The root macOS build and test both pass, and `git diff --check` is clean at delivery.
No real Ollama model was available during the repair, so model behavior is mock-verified only.
The model-floor decision remains report-only, with the earlier recommendation to consider disabling the Coach below 8B left for product direction.
