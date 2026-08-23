# Multi-ply practice exchange

P4.5 multi-ply practice is implemented on branch multiply-practice-p4.5.
The session view model now owns one Equatable PracticeExchange value for the entire learner and opponent exchange.
The exchange stores the legal rank-one prefix, next learner cursor, applied UCI prefix, stage, learner outcomes, learner evaluations, and an all-plies first-attempt flag.
Rank-one principal variations are replayed once at card initialization, and only their legal prefixes enter the exchange.
The board position, legal destinations, promotion checks, and last-move highlight are derived by replaying the applied prefix.
Multi-ply cards compare each learner UCI move exactly with the stored rank-one learner ply.
Correct learner moves are applied immediately, followed by an explicit replying state and one injected-delay opponent reply.
Delayed replies are guarded by card identity, learner cursor, applied prefix, and replying stage so reset and next-card transitions cannot mutate a later card.
Learner checkmate completes without a reply, while opponent checkmate completes after the reply has been shown.
Wrong learner moves use the typed card explanation and a fixed expected-SAN sentence.
Wrong attempts persist one incorrect exchange attempt and reset the entire exchange on retry.
Fully correct exchanges persist one strong attempt and apply the scheduler once at completion.
Intermediate correct learner moves and automatic replies do not create attempts or scheduler writes.
First-attempt success is counted only when every learner ply in the exchange succeeds before any retry.
Legacy one-learner cards continue through TrainingMoveEvaluator, preserving playable-alternative grading and existing feedback.
Ignored-threat facts now carry an application-owned marker through the existing themes JSON.
The marker is parsed only by the exact marker prefix, excluded from learner-facing themes, and excluded from recurring-theme aggregation.
Hint level one presents the typed threat SAN when the marker exists and falls back to the generic forcing-idea hint for old cards.
The practice UI now exposes Step N of M, three reserved hint lines, an accessible Opponent replies SAN status, and a display-only board outside learner prompts.
The display-only board is disabled for keyboard and VoiceOver interaction outside the learner prompt.
Focused tests cover successful three-ply exchanges, wrong second learner moves, learner and opponent checkmates, stale delayed replies, scheduler atomicity, first-attempt summaries, marker generation and compatibility, legacy cards, and malformed lines.
The focused macOS test command passed 49 tests across the PracticeSessionViewModel and TrainingDomain suites after the final additions.
Visual window capture was unavailable in this environment, so accessibility-oriented source checks and state-driven injected-delay verification were used for the reply flow.
