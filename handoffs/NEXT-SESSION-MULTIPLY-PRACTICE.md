# P4.5 multi-ply practice cards

Status: Delivered on branch `multiply-practice-p4.5`.

The multi-ply practice exchange is implemented, tested, committed, and pushed.

`PracticeSessionViewModel` owns one Equatable `PracticeExchange` value containing the legal rank-one prefix, cursor, applied UCI prefix, stage, learner outcomes, and all-plies first-attempt flag.

The rank-one principal variation is replayed once at card initialization and only its legal prefix is retained.

The current applied prefix drives the position, legal move context, promotion checks, and last-move presentation.

Exact stored-PV grading applies whenever the legal prefix contains more than one ply, including a two-ply line with one learner turn.

True one-ply cards and malformed or empty legacy lines use the existing evaluator fallback without crashing.

After each correct learner move, the exchange exposes the learner position, enters `replying`, announces the stored opponent SAN, and applies exactly one delayed opponent move through the existing board and last-move path.

Delayed replies are guarded by card identity, cursor, and stage so reset and next-card actions cannot apply stale work.

The exchange ends only when the legal stored line is exhausted or the latest replayed move is checkmate.

Wrong feedback uses the typed card explanation when present and a fixed expected-SAN template.

`tryAgain()` resets the whole exchange while preserving a failed first-attempt flag.

Scheduling is all-or-nothing per exchange attempt, with one incorrect write for a failed attempt or one strong write after a fully correct line.

The threat hint uses an exact application-owned marker derived from `IgnoredThreatFact.threatenedSAN`, while old cards retain the generic fallback.

The UI shows progress, reserved hint slots, accessible reply status, and disabled board interaction while a reply is pending.

No persistence schema, analysis detector, CoachKit, or unrelated selection behavior was changed.

Focused tests cover multi-ply success, wrong second learner move and reset, checkmate termination, delayed-reply stale guards, scheduler atomicity, first-attempt accounting, typed and generic hints, legacy single-ply cards, malformed lines, and the two-ply exact-PV boundary.

Full macOS build and test validation passed with 188 tests across 34 suites.
