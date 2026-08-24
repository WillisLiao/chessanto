# Chessanto - Handoff

Living snapshot of project state.
Read this first at session start; update it at session end.

## Current state (2026-08-25) - QA Hikaru games (scan run, Carlsen PGN fixes ported)

On `qa/hikaru-games`: the full-archive scan has now run end to end over all
152 cached archives (70,182 games, 5,510,993 plies replayed) in about 73 minutes.
First results: 4,503 PGN parse failures (all `PGNCompatibility.Error error 0`)
and 523 FEN mismatches against chess.com's `CurrentPosition` tag.
Root cause of both categories is the already-diagnosed upstream `chesskit-swift`
defect that this branch forked without: the SAN parser silently drops the
disambiguator on piece captures (`Nexd5` moves the wrong knight) and mishandles
rank/square disambiguation and castling-with-check suffixes.
Per the plan recorded below and in the devlog, the identical fix from
`qa/carlsen-games` was ported verbatim: `PGNCompatibility.requiresFallback`,
the rewritten `parseSAN` disambiguation/en-passant/suffix handling in
`ChessGame.init(pgn:)` routing, plus its 7 regression tests.
Validated against real failing data: all 7 sampled parse-failure games now parse,
and all 5 sampled FEN-mismatch games now TAG-MATCH after the port.
A full post-port suite re-run for the final summary block is queued;
ChessCore passes 64 tests with the port applied.
The scan test currently auto-runs whenever the cached archives exist on disk,
which adds roughly 73 minutes to every full app-suite run; gating it behind an
explicit environment variable at integration time is recommended so the main
verification bar stays runnable.

## Current state (2026-08-25) - QA Hikaru games (harness done, scan pending)

On `qa/hikaru-games`: the Hikaru QA harness is complete and verified, but the
full-archive scan itself has not run yet.
Follow `handoffs/NEXT-SESSION-QA-HIKARU-FINISH.md` to run it and finish the session.
All 152 monthly archives of chess.com user `hikaru` are cached locally as JSON
(70,182 games); `HikaruQAScanTests` drives them through the real app path
(`GameReplayViewModel` -> `ReportBuilding.buildInput`/`buildReport`) with no network.
The prior instance's redundant package-executable scanner was checkpointed
(`93bc961`) then deleted in favor of the app-path test, matching the Carlsen precedent.
One real bug found and fixed with a regression test: chess.com ships bughouse games
with no `pgn` key, which used to poison decoding of an entire monthly archive on the
real fetch path; `ChessComGame` now decodes missing PGN as empty and ChessComKit has 5 tests.
Package suites pass: ChessCore 57, ChessComKit 5, AnalysisKit 195.
Note this branch does NOT contain the Carlsen branch's three unmerged ChessCore PGN fixes;
if the scan surfaces those failure shapes, port the identical fix rather than re-deriving it.

## Current state (2026-08-24) - absolute-pin fact slice

The end-to-end absolute-pin slice is implemented on `codex/roadmap-completion`.
`ChessGame.absolutePins(in:)` uses ChessKit-backed hypothetical blocker removal and returns deterministic typed relations for both colors.
`ThemeDetector.pin(input:ply:)` requires strict FEN metadata, unsigned counters, and replay, then compares attacker, pinned-piece, and king identities across the move, including promotion, captures, en-passant, and castling bookkeeping.
Audited `PinFact` values attach only to already-selected key moments, render as a neutral verified-alignment sentence, and propagate through the backward-compatible Coach payload and restricted prompt wording.
The real 56-position fixture scan has three hand-reviewed fires at plies 25, 29, and 31, with no fires on the existing selected moments, so golden report and Coach resources remain unchanged.
ChessCore, AnalysisKit, and CoachKit focused and full package tests pass.

## Next up

All roadmap tasks from `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` are now fully implemented.
P1.1-P1.7, P2.2/P2.5/P2.6, P3.1-P3.3, P4.1-P4.8, and P5 are all complete.
The four remaining P4.2 detectors (skewer, discovered attack, back-rank weakness, trapped piece) are now implemented.
`[%clk]` clock parsing and time-pressure takeaways are implemented.
The Coach model floor (disable below 8B) is implemented.
Dark mode support (default stays light) is implemented.

The Chessanto roadmap is feature-complete.

## Current state (2026-08-24) - PGN parser hardening

Fixed real end-user PGN load failure (`invalidMove("Rb5")` and `ChessKit.PGNParser.Error error 2`) caused by upstream `chesskit-swift` `SANParser` regex dropping disambiguation on piece captures such as `30. Rfxe1`.
Preserved `Game(pgn:)` as the primary parser and added a targeted `PGNCompatibility` fallback that resolves affected disambiguated piece captures via `Board.move(pieceAt:to:)`, requiring exactly one legal source candidate after disambiguation.
Regression tests verify ordinary upstream parsing, compact PGN forms (`1.e4 e5`), attached move numbers, comments, NAGs, variations, castling, promotion, and en passant across 47 `ChessCore` tests, all package tests, and root app tests with `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **` in Release mode.
Live database SHA-256 remains intact and unchanged (`3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`).

## Current state (2026-08-24) - Rating register propagation

The resolved AnalysisKit RatingRegister is now propagated across every production report-building path rather than silently defaulting non-replay surfaces to .advanced.
`ReportBuilding.swift` provides a unified shared seam with `ReportBuilding.userRating(in:username:)`, `ReportBuilding.resolveRegister(userProfile:ratingBand:userRating:record:username:)`, and `ReportBuilding.buildReport(record:analysisRows:chessComUsername:userProfile:register:)`.
`GameReplayViewModel`, `DashboardView` (both `computeDashboard` and `backfillTrainingCards`), `PlayerBriefView.buildSnapshot`, and `MacGameAnalysisBackend` all resolve their `RatingRegister` through this shared seam.
`MacCompletedAnalysis` in `GameAnalysisApplicationService.swift` carries the resolved register through to `PortableReportAssembler.assemble(..., register:)` and `PortableAnalysisReport`.
Callers and tests that genuinely omit profile and rating context preserve backward compatibility through the `.advanced` register fallback.
The changes are covered by 10 new unit and boundary propagation tests in `RatingRegisterPropagationTests.swift`, bringing the app suite to 198 tests across 35 suites.

## Current integration validation (2026-08-24)

The isolated fork, move-quality, multi-ply practice, and Coach-purpose branches are combined on `codex/roadmap-completion` without merging into `main`.
The combined `CoachFactsPayload` carries `ignoredThreat`, `fork`, and `moveQuality` through backward-compatible optional fields, and the structured prompt gives each fact an explicit grounded phrasing rule.
Fresh integrated validation passes 44 ChessCore tests, 195 AnalysisKit tests across 6 suites, 114 CoachKit tests across 8 suites, and 188 app tests across 34 suites.
The integrated macOS build ends with `** BUILD SUCCEEDED **`.

## Current state (2026-08-24) - P4.8 audit repair

The independent audit repair closes the concrete-claim gate loopholes from the earlier P4.8 implementation.
`CoachChat` no longer checks `hadEngineData`, and neither payload lines nor precheck or seed evaluations can satisfy the gate.
`CoachNarrator.ConversationResult.successfulEvaluateCalls` records only a successful `evaluate` executor result, and `CoachChat` retains that signal across regeneration while resetting it between user turns.
Invalid or failed evaluate calls therefore still regenerate and fall back when the final response is concrete.
`CoachVerifier.requiresEvaluateCall` now uses a default-closed policy in which every non-empty response requires a successful current-turn evaluate call unless its normalized text exactly matches the tiny whitelist of greetings, thanks, acknowledgments, or pure clarifying questions.
The clarifier whitelist includes `Are you asking whether White is winning?`, `What do you mean?`, and `Can you clarify your question?`, while advice-bearing and close-variant questions remain gated without a prefix parser or phrase-list detector.
The chat prompt no longer advertises a pre-existing-engine-data exception.
`CoachFactsPayload` and `CoachPayloadBuilder` now carry `ignoredThreat`, and the moment prompt explicitly tells the model to phrase that audited fact alongside betterMove, punishment, missedMate, and allowedMate.
The corrected behavior is covered by 109 CoachKit tests across 8 suites, including pre-existing, precheck, seed, successful, invalid, failed, regeneration, default-closed, safe-response, and clarifying-question cases.
The root macOS build passed with `** BUILD SUCCEEDED **`, the root macOS test passed with `179 tests in 34 suites` and `** TEST SUCCEEDED **`, and `git diff --check` passed.
No real-model run was possible because Ollama was unavailable at `127.0.0.1:11434`, so this repair is mock-verified only.
The model-floor decision remains report-only, with the earlier recommendation to consider disabling the Coach below 8B left for product direction.

## Current state (2026-08-24)

The original P4.8 record below is historical and is superseded by the bounded audit repair section above.

- **LLM Coach purpose clarified and enforced (P4.8).**
  Full narrative in `devlogs/2026-08-24-coach-purpose.md`.
  The observed failure - Coach answering "e4 is a classic opening move" tautologies and saying "let me check the evaluation" without checking - is now addressed at two levels.
  `CoachPrompt.systemPrompt` (moment-specific) now explicitly instructs the model to restate and phrase the attached verified facts (betterMove, punishment, missedMate, allowedMate) rather than reasoning about the position from scratch.
  `CoachPrompt.chatSystemPrompt` (open-ended chat) strengthened the evaluate-tool instruction from a soft suggestion to a hard directive with explicit "never say 'let me check' without actually calling the tool" language.
  A new concreteness gate in `CoachChat.send()` mechanically enforces what the prompt now requests: if the model's response passes `CoachVerifier` (no false claims) but makes concrete position claims (move recommendations, evaluation assertions, plans involving specific moves) without having called the evaluate tool and without pre-existing engine data in the payload, the response is treated as a violation and triggers regeneration via the existing `CoachPrompt.regenerationUserMessage(violations:)` machinery. Double failure falls back to canned text.
  `CoachVerifier.containsConcreteClaim(in:)` detects concrete claims via a combination of numbered move chains, recommendation phrases, and evaluation-assertion phrases paired with move tokens.
  `CoachVerifier`'s grounding guarantee is not weakened - the concreteness gate adds a check on top, never bypasses existing verification.
  The verifier may reject more responses and fall back more often; this is an expected tradeoff (canned fallback is better than tautological advice).
  Model floor recommendation (report only, not implemented): `qwen3:4b` is likely too weak to reliably follow the strengthened instructions or call tools; the backlog's suggestion to disable the Coach below 8B deserves action.
  Verified against the test mock only - no running Ollama instance was available.
  Packages/CoachKit: 86 tests across 8 suites (was 74). App suite unchanged.

## Current state (2026-08-24)

- **P4.2 fork detection is implemented on the dedicated branch.**
  `ChessGame.attackedEnemySquares(from:in:)` delegates to ChessKit legal moves, filters occupied enemy destinations, is independent of FEN side to move, and returns deterministic square and piece-kind pairs without hand-written attack geometry.
  `ForkFact` and `ForkTarget` are carried through `KeyMoment`, `ReportBuilder`, and `FactAuditor`, then rendered by a fixed `ReportText` sentence while selector priority remains unchanged.
  The detector requires two valuable non-king targets or a king plus one valuable non-king target, excludes pawns, replays the post-move rank-1 line through an opponent response, the same forking piece capturing an original target, and one opponent reply, and requires at least one pawn-equivalent settled material gain.
  Promotion suffixes label the resulting forking piece without changing `ReplayedMove`, replayed moves must match the FEN mover color, and mate facts take precedence while incomplete or ambiguous replays return nil.
  Target ordering is descending value then square, and all 55 real-fixture plies were scanned with zero fires.
  Fork facts do not change `KeyMomentSelector` priority, ChessCore has 34 tests, and AnalysisKit has 145 tests across 6 suites after this correction.
  The primitive is committed as `0da2ec7` and the detector/report integration as `1c40699` on `fork-detector-p4.2`.

- **Move-quality repair completed and verified against real fixtures (P4.2 slice).**
  Full narrative in `devlogs/2026-08-24-move-quality.md`.
  Re-verified the backlog premise claiming `[%clk]` time data was already parsed: confirmed false across all packages, with no clock parsing in `ChessComKit`, `ChessCore`, `AnalysisKit`, or `App`.
  Added `MoveQualityFact` in `Facts.swift` and `ThemeDetector.moveQuality(input:ply:)` in `ThemeDetector.swift`.
  `MoveQualityFact` is composed from replayed capture, check, checkmate, typed piece identity, castling state, and original-queen state.
  `ThemeDetector.moveQuality(input:ply:)` closes the complete historical fact on missing, malformed, illegal, wrong-colored, or board-inconsistent history.
  Every prior and current UCI is replayed through `ChessGame.replayLine` and checked against the FEN side, `ReportInput.moverIsWhite(atPly:)`, tracked source identity, and stored boards.
  FEN validation requires exactly six fields, a nonnegative halfmove clock, and a positive fullmove number; replay comparison checks all six fields with only the documented persisted en-passant normalization and narrow ChessCore en-passant halfmove correction.
  The semantic halfmove clock for a real en-passant capture remains `0`; the correction accepts only ChessCore's observed replay value of `1` against that expected `0`.
  En-passant removal is limited to a pawn diagonal capture onto an empty destination, castling updates rook identity, and promotion resets the promoted piece's pedagogical move count.
  Redevelopment uses the pre-move FEN fullmove number through fullmove 10, and early queen requires the original queen leaving `d1` or `d8` before fullmove 5.
  `KeyMomentSelector` is unchanged, while `ReportText` and typed `CoachFactsPayload.moveQuality` expose deterministic neutral observations with backward-compatible decoding.
  Scanned all 55 played UCIs from the 56 stored positions of the real Magnus Carlsen versus artin10862 fixture and hand-checked capture fires at plies 8, 9, 15, 18, 21, 22, 23, 24, 25, 31, 32, 43, 44, and 45, check fires at plies 43, 45, 49, 51, and 55 with the ply-55 check valid, and the sole redevelopment fire at ply 17.
  Packages/AnalysisKit: 153 tests across 6 suites. Packages/CoachKit: 76 tests across 8 suites. App suite: 179 tests across 34 suites.

- **Spaced repetition scheduler and persistence upgraded to ease-factor SM-2 model (P4.6).**
  Full narrative in `devlogs/2026-08-24-spaced-repetition.md`.
  Fixed the immediate same-session reappearance bug where incorrect/inaccurate answers set `dueAt = now`.
  Lapses now schedule at least 1 day in the future to train recall rather than recognition.
  Added append-only migration `v12_spacedRepetition` introducing `easeFactor: Double` (default 2.5), `lapseCount: Int` (default 0), and `intervalDays: Double` (default 0.0) on `trainingCard`.
  Updated `DeterministicReviewScheduler` with an ease-factor SM-2 algorithm tailored to Chessanto's four outcome grades.
  `.strong` recalls increment `consecutiveSuccesses`, grow `easeFactor` by +0.15, follow the early ladder (3d -> 7d), and scale intervals by `easeFactor` upon graduation at 3 consecutive successes up to an asymptotic 180-day maximum.
  Lapses (`.incorrect`, `.inaccurate`) reset `consecutiveSuccesses` to 0, return `masteryState` to `learning`, decrement `easeFactor` by -0.2 (clamped at a 1.3 floor), increment `lapseCount`, and enforce a 1-day relearn interval with tighter post-lapse progression (1d -> 3d -> 3*ease).
  `lapseCount` dampens maximum interval ceilings for leeches via `max(30.0, 180.0 / (1.0 + 0.25 * Double(lapseCount)))`.
  `.playable` answers reset consecutive successes to 0 and set 1-day interval without changing `easeFactor` or `lapseCount`.
  Packages/Persistence: 44 tests across 2 suites (was 43). App suite: 178 tests across 34 suites (was 174).

- **Takeaways now produce concrete, verified insights (P4.3).**
  Full narrative in `devlogs/2026-08-24-takeaways.md`.
  `ReportBuilder.buildTakeaways` extended with two new rules: recurring ignored threats (2+ occurrences per player, naming the count and move numbers, backed by `IgnoredThreatFact`) and a general error-frequency summary (naming total errors, move counts, and error breakdown across inaccuracies, mistakes, blunders, and missed wins from `whiteClassificationCounts`/`blackClassificationCounts`).
  Takeaways are prioritized deterministically: decisive tactical moments (missed/allowed forced mates) > recurring tactical blindspots (punishments, ignored threats) > opening deviations leading to disadvantage > general error frequencies > clean-game/no-pattern fallback.
  The real Carlsen fixture report now surfaces concrete error-frequency takeaways for both players (`artin10862 made 2 errors across 24 scored moves (1 inaccuracy, 1 blunder).`, `MagnusCarlsen made 1 error across 26 scored moves (1 inaccuracy).`) instead of the empty fallback.
  Packages/AnalysisKit: 126 tests across 6 suites (was 123). App suite: 174 tests across 34 suites at the time this branch was written (both branches ran in parallel from the same starting point; see the combined counts after this merge below).

- **Coach entry points clarity is implemented (P2.5).**
  Full narrative in `devlogs/2026-08-24-coach-entry-points.md`.
  Live diagnosis verified the backlog finding: toggling the Coach open via the header toggle retained stale pins from previous context-menu or button actions rather than following the board, the caption line was the sole differentiator between modes, and neither the scoresheet nor the report indicated which move the Coach was talking about.
  In `ChatView`, replaced the understated single caption line with two distinct, warm-neutral mode banners.
  Following mode features a clear status header ("FOLLOWING BOARD"), live position subtitle, descriptive helper text ("Questions and suggestions track the board move by move."), and an explicit "Pin position" button.
  Pinned mode features a warm-brass bordered callout card with a bold "PINNED POSITION" brass badge, the pinned move label, an explicit "Follow board" button to unpin, and when the board scrubs away, a live delta note ("Board is at Move Y") paired with a "View pinned move" jump button.
  Opening Coach via the header toggle now unpins (`unpinChat()`), ensuring the top toggle always delivers the promised "following the board" behavior.
  Move rows in `MoveListView` and key-moment cards in `GameReportView` now render persistent brass pin badges (`pin.fill`) and updated accessibility announcements ("pinned in Coach") on whatever move is currently pinned.
  Action copy was standardized to "Ask Coach about this move" in `MoveListView` and "Ask Coach about this moment" in `GameReportView`.
  Stayed strictly within the warm-neutral and brass design system; `Packages/AnalysisKit` and `Packages/CoachKit` were untouched.
  App test suite: 175 tests across 34 suites (up from 174, all green).

- **Native QA of the four unverified board behaviors: drag and drop confirmed live.**
  Full narrative in `devlogs/2026-08-24-board-qa.md`.
  Screen capture and window compositing were refused by the OS in this non-interactive agent environment (`could not create image from window`), so verification fell back to direct AX-tree and synthesized event introspection.
  Live database safety was strictly observed: backed up, executed all QA against a disposable copy under both required opt-in environment variables, and confirmed the live database remained untouched afterward (SHA-256 `173a3693267582696c9ce2415d83cf6d3e158089fab9116d6fe550a5ca72c133`, clean integrity check).
  **Drag and drop was verified live** using `scripts/axdrag.swift` across multiple real moves (1. e4, 1... d6, 2. d4, 2... Nf6); piece positions updated correctly in the live app and all 64 `square-<algebraic>` accessibility identifiers survived intact - this is the first time in three sessions this has been observed running rather than only unit-tested.
  Right-drag event routing via `RightDragCatcher`'s AppKit layer was verified with hit-testing separation (left clicks pass through to square buttons, right clicks/drags claimed by catcher), though the drawn arrow/circle shapes themselves remain visually unverified.
  The arrival animation's timing and the coordinate labels' rendered point size remain unverified - both are inherently visual and the AX tree exposes neither frame-by-frame rendering nor rendered font size, and this environment still cannot composite a window for a screenshot.
  No source bugs were found; only the QA scripts themselves were hardened. App test suite: 170 tests across 34 suites (unchanged, all green).

- **Priority 5's small UI details batch is implemented (8 of 8 items).**
  Full narrative in `devlogs/2026-08-24-ui-polish.md`.
  Classification chips no longer wrap mid-word (`.lineLimit(1)` + `.fixedSize`); a collapsible legend for all 10 classification marks was added to the Game Audit card, sourcing its copy from `ChessGlossary.gloss(for:)` rather than new prose; accuracy now renders with a percent sign and marks the user's own side ("White (You) 93.8%") via a new `AccuracySummaryFormatter`; sidebar rows with no username render "White won"/"Black won"/"Draw" instead of raw "1-0" notation; `LinesPanelView` separates inspecting a line (hover) from adopting it as a variation (an explicit branch button) instead of adopting on click; eval-graph key-moment dots gained a real 24x24pt hit target; the eval bar's win-probability-vs-centipawn scale mismatch is now explained via tooltip/accessibility text rather than resolved by unifying the two (a deliberate choice, both currencies are kept); the disabled "Practice positions" button now explains why.
  Stayed entirely in the App layer; `Packages/AnalysisKit` and `Packages/CoachKit` untouched.
  App test suite: 174 tests across 34 suites (up from 170).

- **The ignored-threat detector is implemented (P4.2 slice).**
  Full narrative in `devlogs/2026-08-24.md`.
  `ThemeDetector.ignoredThreat(input:ply:)` identifies when the mover ignored a concrete, pre-existing threat from the opponent (an immediate checkmate or a capture winning material) and the opponent executed it on the very next move.
  Operational definition stays strictly within stored board replay: replays opponent's played move at ply `p + 1` from the post-move position, flips the active color in the pre-move position (`input.plies[p - 1].fen`) to verify the exact move was already legal and achieved the same result before the mover moved, and calculates settled net material gain using `ChessGame.hasLegalMove` and piece values.
  An ignored threat attaches as an audited `IgnoredThreatFact` on `KeyMoment` and renders directly in `ReportText` across all registers ("This ignored the threat of checkmate: Qxf7#", "This ignored the threat to the bishop on c5: Bxc5 winning the bishop").
  When an ignored threat explains the loss of an already-hanging piece on square X, `ReportText` renders `ignoredThreat` and suppresses the redundant `punishment` sentence to prevent duplicating the same square and capture in one summary.
  `KeyMomentSelector`'s `prefersNameableConsequences` was extended to treat `IgnoredThreatFact` as a nameable consequence alongside punishment/missedMate/allowedMate.
  Scanned all 55 plies of the real Carlsen fixture game by hand: 0 fires, confirmed correct as all captures in that game were immediate equal trades, recaptures, or new hanging pieces created on that move. All golden report fixtures pass unmodified.
  Packages/AnalysisKit: 123 tests across 6 suites (was 105). App suite: 170 tests across 34 suites (unchanged).
  This and the board-QA and UI-polish sessions above ran in parallel, in separate git worktrees, and were integrated by hand afterward - see this repository's commit history around 2026-08-24 for the merge.

## Current state (2026-08-22)

- **`MoveClassification.brilliant` is implemented (P1.6 + P4.4): sacrifice detection.**
  Full narrative in `devlogs/2026-08-22.md`.
  `BrilliancyDetector.isBrilliant(input:ply:)` requires all five: the engine's own top choice, still 75%+ winning immediately after, a 10-point uniqueness margin over the engine's second choice (the honest proxy for "this was a find" that stored analysis can actually support), not a same-square recapture, and a settled material deficit of 3+ pawns-equivalent once the sacrifice is actually accepted - measured at the longest even-length prefix of the replayed line, mirroring `ThemeDetector.punishment`'s own rule.
  Detection lives inside `ClassificationContext.forGame`, alongside the existing book/forced-move detection, so the Report, the scoresheet, and the phone companion see identical brilliant assignments automatically rather than needing separate wiring at each of the three real call sites.
  **A first implementation attempt produced a real false positive on the committed Carlsen fixture** - checking material only at k=2 and k=4 of the replayed line caught a transient dip mid-exchange (a rook offered on move 55 that nets White a queen for a rook once fully settled) and mislabeled a winning combination as a sacrifice. Caught by doing exactly what the design's own author flagged as the one pre-ship check worth doing: running the detector over the real fixture corpus and reading every fire by hand. Fixed by reading the settled position instead of a fixed early window; confirmed zero false positives remain in the fixture corpus.
  Deliberately narrow: exchange sacrifices and pawn sacrifices do not qualify. No depth-dependent re-verification, no beauty scoring, no `KeyMomentSelector` or `FactAuditor` wiring this session.
  Packages/AnalysisKit: 105 tests across 6 suites (was 90). App suite: 170 tests across 34 suites (unchanged, no App-layer change - `.brilliant`'s color, glossary entry, and Coach headline were all already written in a prior session and needed no touching).

- **Teaching level now does real work, and beginner prose dropped percentages for plain language (P4.1 + P4.7).**
  Full narrative in `devlogs/2026-08-21.md`.
  `RatingRegister` moved from CoachKit to AnalysisKit (CoachKit keeps a `typealias`) so `ReportBuilder`/`KeyMomentSelector`/`ReportText` can read it, not just one LLM prompt sentence.
  Beginner reports show 4 key moments instead of 8, prefer moments with a concrete consequence (a punishment, missed mate, or allowed mate) when the cap forces a choice, truncate better-lines to 2 plies, and render qualitative prose ("makes things worse for you: White is winning now") instead of percentages or eval-label numerals.
  No material figure is ever derived from a win-probability swing - only `PunishmentFact`, which is already audited, licenses material language.
  `ThemeDetector`'s principal variation is never truncated at detection time, only at render time, so `FactAuditor` keeps verifying the same fact the detector produced.
  Every existing caller of `ReportBuilder.build`/`KeyMomentSelector.selectPlies` defaults to `.advanced` and is byte-identical to before, proved by the pre-existing golden fixture test passing unmodified plus a new beginner golden fixture.
  Also fixed: the eval-graph hover readout said "Ply 27" for everyone; it now reads "14... 63% for White".
  `GameReportView` and `GameReplayView` each carried their own hand-rolled, independently-drifted key-moment summary sentence; both are deleted in favor of the one canonical `ReportText.momentSummary`.
  Practice feedback said "Engine loss: 140 centipawns"; it now says "About 1.4 pawns worse than the best move."
  `ChessGlossary` gained `match(in:)` (term plus gloss), and beginner key-moment rows show one plain-language footnote when a known term appears in the summary.
  Design was consulted with an Opus advisor given the cross-package layering question (AnalysisKit cannot depend on CoachKit) and the pedagogical judgment calls (exact thresholds, what "nameable consequence" means operationally, whether to derive material figures from probability - the advisor's answer was no, and said why).
  Packages/AnalysisKit: 90 tests across 6 suites (was 29). Packages/CoachKit: 74 tests across 8 suites (unchanged). App suite: 170 tests across 34 suites (was 159 across 32).
  **Not done this session:** native QA of the rendered beginner report in the real app - the golden-fixture tests prove the text is exactly what was designed, but nobody has looked at the beginner register live in a window yet.
  Also not wired this session, deliberately: `PortableReportAssembler`, `DashboardView`, `PlayerBriefView`, `MacGameAnalysisBackend` still build reports at the `.advanced` default regardless of the viewer's actual register.

- **Finished the rest of Priority 2's keyboard/window items (P2.6) and the onboarding-to-fetch handoff (P2.2), committed at the start of this session having been left uncommitted by a prior one.**
  `KeyMomentNavigator` walks a report's key moments in ply order without wrapping; a new Game menu (Next/Previous Move, Next/Previous Key Moment, Play/Pause Line, Flip Board, Analyze) works regardless of which view has focus.
  `coachDockWidthThreshold` was comparing the window's width against a quantity measured from the detail pane, so the Coach panel could never dock on a 13-inch laptop; corrected from 1100 to 960.
  Onboarding now reports whether the user confirmed a chess.com account so the app can route straight into fetching games instead of landing on an empty register.
  App suite: 159 tests across 32 suites (was 154 across 31) before the P4.1/P4.7 work above added more.

## Current state (2026-07-30)

- **Priority 3 of the product review is implemented (2026-07-30): the board.**
  Full narrative in `devlogs/2026-07-30.md` under "Priority 3: the board".
  - **The promotion bug was real but not where the review placed it.** The evaluator already handled `b7b8q` correctly; the UI could only ever produce a square pair.
    Reproducing that square pair found the worse half: `replayLine(fromUCI: ["b7b8"])` returned a position with **a white pawn standing on b8**, and that illegal position was being sent to Stockfish to be scored.
    `ChessGame.replayLine` now stops at a back-rank pawn move that names no promotion piece, rather than leaving an illegal position or inventing a queen.
  - **`BoardInteraction` is the single select-then-move state machine**, replacing the two drifting copies in `GameReplayView` and `PracticeSessionViewModel`.
    It is a pure value type; the board's knowledge arrives per call through a `Context` of closures.
    `BoardInteraction.Move.uci` is the one place a promotion becomes five characters.
    This was built before the promotion picker rather than after, so the picker only had to be written once.
  - **The promotion picker** is an in-board column of the four pieces on the promotion file, using the real cburnett artwork, over a dismissing scrim. Underpromotion is reachable for the first time.
  - **Drag and drop** runs as a `simultaneousGesture` alongside the per-square buttons, so tap-to-move survives as the accessible path and all 64 `square-<algebraic>` identifiers the QA scripts drive are intact. 4pt threshold.
  - **Animation** moves the arriving piece by animating a scalar inside the piece layer, never the board's geometry, so the column cannot reflow and resize the board. 180ms ease-out, skipped under Reduce Motion.
  - **Sounds** are synthesized by `scripts/generate-sounds.py`, so no third-party licence rides alongside the GPLv3 build. `BoardSounds.isEnabled` starts false until `GameLibrary` has read the stored preference. New `v10_boardSounds` migration and a General settings toggle, on by default.
  - **Coordinates** went 16% to 22% of the square with an 11pt floor and bold weight, and are now `accessibilityHidden` since each square's button already carries its name.
  - **Annotations are deliberately not persisted.** Right-drag arrows and circles clear when the position changes, as on lichess and chess.com. Persisting them needs a position-keyed table plus a lifecycle answer for re-analysis and variation deletion, which is its own session. Right-drag comes from `RightDragCatcher`, which claims hit tests only during right-mouse events so left clicks pass through.
  - **A pre-existing data-safety defect was found and fixed.** `xcodebuild test` on the app scheme launches the real app as its test host, which reaches `GameStore.defaultStore()` during SwiftUI startup; the `XCTestConfigurationFilePath` guard did not catch it, so the test run applied `v10_boardSounds` to the **live** database.
    Confirmed with a throwaway probe migration, fixed in `GameStore.isRunningUnderTests` (loaded XCTest runtime, loaded `.xctest` bundle, SwiftPM's `swiftpm-testing-helper`), and re-probed to confirm the live database is now untouched.
    Harmless until now only because no earlier session added a migration while testing.
  - Suites: app 138 across 29 (was 107 across 27), ChessCore 29, AnalysisKit 78, CoachKit 74, EngineKit 1, Persistence 43, ChessComKit 4, CompanionKit 32.
  - Native QA against an isolated copy confirmed the picker, `axb8=N` underpromotion persisting to the variation table, cancel playing nothing, an ordinary `Nf3` through the same machine, the 64 square identifiers, the bundled sounds, and the settings toggle persisting.
    The QA copy was deleted; the live database passes `PRAGMA integrity_check` with its 15 games, 668 analysis rows, 10 cards and 75 variations at SHA-256 `173a3693267582696c9ce2415d83cf6d3e158089fab9116d6fe550a5ca72c133`.
    That differs from the `e9947b…` recorded earlier today only by the `v10_boardSounds` column, which the app applies on next launch regardless.
  - **Not verified in the real app: drag and drop, right-drag annotations, the arrival animation, and coordinate sizing.**
    All four need a composited window; the display stopped compositing partway through QA (every Chessanto window including its menu bar reported `onscreen=false` while unlocked and on console) and could not be woken from the agent environment.
    `scripts/axdrag.swift` is committed for exactly this.
  - **Found, not fixed:** `libc++abi: … mutex lock failed` prints after roughly half of app test runs, always *after* the run reports success. Exit code was 0 and `** TEST SUCCEEDED **` in all 8 sampled runs. Static-destruction ordering in the vendored Stockfish, not a flaky test.

- **Priority 1 of the product review is implemented (2026-07-30): analysis correctness.**
  - Commits `6939582`, `abf0876`, `43483da`, `b11eb61`. Full narrative in `devlogs/2026-07-30.md`.
  - **Analysis is budgeted by depth, not movetime.** Presets are depth 12/16/20 with 5s/20s/60s ceilings.
    The numbers are measured, not chosen: depth 18 with a 4s ceiling reached 18 on only 14% of a 50-position game, with the ceiling binding as the norm, which is the machine-dependent spread the scheme exists to remove.
    After retuning, 41 of 50 positions reached depth 16 and 9 reached 15, against 7 to 14 before any of this work.
    Do not combine depth and movetime in one UCI `go` - Stockfish reports one iteration fewer - so the ceiling is enforced with an explicit `stop`.
  - **Analysis reuse now requires the stored depth to meet the requested depth**, not just a matching preset label, and the UI reports the shallowest depth actually stored rather than the preset's nominal figure.
    Without this, rows written when "standard" meant 350ms would be kept under a preset that now promises a depth; the real library had a game stored as "standard" whose rank-one depths ran 8 to 17.
  - **`.book` and `.forced` classifications** exempt theory and single-legal-move plies from scoring while still showing them.
    `ClassificationContext.forGame` is the single source of truth, so the phone companion cannot label a move "Best" that the Mac calls "Book".
  - **Punishment facts are decided by the board**, not by the shape of the principal variation: replay the capture, then ask whether the piece can be taken back.
    Ordinary trades no longer render as hanging pieces or feed the practice themes and Player Brief motifs.
  - **Key moments are filtered to the user's own side** when the report knows who the user is, so the register and the practice card count stop disagreeing.
  - **Accuracy follows Lichess's volatility-weighted plus harmonic combination**, fetched from `lichess-org/lila` rather than reconstructed from memory.
    Fixture game: White 94 to 90, Black 91 to 75.
  - **Training grading searches at the card's own reference depth**, instead of comparing a 500ms search against a stored deep one.
  - All suites pass: ChessCore 26, AnalysisKit 78, CoachKit 74, EngineKit 1, Persistence 41, ChessComKit 4, CompanionKit 32, app 107 across 27 suites, plus `engine-smoke` against live Stockfish.
  - Native end-to-end QA ran the Release build against an isolated copy of the library database and confirmed the Pirc game's first four plies read `Book`, the header reports the real stored depth, and a fresh 50-position analysis completes in about 260 seconds.
    The live database was verified byte-identical afterwards at SHA-256 `e9947babbf767d66d5164d28b86af9c843f6973231b0351bb82e84d5921b027b`.
  - **Two claims in the review document below were disproved while implementing them.** They are corrected here; the bootstrap document is superseded on these two points only.
    - Moves made in an already-mated position do *not* flood the report with blunders. The mover's win probability is pinned at 0, so the drop is 0 and they grade `.excellent`. The real defect in that area was narrower: forced moves graded `.best`.
    - A depth-`N` search reporting depth `N-1` is *not* a delivery race. `engine-smoke` drains everything still in flight and the depth never improves, so the line is never emitted and no consumer-side wait can recover it. The ±1 ply is inherent to Stockfish under MultiPV with multiple threads. An earlier grace-window fix built on the wrong diagnosis was removed.
  - **Not done from Priority 1:** `brilliant` is still assigned nowhere. It is a feature rather than a correctness fix and belongs with the teaching-depth work.
  - **Found while verifying, not fixed:** one game in the library fails to parse with `ChessKit.PGNParser.Error error 2`, and its modal "Load error" alert silently swallows clicks on the window beneath it.

- **Player-lens product review complete (2026-07-30). Review only, no code changed.**
  - Reviewed the whole product twice, once as an intermediate 1800-rated club player and once as a 300 to 600 rated beginner, covering flow, UI, UX, chess theory, teaching method, analysis correctness, learning science, and attention design.
  - Findings and a prioritized plan are in `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`.
    Session narrative and method are in `devlogs/2026-07-30.md`.
    Nothing in either document has been implemented.
  - **The highest-leverage defect is analysis depth.**
    `EngineService.swift:21-27` uses movetime (standard is 350ms per position) where the classification thresholds need to distinguish a 9-point win-probability drop from an 11-point one.
    That is below the evaluation noise floor in sharp positions, and movetime is not reproducible, so re-analysis churns key moments and the spaced-repetition queue.
    Every teaching surface in the app is downstream of these numbers, so this should land before any other work.
  - Four correctness holes compound it: no book move exemption (despite `deepestBookPly` already being computed), no forced-move or already-decided-position handling (`WinProbability.fromMate` returns a hard 0 or 100, so every move after an opponent's forced mate reads as a blunder), `Accuracy.average` being a plain arithmetic mean where Lichess uses a volatility-weighted and harmonic combination, and `ThemeDetector.punishment` firing on any capture-first PV so ordinary trades render as hanging pieces.
    That last false fact propagates into practice card themes, Player Brief motifs, and the takeaway generator.
  - `MoveClassification.brilliant` is still assigned nowhere despite having a color, a `!!` mark, a glossary entry, and a coach headline.
  - `KeyMomentSelector` does not filter to the user's side, so the register and the practice card count disagree.
  - Flow: every aggregate surface needs many analyzed games, and analysis is manual one game at a time with no batch action.
    Onboarding collects a chess.com username and then lands on an empty window.
    Player Brief is hard-gated behind chess.com confirmation, so PGN-only users can never see their progress.
  - Board: no drag and drop, no piece animation, no sounds, no annotation arrows.
    `playMove` auto-queens with no picker, and a promotion practice card is probably ungradeable (four-character UCI cannot match a five-character `bestMoveUCI`).
    Reproduce that one before fixing.
  - The teaching level setting is cosmetic: `RatingRegister` injects one sentence into the LLM prompt and changes no thresholds, moment counts, PV lengths, cards, or grading.
  - Environment note: sandboxed screen capture was refused by the OS, so visual findings are grounded in the pre-2026-07-19 QA screenshots and are all marked as needing re-verification against a current build.
  - The live database was backed up before launching the Release build and verified byte-identical afterward at SHA-256 `e9947babbf767d66d5164d28b86af9c843f6973231b0351bb82e84d5921b027b`.

- **User-selectable move notation complete (2026-07-19).**
  - General Settings now lets the user choose standard SAN such as `Nf3` or full piece names such as `Knight f3`.
  - The choice is persisted by the append-only `v8_moveNotationStyle` migration and is applied consistently to the move ledger, Report, Practice, engine lines, line playback, the comic Coach, and Coach responses.
  - Full-name mode uses a one-move-per-row ledger so expanded moves remain readable, while standard mode keeps the compact two-column scoresheet.
  - This is a presentation-only boundary.
    Canonical SAN in PGNs, analysis, variations, engine input, Coach grounding, and user-authored chat is never rewritten.
  - VoiceOver receives semantic move names in both visual modes.
  - The complete app suite passes with 98 tests across 23 suites, the persistence migration and round-trip tests pass, the universal Release build passes, and native QA covered both notation modes plus automatic better-line playback.
  - Native QA used the isolated database at `~/Library/Containers/com.chessanto.app/Data/tmp/notation-choice-final-20260719-1752/chessanto.sqlite`.
    The live database was restored from its preserved backup, passed `PRAGMA integrity_check`, and matches that backup at SHA-256 `5112ee500dd1c249bad5ccca9ea61e2681176141572c9051dd765457c0bc976e`.

- **UI/UX clarity phase 2 complete (2026-07-19): synchronized Coach stage and playable analysis.**
  - `LinePreviewController` is a small, DB-free replay module built on `ChessGame.replayLine`.
    It cannot access `GameStore`, the variation tree, or `adoptLine`.
  - Report key moments now start the full stored rank-1 line automatically on the board.
    Report also offers a separate read-only playback of the moves that actually followed in the game.
  - Practice feedback and Reveal start the full stored better line automatically.
    Nothing is previewed before the learner has answered or revealed the card.
  - Both surfaces retain manual pause, replay, previous, next, jump-to-start, jump-to-end, and Done controls.
  - The narrow Review and Practice panes no longer print long Coach paragraphs.
    A purpose-built comic Coach portrait and speech bubble sit with the board and update with each demonstrated SAN move.
  - The bubble uses verified local Coach narration when available and otherwise labels deterministic report text as `Engine verified`.
  - The original phase 2 plan's manual-only and sentence-fragment presentation decisions were superseded by the user's explicit autoplay and comic-stage direction.
  - App coverage increased from 75 tests across 19 suites to 91 tests across 22 suites.
  - Native Release QA exercised better-line autoplay in Review and Practice plus the real played continuation.
    The QA database had one variation row before and after, and the protected live database was restored byte-for-byte from its preserved backup after QA.

- **M1 complete.** App builds, all tests pass, and the acceptance criteria in
  `PLAN.md` are met: a real chess.com PGN (fetched live from the public API,
  with `[%clk]` comments and both castling sides) imports through the actual
  UI, persists across quit/relaunch, and steps forward through the game move
  by move with the board and move list updating correctly.
- **M2 complete (2026-07-17): engine integration and move classification.**
  Followed `handoffs/NEXT-SESSION-M2.md` step by step; every step's
  verification passed. What's new:
  - `Persistence`: `AnalysisRecord` + `GameStore` analysis CRUD (async,
    delete-first replacement per ply - this is also crash/cancel resume).
  - `EngineKit`: `AnalysisEngine.go(movetimeMilliseconds:)`; `setPosition`
    now waits for an in-flight search's terminating `bestmove` before
    bumping the generation, closing the stale-tag window the prep session
    flagged. `engine-smoke` still exits 0 with this extended.
  - `ChessCore`: `ChessGame.uciMove(at:)` (chesskit-swift's `Move.lan` was
    already exact UCI) and `ChessGame.sanLine(fromUCI:startingFEN:)` for
    turning an engine PV back into SAN for the lines panel.
  - `AnalysisKit`: `WinProbability`, `MoveClassifier`, `Accuracy` - pure,
    engine/DB-free, exactly the Lichess-derived formulas fixed in the prep
    plan. 17 tests including the worked example and both perspectives.
  - `App`: `EngineService` (`@MainActor`, one shared `AnalysisEngine`,
    live infinite analysis and batch analysis mutually exclusive), wired
    into `GameReplayView` - eval bar, eval graph, move-list classification
    badges, Analyze/Re-analyze toolbar with quality picker and cancellable
    progress, and a display-only MultiPV lines panel. Live analysis follows
    ply changes (200ms debounced) and only trusts the engine's live eval
    when its FEN matches the currently displayed ply - cached DB values
    otherwise, so scrubbing never shows a stale eval.
  - Real E2E verification (Release build, driven via `osascript`/System
    Events accessibility introspection since Screen Recording permission
    wasn't available in this environment - see the 2026-07-17 devlog for
    the full method): Analyze on a real 55-ply chess.com game finished in
    a few seconds, DB rows had sane white-perspective evals, cache-instant
    reload was confirmed (accuracy + Re-analyze button appear before any
    engine interaction on relaunch), and stepping through plies showed the
    eval bar updating per-position rather than carrying over a stale value.
- **M3 complete (2026-07-17): Exploration Mode.** Followed
  `handoffs/NEXT-SESSION-M3.md`'s bootstrap; every accept-criterion step
  verified E2E through the built app. What's new:
  - `ChessCore`: `allIndices`, `isMainline(_:)`, `parent(of:)`,
    `mainlineAncestor(of:)` - tree navigation built on chesskit-swift's
    public API only, since `MoveTree` exposes no children/delete API.
    `playMove(from:to:at:)` auto-promotes (default queen); `PromotionKind`
    and `isPromotion(from:to:at:)` added for a future picker.
  - `Persistence`: `VariationRecord` (parent-pointer forest: root rows
    reference a mainline `parentPlyIndex`, other rows reference the
    preceding row via `parentVariationId`) + `GameStore.insertVariationMove
    /variations/deleteVariation` - delete cascades to the whole subtree
    via the schema's existing FK, tested with a 3-deep chain.
  - `App`: `GameReplayViewModel` rebuilds the variation tree in memory on
    load (replaying persisted rows onto `chessGame`) and persists each new
    move immediately as it's played (same crash-safety pattern as M2's
    analysis). `BoardView` squares are real tappable `Button`s (click to
    select, click a highlighted legal destination to play) - this also
    fixed a real accessibility gap, see devlog. `MoveListView` renders the
    variation tree (nested branches, delete-subtree, "back to game").
    `LinesPanelView` lines are clickable and adopt as a new variation.
  - Real E2E (same `osascript`/System Events method as M2, with one
    correction: raw pixel clicks are blocked in this sandbox, only
    AX-element-reference clicks work): played a 5-move variation plus a
    nested sub-variation via real board clicks, confirmed the DB rows and
    parent-pointer shape at each step, watched the live eval update for
    the explored position, deleted the sub-variation via its UI trash
    button, quit/relaunched, and confirmed the remaining 5-move variation
    reloaded correctly into both the DB and the live move list.
  - Known gaps (see devlog for detail): promote/collapse controls not
    built (only delete); no promotion picker UI; replaying a move that
    happens to equal the real mainline continuation still creates a
    redundant variation branch instead of being recognized; the
    lines-panel adopt buttons' accessibility exposure is unconfirmed.
- **M4 complete (2026-07-17): chess.com fetch.** Followed
  `handoffs/NEXT-SESSION-M4.md`'s bootstrap. What's new:
  - `ChessComKit` got real coverage: a fixture-based decode test (a
    trimmed real archive response) plus `chesscom-smoke`, a live
    executable (mirroring `EngineKit`'s `engine-smoke`) that round-trips
    `profile`/`archiveURLs`/`recentGames` against the real chess.com API.
  - `Persistence`: `UserProfileRecord` + `GameStore.userProfile()`/
    `saveUserProfile()` - the settings-storage question from the M4
    bootstrap resolved in favor of the existing `userProfile` table over
    `UserDefaults`, since M6 will need `ratingBand`/`coachModel`/
    `coachEnabled` there anyway.
  - `App`: `ChessComFetchView` - a sheet with username entry, fetch,
    a checkbox-selectable game list (already-imported games marked and
    disabled), and multi-select import via the existing
    `GameLibrary.importPGN(_:source:sourceURL:)` path. Wired to a new
    "Fetch from chess.com" toolbar button next to "Import PGN". Also
    fixed a real bug in `GameLibrary.alreadyImported(sourceURLs:)`,
    which ignored its parameter and returned every imported URL instead
    of intersecting with the games actually being shown.
  - Real E2E verification (same `osascript`/System Events method as
    M2/M3): fetched a real, very active chess.com account
    (`hikaru`, 991 games in the default 2-month window - which is also
    why the fetch view now defaults to *no* games pre-selected rather
    than "select all"), imported 5 games, confirmed via `sqlite3` they
    landed with the right `source`/`sourceURL`, quit/relaunched and
    confirmed both the username and all 6 games (1 original + 5 new)
    persisted, ran a full Analyze pass on one of the imported games (238
    analysis rows, accuracy `White 94.5 / Black 91.2` rendered
    correctly), and confirmed an invalid username surfaces the existing
    chess.com error alert cleanly rather than crashing.
  - Two real bugs found and logged (see the 2026-07-17 devlog's M4
    section for full detail, not fixed this session): one of the 5
    imported games fails to parse (`chesskit-swift`
    `invalidMove("Rb5")` on an otherwise ordinary game - a pre-existing
    parser edge case, not a chess.com-specific or M4 regression, and it
    already degrades correctly via the existing load-error alert); and
    the Analyze button has no "engine still starting" state, so clicking
    it before `EngineService.isStarted` flips true silently does
    nothing instead of showing a real error.
- Project layout: `project.yml` (XcodeGen spec, regenerate with
  `xcodegen generate` after adding/removing files - `Chessanto.xcodeproj` is
  gitignored, not committed), `App/` (SwiftUI app target, with an
  `Analysis/` subfolder for M2's engine/eval-bar/graph/lines-panel code),
  `Packages/` (ChessCore, EngineKit, AnalysisKit, CoachKit, ChessComKit,
  Persistence - each a local SPM package per `PLAN.md`'s architecture).
- Git repo initialized and pushed: https://github.com/WillisLiao/chessanto
  (branch `main`). Commit and push M2 work alongside these docs.
- **M5 complete (2026-07-17): rule-based coaching report.** Followed
  `handoffs/NEXT-SESSION-M5.md` step by step; every step's verification
  passed. What's new:
  - `ChessCore`: `ReplayedMove`, `ChessGame.replayLine(fromUCI:startingFEN:)`
    (generalizes `sanLine`, also returns check/mate flags, captures, and
    resulting FEN), `moveDetail(at:)`, `material(fen:)`, `epd(fromFEN:)`.
  - `AnalysisKit` (DB-free, ChessCore-only): a real lichess CC0 opening
    book (`OpeningBook`, 3,803 entries via `scripts/fetch-eco.sh`, indexed
    by replaying every line and keying on final-position EPD; ships a
    **precomputed** `eco-index.json` since replaying the raw dataset at
    launch measured ~7.5s, well past budget). The Facts/detector/report
    pipeline: `ReportInput`/`PlyRecord`/`RankedLine`,
    `EvalSwingFact`/`BetterMoveFact`/`PunishmentFact`/`MissedMateFact`/
    `AllowedMateFact`/`OpeningFact`, `ThemeDetector` (replay-based, never
    string-matching), `KeyMomentSelector`, `ReportBuilder`, `ReportText`
    (closed templates only), `FactAuditor` (independently re-derives and
    drops any fact that fails to match - the seed of M6's
    `CoachVerifier`). `EvalLabel` extracts eval-string formatting
    previously duplicated in `GameReplayViewModel`.
  - `App`: fixed the M4-logged "Analyze silently no-ops before the engine
    finishes starting" bug (a real "Starting engine..." toolbar state).
    `GameReplayViewModel` retains full per-ply ranked rows and builds a
    `GameReport` once analyzed; the right pane is now a "Moves"/"Report"
    segmented tab; `GameReportView` renders it with real, board-jumping
    `Button`s for each key moment.
  - Two real bugs found by the E2E pass and fixed (see the 2026-07-17
    devlog's M5 section for full detail): `ContentView`'s detail pane
    wasn't recreated when switching between two already-selected games
    (missing `.id(game.id)` - the `if let` branch never changes identity),
    so the whole replay pane (including the new Report tab) silently kept
    showing the *previous* game; and the Takeaways section falsely
    claimed "a clean game" whenever no *aggregate* pattern fired, even on
    games with real, individually-flagged blunders.
  - Real E2E verification (Release build, `osascript`/System Events):
    every claim in all 3 key moments of the real 55-ply fixture game was
    manually cross-checked against the actual `sqlite3` analysis rows and
    hand-computed win-probability math - zero false statements found. A
    committed golden test (`real-fixture-game-report-input.json` +
    `real-fixture-game-golden-report.txt`, both real chess.com/Stockfish
    data) locks this in.
  - Known gaps for a future session (not blocking): the Report tab's
    key-moment `Button`s are fully clickable via AX-element reference
    (role `AXButton`, click-to-jump confirmed working) but their text
    isn't exposed through any AX attribute this session could find,
    unlike `MoveListView`'s structurally similar buttons - possibly
    related to `MoveListView` living inside a `List`/`AXOutline` and the
    report's key moments being a bare `ScrollView`/`VStack`, but
    unconfirmed. The new "Starting engine..." toolbar state is
    structurally correct but wasn't caught live in automation (the
    Release-build engine now starts faster than System Events can query
    the window after launch).
- **M6 prep complete (2026-07-17): live Ollama verification and execution
  plan.** A planning session (no app code changes) verified everything M6
  will code against and rewrote `handoffs/NEXT-SESSION-M6.md` as a
  self-contained execution plan (verified facts with real curl
  transcripts, fixed design decisions, 9 build steps each with a
  verification gate). Highlights, full detail in the devlog's "M6 prep"
  section and the plan itself:
  - Live-verified Ollama 0.31.2's real API end to end: tags/ps/show
    (including the `capabilities` array the picker needs for tool
    support), chat streaming NDJSON, thinking-model handling (`qwen3`
    emits a separate `message.thinking` field; `think:false` disables),
    tool calling (arguments arrive as a JSON object; streamed tool calls
    arrive whole in one chunk; round-trip via `role:"tool"` messages
    verified), pull-with-progress (a real mid-stream `{"error":"503: "}`
    inside an HTTP 200 stream was observed live, and retry resumes), and
    the 4096-default-context trap (`options.num_ctx` is mandatory).
  - All PLAN.md model tags resolve in the registry with real sizes - but
    **gemma3 has no tools capability**, so the 32GB alternative becomes
    `qwen2.5:32b` (19.9 GB, tools). `qwen3:0.6b` (~0.5 GB, tools +
    thinking) was pulled and stays installed as the dev/harness model.
  - Scratch-run against ChessCore proved SAN replay from arbitrary
    mid-game FENs works and exposed a real trap: `playMove(san:)` trusts
    `+`/`#` suffixes instead of deriving check state (bare `Qh5` on a
    mate reports `isCheckmate=false`; spurious `e4+` is echoed back).
    CoachVerifier's fixed pattern: SAN path for legality + UCI extraction
    only, then re-replay via `replayLine(fromUCI:)` for every board fact.
  - No schema work needed: `userProfile` has had `ratingBand`/
    `coachModel`/`coachEnabled` since the v1 migration, and
    `UserProfileRecord` already maps them. `project.yml` already carries
    `NSAllowsLocalNetworking` + the network-client entitlement, and the
    App target already links CoachKit.
- **M6 complete (2026-07-17): local LLM coach.** Followed
  `handoffs/NEXT-SESSION-M6.md` step by step; every step's verification
  gate passed. Full detail in the devlog's "M6 execution" section. What's
  new:
  - `CoachKit` is no longer a placeholder. `OllamaModels`/`OllamaClient`
    (native `/api/*` only, explicit `CodingKeys` throughout, a plain
    `Sendable` class rather than an actor), `CoachVerifier` (Layer 2's
    hard gate: regex token extraction, SAN-legality-then-UCI-re-replay
    per fact 15, PV-prefix or landed-on-known-anchor line verification,
    exact check/mate suffix matching, tolerance-based eval/mate/percentage
    checks, an at-most-once-per-response fresh-verification hook via
    `EngineToolExecutor`), `CoachPayloadBuilder`/`CoachPrompt` (Layer 1),
    `EngineToolExecutor`/`EngineToolResult` (Layer 3's protocol),
    `CoachNarrator` (the orchestrator: generate -> verify -> regenerate
    once -> fallback), `CoachModelCatalog` (the picker table). 40 tests,
    including a gate that runs the real M5 golden rule-based report text
    through `CoachVerifier` expecting zero violations.
  - `AnalysisKit`/`ChessCore`: `Codable` added to the Fact structs,
    `KeyMoment`, `ClassificationCount`, `MoveClassification`, `PieceKind`,
    `PieceColor` (additive); `ReportText.momentSummary(_:report:)`
    (public, reuses the existing private renderer) and
    `ChessGame.isValidFEN(_:)` added.
  - `App`: `EngineService.coachEvaluate` (the `EngineToolExecutor` impl,
    replay-validates args before touching the engine, refuses during
    batch analysis, stop/resume around live analysis like `analyze()`);
    `CoachService` (`@MainActor`, health checks, sequential per-game
    narration generation), `CoachSettingsView` (a real `Settings` scene:
    enable toggle, teaching level, Intel warning, Ollama guidance +
    recovery, installed-model picker with tool-capability badges,
    free-text pull with progress), `MachineProfile` (sysctl detection).
    `GameReplayViewModel` keeps `reportInput` alongside `report`;
    `GameReportView` triggers narration via `.task(id: viewModel.report)`
    and renders a labeled ("Coach" vs "Rule-based") text slot per key
    moment plus a summary section - the rule-based path is byte-identical
    when the coach is off.
  - `coach-grounding` (new CoachKit executable, `engine-smoke` precedent):
    a standalone `GroundingEngine` actor drives a real in-process
    Stockfish directly (duplicates `EngineScoreNormalizer`'s ~10 lines
    since it can't import the App target); runs the full narrate->verify
    loop against real Ollama + the real fixture, independently
    re-verifying every rendered "coach" text with a fresh context (not
    the in-generation tool-call anchors); also carries step 4's live
    "one legal + one illegal `evaluate()` call" gate. `swift run
    coach-grounding` exits 0; multiple live runs show the verifier
    genuinely firing (violations/fallbacks with `qwen3:0.6b`, zero leaks
    every time).
  - Real E2E verification (Release build, `osascript`/System Events, on
    the real `MagnusCarlsen vs artin10862` fixture game): real narration
    rendered for all 3 key moments + summary, every cited move/eval
    grounded (including one moment's `Ka2` getting grounded through the
    verifier's live fresh-verification tool call - Layer 3 confirmed
    working end to end in production); prose *reasoning* quality is
    often weak with this harness model, which is the documented,
    expected tradeoff - the architectural guarantee (no invented
    moves/evals) held in every rendered sentence, general commentary
    accuracy was never part of that guarantee. Killed Ollama outright:
    all moments/summary fell back to the exact M5 rule-based text,
    correctly labeled, no crash/hang. Restarted Ollama: Settings'
    "Check again" recovered live. Settings guidance states (no-Ollama,
    non-tools-model note via the locally-installed `llava:7b`, model
    recommendation matching this machine's real 16 GB) all verified via
    AX. `coach-grounding` + every package's `swift test` + the full
    `xcodebuild test` app suite all green.
  - Known limitations carried forward (not blocking, documented
    deliberate simplifications - see the plan's CoachVerifier design and
    the devlog): eval/mate/percentage claims are checked against a pool
    of known-good values rather than strictly tied to the specific cited
    line they follow, so a real number can occasionally be misattributed
    (never fabricated); the bare-square exemption occasionally exempts a
    genuine single-word move reference (e.g. a played move stated with no
    leading number marker) from verification rather than checking it;
    general prose/qualitative-claim accuracy (as opposed to moves/lines/
    evals) is explicitly out of scope for M6 v1 per PLAN.md's residual-risk
    note.
- **M7 prep complete (2026-07-17): chat mechanics verified live, execution
  plan written.** A prep-only session (no app code changes) read every
  source file M7 builds on in full, verified the new conversational
  mechanics against the live Ollama 0.31.2 server, scratch-ran the
  proposed-move precheck against real ChessCore, and rewrote
  `handoffs/NEXT-SESSION-M7.md` from a rough bootstrap into a
  self-contained execution plan (9 verified facts, fixed design decisions,
  10 build steps each with a verification gate). Highlights, full detail
  in the devlog's "M7 prep" section and the plan itself:
  - Live-verified: multi-turn chat history round-trips; tool calls fire
    with history present (and the model mangled its FEN argument again
    live - the replay-validation guard is load-bearing for chat too);
    concurrent requests are safe on Ollama's side, so the real hazard is
    `EngineService.searchOneShot`'s singleton collector state - the plan
    serializes `coachEvaluate` with a FIFO chain.
  - Scratch-run against real ChessCore found three precheck traps before
    any code: bare-square tokens ("take on d5", "knight on c6") must
    never be treated as move proposals, and number-marker chains
    ("24...Qd7") are game-history references that must skip the precheck.
  - The bootstrap's four open design questions are now fixed decisions:
    a `CoachChat` actor sharing `CoachNarrator`'s (made-internal) turn
    engine; a chat payload with context-block-on-FEN-change injection and
    a seed evaluation; in-code proposed-move validation before the LLM
    with a canned illegal-move short circuit; buffer-then-render replies
    (a documented deviation from PLAN.md's "Streaming responses" bullet,
    resolved by its own "nothing unverified renders" rule).
  - One schema change is planned (the first post-v1 migration): a
    nullable `chatMessage.source` column so the Coach/fallback honesty
    label survives relaunch.
- **M7 complete (2026-07-18): position chat.** Followed
  `handoffs/NEXT-SESSION-M7.md` step by step; every step's verification
  gate passed, including two real bugs found live and fixed before
  moving on. Full detail in the devlog's "M7" section. What's new:
  - `Persistence`: a `v2_chatMessageSource` migration (the first
    post-v1 migration) plus `ChatMessageRecord` and
    `GameStore.insertChatMessage`/`chatMessages`/`deleteChatMessages`.
  - `CoachKit`: `CoachVerifier.moveTokenChains(in:)` (public tokenizer
    exposure, `verify()` itself unchanged) and `ProposedLineCheck`
    (the precheck classifier: bare-square/history-reference/legal-
    proposal/illegal-proposal, built around the prep session's TRAP 1/
    TRAP 2 findings); `CoachChatContext`/`CoachChatPayload`/
    `CoachPayloadBuilder.chatPayload`/`CoachPrompt.chatSystemPrompt` etc;
    `CoachChat` (a `public actor`, the multi-turn analogue of
    `CoachNarrator` - precheck -> seed eval -> generate -> verify ->
    regenerate once -> fallback, history pruned to bare turns and capped
    at 12 messages, `CoachNarrator.runConversation` shared via a
    `private` -> `internal` refactor with all 7 of its own tests
    unmodified). 40 new CoachKit tests.
  - `App`: `EngineService.coachEvaluate` gets a FIFO chokepoint
    (`coachEvaluateTail`) so a narration tool call and a chat tool call
    can't clobber `searchOneShot`'s shared state - **the first attempt
    at this was wrong** (a placeholder-task chain that only waited for
    the previous placeholder, not the previous call's actual engine
    work, serializing nothing) and wasn't caught by any offline test;
    only the live concurrent-evaluate probe in `coach-grounding`
    deadlocked and surfaced it. `GameReplayViewModel.chatContext()`/
    `chatPositionLabel`; `CoachService` chat state
    (`chatMessages`/`isSendingChatMessage`/per-game cached `CoachChat`);
    a new `ChatView` (third `RightPaneTab` segment) - `List`-based
    message view, position chip, source captions, per-message jump
    buttons, starter chips, single-phase "Coach is thinking..."
    indicator (a documented scope-down - no real progress-reporting
    hook exists to back the plan's 3-phase design honestly), offline
    guidance state.
  - `coach-grounding` grew a chat section (legal/illegal/open-question
    turns plus the concurrent-evaluate probe) - this is what caught the
    FIFO bug above, and also caught a harness-side bug (independent
    re-verification was re-checking `.precheck` canned-template replies
    as if they were LLM prose, false-flagging the very token the
    template declines as an unverified citation) - both fixed, second
    run exits 0.
  - Real E2E verification (Release build, `osascript`/System Events, the
    real analyzed `MagnusCarlsen vs artin10862` fixture): found and fixed
    a real bug before functional testing could even start (Chat tab
    never triggered a health check, stuck on "Checking..." forever);
    then confirmed live - illegal-move precheck (instant, zero LLM
    calls), legal-move proposal (verified eval injected and cited,
    `source=coach`), variation-position chat (correct branch-ply
    `plyIndex` mapping), quit/relaunch persistence (14 messages
    round-tripped, jump buttons work), Clear chat, and the
    coach-disabled offline state. `coach-grounding` exits 0; all 160
    package tests plus the 10 app tests green throughout.
  - Known gaps for a future session (not blocking, all quality/UX/
    robustness, not safety - nothing unverified ever rendered in any
    live test): open-question tool-calling didn't clearly fire live with
    either `qwen3:0.6b` or a `qwen2.5-coder:7b` spot-check (no
    `qwen3:8b` on this machine); prose quality with non-frontier models
    is weak/repetitive (same documented M6 residual risk, not new);
    `List` produces a real `AXOutline`/`AXRow` structure (a genuine, if
    partial, improvement over `MoveListView`'s bare `ScrollView`) but
    row text/button labels still don't expose via `name` in this AX
    bridge, so the M5 AX gap isn't fully resolved; `OllamaClient` has no
    request timeout, so a genuinely-*unresponsive*-but-not-torn-down
    Ollama (simulated via `SIGSTOP`, as opposed to `kill -9` which this
    machine's Ollama.app auto-respawns too fast to observe) hangs chat
    indefinitely rather than falling back in a reasonable time - a
    pre-existing characteristic shared by M6's narration path, only now
    exercised by this specific failure mode.
- **M8 prep complete (2026-07-18): polish/packaging surface verified live,
  execution plan written.** A prep-only session (no app code changes) read
  every file M8 touches in full, overturned two carried-forward claims by
  measuring (OllamaClient's 300s timeout exists and fires at 301.0s
  against a frozen Ollama - the real fix is shorter differentiated
  timeouts; and the M5/M7 "List AX text gap" was the AppleScript bridge,
  not the app - full text is present in `AXDescription` via the raw AX
  API, so `scripts/axprobe.swift` becomes the E2E read method), settled
  the Stockfish licensing question with the user (**the app will be
  licensed GPLv3**; LICENSE/README/release script land in M8), fixed the
  board scope (cburnett GPLv2+ SVGs, verified live, plus three square
  themes and three dormant M1 board features: coordinates, flip,
  last-move highlight), measured the dashboard cheap enough to compute
  live (3.55 ms/game release-mode ReportBuilder run - no rollup table),
  and pinned mixed-ELO acceptance data across every rating band per the
  user's request (the user is chess.com `WillisLiao`, blitz ~231; plus
  verified accounts at ~750, ~1200, 1819-2241, 2533, and the existing GM
  fixtures). One v3 `userProfile` migration
  (`hasCompletedOnboarding`/`analysisQuality`/`boardTheme`) is the only
  schema work. Full detail in the devlog's "M8 prep" section and the
  rewritten `handoffs/NEXT-SESSION-M8.md`.
- **M8 complete (2026-07-18): polish and packaging - v1 complete per
  PLAN.md.** Followed `handoffs/NEXT-SESSION-M8.md` step by step; every
  step's verification gate passed, full detail in the devlog's "M8
  execution" section. What's new:
  - `Persistence`: a `v3_m8Settings` migration
    (`hasCompletedOnboarding`/`analysisQuality`/`boardTheme` on
    `userProfile`), `UserProfileRecord` extended, a real partial-then-full
    migration test plus a live check against a copy of the real dev DB.
  - `CoachKit`: `OllamaClient` no longer clobbers an injected session
    config's timeout; per-request timeouts (5s probes/120s chat/300s
    pull) replace one 300s-for-everything default; `.timedOut` mapping.
    Live-verified against a real frozen (`kill -STOP`) Ollama: `version()`
    failed at 5.0s, a chat turn at 121.0s, clean recovery on
    `kill -CONT`, `coach-grounding` still green after.
  - `App`: real cburnett piece artwork (`App/Resources/Pieces.xcassets`,
    fetched by `scripts/fetch-pieces.sh`, GPLv2+) replaces the Unicode
    glyph placeholders; `BoardTheme` (classic/green/blue); the three M1
    board debts closed (file/rank coordinates, a flip-board toolbar
    button, `lastMove` highlighting). Settings became a tabbed scene
    (General + Coach); a new `CoachSetupView` is shared between
    `CoachSettingsView` and a new 4-page `OnboardingView` (welcome ->
    chess.com username -> rating band -> coach), gated on
    `hasCompletedOnboarding`. A new `DashboardView` ("Progress" toolbar
    button) shows an accuracy trend chart and mistake-theme aggregation
    across analyzed, user-matched games, computed live off the main actor
    via a new shared `ReportBuilding` helper (also now used by
    `GameReplayViewModel`, replacing duplicated inline mapping code). The
    `-0.0` eval-label bug is fixed (`EvalLabel.format`); `ChessantoApp`
    no longer replaces the default "New Window" menu item, restoring an
    in-app recovery path from the zero-window state.
  - Packaging: `LICENSE` (GPLv3), `README.md` (what the app is, build
    steps, dependency/license table, signing/notarization steps
    documented but never auto-run), `scripts/release-build.sh`
    (produces an unsigned Release build; verified from a fully wiped
    `DerivedData`).
  - New E2E tooling, committed: `scripts/axprobe.swift` (reads via raw
    `AXUIElementCopyAttributeValue`, the fix for the M5/M7 "AX gap" which
    turned out to be the AppleScript bridge's limitation, not the app's),
    `scripts/axclick.swift` (presses via `AXUIElementPerformAction`),
    `scripts/axclickat.swift` (real `CGEvent` clicks at screen
    coordinates - the only thing that reliably hands a SwiftUI text field
    real keyboard focus), `scripts/axfocus.swift`/`scripts/axsettext.swift`
    (built this session but found NOT to reliably drive real SwiftUI
    `@State` bindings when writing text directly via the AX API - kept,
    but documented as unreliable for that specific purpose in the
    devlog). Reads and button/menu presses work without the app being
    frontmost; sheets don't even render while backgrounded, and real
    text entry needs the app frontmost plus a real `CGEvent` click.
  - Real E2E verification (Release build): the full fresh-user flow
    against the live chess.com API and a live Ollama - onboarded as the
    user's real account `WillisLiao`, fetched and imported a real recent
    game, analyzed it, read the real coached report, drove Chat for real
    (a real coach-narrated answer and a real illegal-move precheck
    reject) on this real beginner-band game (not just the GM fixture),
    and cross-checked the dashboard's numbers directly against
    `sqlite3`. All package tests (177), `xcodebuild test` (11 app
    tests), and `coach-grounding` (10/10 zero-leak runs) green.
  - Known gap: M3's promote/collapse variation controls and the
    promotion-picker UI are still absent (out of M8's PLAN.md scope, not
    a regression). Prose quality with small local models remains the
    documented M6/M7 residual risk, not something M8 could or should fix.
- **v1 is feature-complete per PLAN.md.**
- **UI/UX audit + redesign plan complete (2026-07-18, planning only, no code).**
  The audit followed `handoffs/NEXT-SESSION-UIUX.md`, built and ran the app, screenshotted every screen and state live, and produced the signed-off `handoffs/NEXT-SESSION-UIUX-EXECUTE.md` plan with verified facts, fixed decisions, and 12 staged gates.
  The audit reproduced 12 real problems, including toolbar overflow hiding Import PGN at 1400px, a single-column move list with a badge on every move, classification labels wrapping mid-word in the narrow Report pane, literal Coach markdown syntax, Chat replacing Moves with no position pin, a stark eval bar and graph, a broken-looking one-point dashboard chart, and sidebar rows with truncated names and raw-seconds time controls.
  The board artwork, themes, coordinates, last-move treatment, and flip behavior were explicitly protected.
  The recorded user decisions were a light and white-forward appearance, a brass accent, no green, near-monochrome warm chrome, and a Coach slide-over or wide dock that never hides the board or move context.
  The user later superseded the planned dark support by explicitly requiring a forced-light palette during execution.
  The implementation target was visual and information-architecture improvement without a new schema or unrelated feature expansion.
- **UI/UX redesign execution complete (2026-07-18).**
  The paused Sonnet task was reconstructed from its local session log and continued from Step 11 through acceptance.
  A shared design system now governs warm-neutral surfaces, graphite text, brass accents, spacing, typography, cards, chips, and primary controls.
  The user explicitly corrected the earlier plan and required the app to force the light palette even when macOS is dark, so `ChessantoApp` intentionally pins Aqua and `.light`.
  The sidebar now has room for real names and metadata, a stable Progress/Add bottom bar, and richer game rows.
  Empty selection and onboarding use a code-native Chessanto emblem and clearer value messaging.
  A generated macOS app icon carries the same ivory, graphite, brass, tilted-board, and improvement-line identity into Finder and the Dock.
  The replay workspace now has a quieter eval bar and graph, two-column notation, compact classification marks, polished controls, card-based reports, and a clear text-labeled Coach entry point.
  Coach is no longer a third tab.
  It docks as a third column when wide and slides over the right pane when narrow, while leaving the board visible.
  Coach can follow the board or pin to an exact position, and move/report entry points open it already pinned.
  Markdown now renders as formatting rather than literal asterisks.
  A regression test found and fixed an existing chat-context bug where move paths omitted White's first move and could subscript an empty history at the start position.
  The live grounding gate also exposed a mismatch between production chat verification and the independent harness.
  Fresh re-verification now recreates legal-proposal anchors, and trusted PV prefixes carry their resulting position forward.
  Full package tests, the app tests, a universal Release build, and `coach-grounding` all pass.
  The final product audit and next implementation plan are in `handoffs/NEXT-SESSION-LEARNING-LOOP.md`.
  Large UI audit screenshots remain local and are intentionally ignored because the capture set exceeds 160MB.
  M3's promote/collapse variation controls remain intentionally deferred because the wrapped move tree exposes no public child reordering, promotion, or deletion mutation API, while the current parent-pointer persistence model has no branch-order semantics.
  Implementing promotion correctly therefore requires a small domain and persistence design rather than a cosmetic control, and pairing collapse with that work avoids creating a partial editor that suggests unsupported branch management.
  Engine arrows are an intentional visual-aid extension within the user's request to improve graphics and helpfulness.
  Report prose continues to use `you`, `White`, and `Black` rather than exposing opponent usernames, which preserves an earlier user decision and keeps fixture reports legible.
  The grounding-harness change is a release-safety correction that makes independent verification faithfully recreate production's legal-proposal anchors.

## Real dependencies resolved during M1 (verified against actual source, not guessed)

- [`chesskit-app/chesskit-swift`](https://github.com/chesskit-app/chesskit-swift)
  0.17.0 (MIT) - chess rules/PGN/FEN, wrapped by `ChessCore`.
- [`chesskit-app/chesskit-engine`](https://github.com/chesskit-app/chesskit-engine)
  0.7.0 (MIT wrapper; vendors Stockfish 17, GPLv3) - wraps Stockfish
  **in-process** via async/await, no subprocess/pipes. Wrapped by
  `EngineKit`'s `AnalysisEngine` actor, which already implements the
  position-generation-counter pattern from PLAN.md's risk section.
  **NNUE networks are required, not optional** (corrected 2026-07-17: the
  earlier "embedded default network" note was wrong for this build) -
  chesskit-engine compiles Stockfish with `NNUE_EMBEDDING_OFF`, and
  Stockfish 17 `exit()`s the whole host process if a search starts with no
  net loaded. `scripts/fetch-nnue.sh` fetches + hash-verifies both nets;
  chesskit-engine auto-loads them from `Bundle.main`.
  `chesskit-engine` 0.7.0's own Stockfish tests are commented out upstream
  (they need a free main run loop plus the nets, neither of which XCTest
  in CI gives them), so EngineKit's tests stay structural; the live-engine
  check in this repo is the `engine-smoke` executable, which works and is
  the thing to run after touching EngineKit.
- GRDB 7.11.1 for persistence.
- Stockfish being GPLv3: **resolved 2026-07-18 (M8 prep, user decision) -
  Chessanto itself is licensed GPLv3** (`LICENSE`, shipped M8), making
  distribution compliant; the README's dependency/license table and
  `scripts/release-build.sh` also shipped in M8. See `PLAN.md`'s
  Architecture/Risks sections for the original analysis.

## Key decisions

- Native SwiftUI macOS app (macOS 14+), Apple Silicon primary.
- Verified Coach: rule-based facts + local LLM (Ollama), with a programmatic CoachVerifier gate on all output and an engine-tool loop; nothing unverified renders.
- Exploration Mode: chess.com-style analysis board - live eval bar while scrubbing, free variation play with variation tree, continuous engine analysis of the displayed position.
- chess.com public API fetch + offline PGN import; analysis fully local.
- RAM-based model picker; Intel Macs default to rule-based mode with a slow-inference warning.
- Position chat included in v1 (M7, complete 2026-07-18).
- Board pieces render real cburnett artwork (GPLv2+, shipped M8) sized to
  the square, replacing M1's placeholder Unicode glyphs; three square
  themes (classic/green/blue) and file/rank coordinates, flip, and
  last-move highlighting all shipped alongside them.
- The app is licensed GPLv3 (user decision, 2026-07-18): Stockfish
  compliance resolved, binaries distributable, cburnett artwork
  compatible. `LICENSE`/`README.md`/`scripts/release-build.sh` shipped M8.
- E2E/acceptance data spans all rating bands, beginner through pro (user
  request, 2026-07-18): the user's own `WillisLiao` account (~231 blitz)
  plus pinned accounts per band in `NEXT-SESSION-M8.md` fact 12, not just
  the GM fixtures - M8's acceptance pass used a real live `WillisLiao`
  game end to end (fetch, analyze, report, chat), not a GM fixture.
- A one-time onboarding flow (M8) and a live-computed player-progress
  dashboard (accuracy trend + mistake themes, M8) round out PLAN.md's v1
  scope. **v1 is now feature-complete.**

## Active Learning Loop completion (2026-07-18)

Implemented the Active Learning Loop vertical slice from `handoffs/NEXT-SESSION-LEARNING-LOOP.md`.

### Product behavior

Analyzed reports now generate persistent practice cards from audited key moments.
The Report tab has a primary `Practice key moments` action plus a small `Practice` action on each key moment.
The primary action opens the full game key-moment queue.
The row action opens that single source ply.

The Progress dashboard now surfaces a `Next lesson` card.
When due cards exist, its primary action is `Review next lesson`.
When nothing is due, it shows the next review date when available and offers a secondary `Practice any position` action against existing saved training cards.

The practice sheet reuses the real board, board theme, legal-move selection, and side-to-move orientation.
It prompts with `Find the move you wish you had played.`
It supports hint, reveal, try again, next, skip, and completion states without changing the approved warm-neutral and brass design system.

### Domain and persistence

Added a focused training domain under `App/Sources/Chessanto/Training`.
The core types are `TrainingCard`, `TrainingAttempt`, `TrainingOutcome`, `MasteryState`, `TrainingMoveEvaluator`, and `ReviewScheduling`.
`DefaultTrainingMoveEvaluator` rejects illegal moves with `ChessCore`, accepts cached ranked-line first moves, evaluates other legal attempts through the engine, compares white-perspective scores from the mover perspective, and keeps mate scores separate from centipawn scores.
The deterministic scheduler implements the current review policy: incorrect and inaccurate are due now, playable is due tomorrow, one strong recall is due in three days, two strong recalls are due in seven days, and three or more strong recalls become mastered with a fourteen-day review.

Persistence now has forward-only migration `v4_trainingLoop`.
It adds `trainingCard` and `trainingAttempt`.
Cards are unique by `gameId` plus `sourcePly`, persist the pre-move FEN and ranked-line facts needed for practice, and cascade with deleted games.
Attempts cascade with deleted cards.
`GameStore` exposes card upsert, game-card lookup, due-card lookup, any-card fallback lookup, next-due lookup, attempt save, and attempt history methods.

### Verification

Focused training app tests passed:
`xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/PracticeSessionViewModelTests -only-testing:ChessantoTests/TrainingDomainTests`.

Full app tests passed:
`xcodebuild test -scheme Chessanto -destination 'platform=macOS'`.
That run executed 23 tests in 10 suites.

Persistence package tests passed after the migration and store changes:
`swift test --package-path Packages/Persistence`.

The existing broader package and release gates also passed during this session before the final row-filter and card-count polish:
`swift test --package-path Packages/ChessCore`,
`swift test --package-path Packages/AnalysisKit`,
`swift test --package-path Packages/CoachKit`,
`swift test --package-path Packages/EngineKit`,
`swift test --package-path Packages/ChessComKit`,
`swift run --package-path Packages/EngineKit engine-smoke`,
`swift run --package-path Packages/CoachKit coach-grounding`,
and `scripts/release-build.sh`.

`git diff --check` is clean.

### Notable fix outside the practice feature

The live `coach-grounding` harness initially failed independent chat verification because its fresh audit context rebuilt anchors but did not seed the known eval and mate arrays from those anchors the way production `CoachChat` does.
`Packages/CoachKit/Sources/coach-grounding/main.swift` now seeds `knownEvalsCentipawns` and `knownMates` from the fresh anchors before the independent verification pass.
After that fix, `coach-grounding` passed with zero leaks.

### Remaining gap

This session did not capture a fresh native screenshot of the completed practice flow.
The implementation was verified by focused view-model tests, domain tests, persistence tests, full app compilation and tests, source review, and prior release gates.
The next visual QA pass should open a generated-card practice session in the Release app and capture the prompt, feedback, reveal, and completion states at normal and narrow widths.

## V1 hardening slice complete (2026-07-18)

The first execution slice from `handoffs/NEXT-SESSION-V1-HARDENING.md` is complete.
The exact implementation and native QA record is in the `V1 hardening execution` section of `devlogs/2026-07-18.md`.

Move-quality abbreviations were replaced with familiar chess-review marks.
Best uses a green star, Excellent uses a green thumbs-up, Good uses a neutral check, and the remaining classifications use familiar punctuation or symbols in their reserved semantic colors.
Every compact mark exposes the full classification through accessibility.

Training-card generation now uses the exact position immediately before the audited missed move.
When the configured username identifies White or Black, report and Dashboard generation keep only that learner's key moments.
Neutral game-scoped Report practice remains available for explicitly opened unmatched study games.

Persistence now performs transactional per-game reconciliation.
It validates candidate ownership, source-ply uniqueness, FEN, mover, legal best move, the complete persisted ranked-line shape, rank-one consistency, themes, classifications, and progress enums before writing.
It inserts new cards, updates retained cards, deletes obsolete cards, preserves scheduling when the answer is unchanged, and resets progress plus attempts when the position, mover, or answer changes.
Unchanged reconciliation is idempotent and preserves `updatedAt`.

The forward-only `v5_trainingIndexes` migration adds queue and attempt-history indexes without modifying the shipped v4 migration.
The upgrade tests preserve seeded v4 training progress, verify both indexes and the latest migration identifier, and require an empty `PRAGMA foreign_key_check`.

Report readiness is now a generation-safe state owned by `TrainingCardSynchronizer`.
Practice stays in a preparing state until reconciliation succeeds, exposes Retry after a real failure, shows a non-action state when the learner has no owned cards, and enables per-moment Practice only for reconciled source plies.
Tests cover readiness, cancellation, stale-generation rejection, failure, retry, and a real analyzed-report path that creates the exact learner-owned pre-move card without seeded SQL.

Dashboard performs a cancellable historic-game backfill before reading one consistent personalized queue snapshot.
It reports the exact due count, reloads after practice dismissal, loads fresh cards when a session opens, excludes unmatched games when a username is configured, and withholds stale actions when preparation or queue loading fails.
Dashboard failure chrome uses a dedicated error token rather than a reserved move-classification color.

Native QA used disposable copies under the sandbox container and never mutated the live database.
The live sandbox database backup path and disposable QA paths are recorded in the devlog.
The repaired Report opened a real middlegame at move 9 instead of the starting position.
The repaired Dashboard opened a developed position at move 4 and excluded the deliberately seeded unmatched move-1 card.
Valid local evidence remains at `/tmp/chessanto-v1-practice-insight-after.png`, `/tmp/chessanto-v1-classification-marks-wide-after.png`, and `/tmp/chessanto-v1-dashboard-practice-final.png`.

The final app suite passed 31 tests across 13 suites.
The final Persistence suite passed 29 tests.
The next planning task for Claude Opus is described in `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md`.
That planning task should produce one bounded implementation plan for a Claude Sonnet medium session and must treat the remaining engine, grading, practice-state, presentation, responsive, accessibility, and release gates in `handoffs/NEXT-SESSION-V1-HARDENING.md` as still open.

## V1 hardening phase 2 complete (2026-07-19)

Followed `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md` step by step; all six steps landed and every gate passed.
Full detail, including the live diagnosis evidence and the native E2E acceptance record, is in the `V1 hardening phase 2` section of `devlogs/2026-07-19.md`.
This checkout still has no physical `AGENTS.md`; the session prompt's repository rules remained authoritative.

### What changed

`AnalysisEngine` now stamps engine updates with the generation the search actually started under (`searchGeneration`) rather than the generation current at delivery time, closing the bulk of F2's cross-position score contamination.
That fix alone was insufficient in live testing: chesskit-engine dispatches each raw response through its own unstructured `Task` with no ordering guarantee, so `setPosition` now also waits for a UCI `isready`/`readyok` round trip plus a 30ms settle window before bumping the generation, unconditionally (not just when a search was in flight, since the reproduced race had `isSearching` already false at the point of entry).
This is documented in code as an empirically-verified mitigation, not a proof; 14 consecutive `engine-smoke` runs (70 repeated iterations of a new live generation-isolation assertion) passed clean after the fix.

A new `BoundedSearchSession` (`App/Sources/Chessanto/Analysis/BoundedSearch.swift`) is a `@MainActor`, engine-free coordinator that latches a search's outcome exactly once, closing F1 (a terminating bestmove arriving before anything was waiting for it, which previously hung forever).
`EngineService.searchOneShot` installs the session before sending `go`, races it against a deadline (`movetimeMilliseconds * 4 + 3000`), and both the timeout and cancellation paths now resolve with typed `EngineSearchError`s and tell the engine to stop.
`coachEvaluate`'s FIFO chokepoint (`coachEvaluateTail`) got a real cancellation-propagation fix (F4): a cancelled caller now actually cancels the queued work via a shared `runOnFIFOTail` helper, instead of the work running to completion unobserved.
`evaluateTrainingPosition` replaces `trainingEvaluationAfterMove`, sharing the same FIFO chokepoint without coupling the training domain to the Coach tool's `EngineToolResult` shape.

`WhitePerspectiveScore` (`App/Sources/Chessanto/Training/WhitePerspectiveScore.swift`) replaces the old `TrainingEngineEvaluation` two-optional pair throughout the training domain and both production call sites.
It cannot represent "both centipawns and mate" or "neither" at once, which is what let a forced mate compare against a `nil` best value and fall through to `.incorrect` (F7).

`DefaultTrainingMoveEvaluator` now short-circuits terminal positions (checkmate, stalemate) via `ChessCore` alone before any engine call (F3), grades a cached lower-ranked line against the cached rank-one score instead of blanket-accepting any cached line as strong with zero loss (F6), and implements a total mate-vs-centipawns comparison with no unrepresentable case (F7).
Two thresholds in that comparison are this evaluator's own judgement calls, not values the plan fixed: the mate-distance playable/inaccurate tiering beyond "shorter or equal is strong," and 200 centipawns as "clearly winning" when a forced mate was lost for a merely-good move.
Both are commented inline as deliberate choices.

A bounded-search failure during grading (`EngineSearchError`) is now recoverable: `PracticeSessionViewModel.submit` returns to `.prompt` with the card and board intact, records no attempt, advances no scheduler state, and surfaces a short retryable message via a new `promptError` field, rendered in `DesignColors.error`.
`.failed` stays reserved for a failure to load the lesson at all.

### Verification

The final app suite passed 55 tests across 15 suites (up from the phase-1 baseline of 31/13).
All package suites, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` passed.
`git diff --check` was clean.
`mattpocock-skills:code-review` ran against `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md` as the spec axis before the final commit; both real Standards findings (an unnamed magic-number deadline formula, an uncalled-out mate-threshold behavior change) were fixed, and the Spec axis's three "under-specified" findings were confirmed as deliberate judgement calls and documented inline rather than changed.

Native E2E acceptance used a disposable database copy under the sandbox container and the freshly built universal Release app; the live sandbox database was confirmed byte-identical (via `md5`) to the pre-session backup both mid-session and at the end.
Live-verified: F6's fix (a cached rank-3 line grades `Inaccurate`/`Engine loss: 99 centipawns`, not a blanket-accepted strong move), F1's fix (a real, non-cached move reaches the engine and returns bounded feedback, `Inaccurate`/`Engine loss: 217 centipawns`, with no hang), a genuine fresh `Analyze` pass (222 plies persisted in ~28s on a previously-unanalyzed game, after an initial false-positive test against an already-analyzed game that the skip-logic made a no-op), and Coach chat continuing to work through the shared FIFO after training evaluations had already run in the same process.
F7 (the mate-grading fix) was not exercised through native play, exactly as the plan anticipated, since it needs a cached card whose position admits a mate that is not the rank-one move; it is covered by the Step 5 tests only.
One unrelated, pre-existing bug was found along the way and not fixed (out of scope): the `Hikaru vs Casablanca` chess.com import (gameId 2 in the QA snapshot) fails to parse with `ChessKit.PGNParser.Error error 2`, matching the parser edge case already logged in the 2026-07-17 M4 devlog section.

### What's still open

The next planning task is described in `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md`.
It carries forward the full practice render-state machine, non-disclosing incorrect feedback and the distinct Reveal state, duplicate-submit rejection, review decisions for Reveal and Skip, Dashboard/practice presentation ownership, the 900-point replay and practice layout, accessibility coverage, promotion moves in practice, README/version alignment, a project-level `CLAUDE.md` (Follow-up A), and a root `CONTEXT.md` (Follow-up B) - all of which were out of scope for phase 2 and remain not started.

## UI/UX clarity planning complete (2026-07-19, planning only, no code)

An Opus planning session executed `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md` and produced three phase documents.
Full detail, including every live reproduction, is in the `UI/UX clarity: Opus planning session` section of `devlogs/2026-07-19.md`.

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` is a fully specified execution plan for one Claude Sonnet medium session.
`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` and `-PHASE-3.md` are deliberate scoping stubs, not designed in advance, because phase 1 restructures the surfaces they build on.

Everything was reproduced live in the Release app against a disposable database copy; the live sandbox database was confirmed byte-identical before and after.

Two findings overturned assumptions the bootstrap carried:

- The key-moment row hit-target bug is **not** a missing width modifier.
  Clicking the far right of the row already works; clicking the prose below the header line does not, because the `Button` wraps only the header line while the summary, narration, and caption are siblings outside it.
  A confident source-reading diagnosis was wrong for the second consecutive planning cycle.
- Playable variations need **no** schema migration.
  `RankedLine.principalVariationUCI` already persists a full PV, verified directly against `trainingCard.rankedLinesJSON`.

Pin and favorite, by contrast, genuinely have no data model in any migration `v1` through `v5` and would need a forward-only `v6`.

The user added one feedback item mid-session and resolved its ambiguity directly: practice must run inline on the existing full-size board with no modal sheet, while the training-card model, the spaced-repetition scheduler, and the Progress queue stay exactly as they are.
That decision is the structural anchor of phase 1.

`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains separately open and is not superseded.

## UI/UX clarity phase 1 complete (2026-07-19)

Followed `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` step by step; all six build steps and full verification landed.
Full detail, including live E2E evidence and one real bug found and fixed during native testing, is in the `UI/UX clarity phase 1` section of `devlogs/2026-07-19.md`.

### What changed

- `ChessGlossary` (`App/Sources/Chessanto/Training/ChessGlossary.swift`), a pure lookup mapping `en prise`, `hanging`, `forced mate`, `O-O`, `O-O-O`, and the eight `MoveClassification` cases to a one-sentence plain-language gloss, term kept beside its real name rather than replacing it (DD2).
- `BoardTheme.hint` and `BoardView.hintSquares` render the practice hint's target square as a fourth, distinct board channel (brass accent plus a stroked ring), never overloading last-move/selected/destination (DD3).
  `PracticeSessionViewModel.hintSquares` exposes the best move's origin square once `hintCount >= 2`.
- `GameReportView.keyMomentRow` was restructured (DD4) so the entire block - header, summary, Coach narration, source caption - is the jump target, via a `KeyMomentRowButtonStyle` that adds a hover/pressed `surface1` background where a bare `.plain` style would show none.
  A prior planning session's confident source-reading diagnosis of this exact code (a missing `.frame(maxWidth: .infinity)`) was wrong for the second consecutive planning cycle; the real defect was vertical (the `Button` wrapped only a 20pt header line), not horizontal, and was found only by a real click test.
- `BoardIdentityStrip` (`App/Sources/Chessanto/Board/BoardIdentityStrip.swift`) is a pure helper plus `BoardIdentityStripView`, rendering compact name/rating/"You" strips above and below the board, bound to screen position (top/bottom) rather than color so they swap correctly on flip (DD5).
- Inline practice mode (DD1): `PracticeSessionView.swift` is now `PracticeContentView.swift` (prompt/hints/feedback/progress only, no board, no frame); `PracticeBoardSection` is a new `@ObservedObject`-driven board wrapper.
  `GameReplayView.RightPaneTab` gained a programmatic-only `.practice` case; the fixed 420pt board and 760x560 sheet minimum are deleted, not enlarged.
  `GameReplayViewModel.isPracticeActive`/`enterPractice()`/`exitPractice()` suspend live engine analysis while practice shows a position that isn't a ply of this game.
  The Dashboard's practice entry points no longer own a `.sheet`; `DashboardView.onOpenPractice` and `ContentView`'s new `pendingPracticeGameID`/`pendingPracticeLoadCards` hand the session to `GameReplayView`, which owns game selection already.
- Plain language (D1/DD2): the practice prompt's classification chip now renders its word alongside the glyph (`PracticeSessionViewModel.classificationLabel`), and theme hints gloss their term (`themeHintTextIgnoringHintCount` - see the bug note below for why it's not just `themeHintText`).
- DD6 (stable hint layout): both hint lines reserve real, final-content height from the start of a card rather than a shorter placeholder, so a second `Hint` press at the same screen point lands correctly.

### A real bug found and fixed during native E2E, not caught by unit tests or code review

The first DD6 implementation swapped between a short placeholder string (hidden via opacity 0) and the real hint text (shown via opacity 1) to "reserve space."
This does not work when the real text is longer and wraps to more lines than the placeholder: native testing (two real `cliclick` presses at one fixed, un-recomputed screen coordinate) showed the `Hint` button shifting downward after the first press, so the second press missed.
Fixed by adding `PracticeSessionViewModel.themeHintTextIgnoringHintCount`, which is always the real, final gloss text; the view renders it unconditionally and only toggles opacity by `hintCount`, so the reserved height is the actual height.
Re-tested with the same fixed-coordinate double-click and confirmed both presses landed, including the level-2 hint's board-square highlight.

### Verification

The final app suite passed 70 tests across 17 suites (up from the phase-2 baseline of 55/15): `ChessGlossaryTests` (4), `BoardIdentityStripTests` (5), 4 new `PracticeSessionViewModelTests`, and 2 new `GameReplayViewModelTrainingTests`.
All package suites (`ChessCore`, `AnalysisKit`, `CoachKit`, `EngineKit`, `ChessComKit`, `Persistence`), `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` passed.
`Packages/Persistence` was unchanged, as expected (no schema migration in this phase).
`git diff --check` was clean.

Native E2E acceptance used a disposable database copy under the sandbox container (game 9, `adamzainuri vs WillisLiao`) and the freshly built universal Release app.
All seven acceptance scenarios from the plan were reproduced live: no `AXSheet` anywhere in the practice flow; the key-moment block's summary prose (not just its header) now jumps the board, and the nested `Practice` button still opens a single-card session independently; the identity strips render and swap correctly on flip; hint clarity/stability including the board-square highlight; plain-language classification on a correct answer; the Dashboard's "Review next lesson" opening inline practice on the correct game with no nested sheet; and the live sandbox database confirmed byte-identical (`md5`) before and after the whole session.

### What's still open

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` (playable variations, Coach text density) has been expanded with what phase 1 actually built, and is the next planning task.
`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-3.md` and `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remain open and untouched by this phase.
Not done and not claimed: playable variations, Coach text density, sidebar select/delete/pin/favorite, the richer player dashboard, chess.com identity confirmation in onboarding, and the remaining V1 hardening phase 3 backlog.
One cosmetic, out-of-scope gap noticed live and not fixed: the practice session-complete screen shows an empty board (no pieces) since `currentCard` is `nil` at that state; carry into a future polish pass if it comes up again.

## UI/UX clarity phase 2 planning complete (2026-07-19, planning only, no code)

A Claude Sonnet session expanded `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` from a scoping stub into a fully specified execution plan, the way the Opus session expanded phase 1.
No product code changed; this was planning and live verification only.
Full detail is in the `UI/UX clarity phase 2 planning` section of `devlogs/2026-07-19.md`.

Verified live against a read-only copy of the real production database (never written to, md5 confirmed unchanged before and after): card 6's rank-1 engine line is 15 plies deep while its rendered explanation shows only 6 SANs, confirming the "better line" data already exists in full on both the Practice and Report models with no schema change needed.

One real trap found and corrected: the stub's "actual bad continuation that was played" could be misread as `PunishmentFact.refutingSAN`, but that fact is the engine's hypothetical best reply to a mistake, not a record of what the opponent actually played in the game.
The plan sources the real continuation from the game's own mainline instead.

The design locks a single new module, `LinePreviewController` (pure, `ChessGame.replayLine`-backed, no persistence), owned independently by `PracticeSessionViewModel` and by `GameReplayView`, explicitly never touching `GameReplayViewModel`'s persisted `variation` table - reusing `adoptLine` for this would have silently written DB rows for every line the learner previews.

Coach text density: `card.explanation` (Practice's post-answer feedback) and the Report's rule-based fallback text share the same underlying string, so one rendering-only fix (sentence-level chunking, not truncation, not a new disclosure affordance) fixes both surfaces at once.
`CoachVerifier` was confirmed to check numeric claims anywhere in the response text rather than requiring the parenthetical-eval format the prompt asks for, so the rendering fix cannot weaken grounding; any `CoachPrompt` wording change stays conditional on that rendering fix proving insufficient, and is gated on a real fallback-rate measurement, not a single run.

This historical planning note is superseded by the completed phase 2 and phase 3 implementation records below.

## UI/UX clarity phase 3 and visual-system redesign complete (2026-07-19)

Phase 3 is implemented and verified.
Phase 2 was subsequently implemented on 2026-07-19, as recorded at the top of this handoff.
Full implementation and native E2E detail is in the `UI/UX clarity phase 3 and visual-system redesign` section of `devlogs/2026-07-19.md`.

### Library organization and recoverable deletion

- A forward-only `v6_gameOrganization` migration adds `pinnedAt`, `isFavorite`, and `deletedAt` to `game`, plus the active-library ordering index.
- A forward-only `v7_confirmedChessComIdentity` migration records whether the saved chess.com username completed the explicit account-proof flow.
- `GameStore` now exposes atomic pin, favorite, move-to-Recently-Deleted, restore, and permanent-delete commands.
- Normal game navigation remains single-selection, while a separate Organize mode owns multi-selection so bulk actions never destabilize the open replay detail.
- The sidebar has persistent All Games, Favorites, Player Brief, and Recently Deleted sources, plus explicit pinned and favorite controls.
- Moving games to Recently Deleted supports immediate undo and preserves analysis, variations, training cards, chat, and all other dependent data.
- Permanent deletion is isolated inside Recently Deleted and requires typed confirmation before the existing cascade can run.
- Deleted games are excluded from the active library and training queue.

Two source-level assumptions from the stub were corrected during implementation.
The existence of a cascading `deleteGame` data-layer method did not make direct destructive deletion an appropriate UI primitive, so the shipping flow is recoverable by default.
The main `selectedGameID` binding did not need to become a `Set<Int64>` to support bulk work, because a separate organization selection preserves the detail pane's navigation contract more cleanly.

### Evidence-based Player Brief

- The former Progress destination is now a persistent, labeled Player Brief source rather than a hidden chart icon.
- `PlayerInsightBuilder` derives the current finding, costly-move count, phase distribution, color and time-control context, repeated lesson themes, and classification counts only from stored analyzed-game evidence.
- The brief names a strength only when both sides of a comparison have at least three games and differ by at least five accuracy points.
- Sparse samples show explicit thresholds and caveats instead of decorative empty charts or invented tactical and positional claims.
- Equal thirds are labeled First, Middle, and Final third, with a methodology note that they are game-relative segments rather than formal chess phases.
- The presentation is a compact analysis memo with aligned registers and ruled sections rather than a dashboard of floating cards.

### Confirmed chess.com identity

- `ChessComProfile` and `ChessComStats` decode the public account proof needed for confirmation, including profile URL and available ratings, while allowing the stats request to fail without discarding a valid profile.
- `ChessComAccountLookupModel` separates candidate lookup from explicit confirmation, rejects stale asynchronous results, and never persists an unconfirmed username.
- The same text-only account proof and confirmation flow is shared by onboarding and Settings.
- Legacy saved usernames migrate as unconfirmed and are never labeled Connected or accepted by Player Brief until the user confirms the account once.
- The design deliberately does not fetch the remote avatar, preserving the app's local-first posture while still showing enough account evidence to make the identity choice explicit.

### Company-designed native visual system

- The entire app now follows a native macOS scorebook and analysis-desk direction: flat ruled sections, dense aligned rows, restrained brass selection, square analytical instruments, system typography, and clear hierarchy.
- Rounded display type, generic emblem tiles, capsules, gradients, decorative shadows, and floating card chrome were removed from the shared design system and major app surfaces.
- The library, replay workspace, report, Coach, onboarding, Settings, evaluation graph, evaluation bar, move classifications, and player identity treatments now use the same visual grammar.
- The analysis workspace now presents a compact Game audit, Key-moment register, Review notes, and a quieter Review toolbar.
- The prior narrow-width evaluation label wrap was fixed as part of the whole-app polish request.

### Verification and database safety

The final app suite passed 75 tests across 19 suites.
All package suites passed: `ChessCore` 21, `AnalysisKit` 63, `CoachKit` 74, `EngineKit` 1, `ChessComKit` 4, and `Persistence` 35.
`engine-smoke` passed every real-engine and generation-isolation check.
`coach-grounding` completed 10 Coach runs with zero violations and zero leaks.
`scripts/release-build.sh` produced a successful universal arm64 and x86_64 Release build.
`git diff --check` was clean.

Native E2E ran only against a disposable database copy under the app container.
It verified bulk recoverable deletion, Recently Deleted selection, restore, retained analysis after restore, Player Brief recomputation, the library, replay workspace, onboarding, and Settings.
A finite-height bug in the first Recently Deleted implementation was visible only in the running app and was fixed by replacing the nested `List` with a bounded selectable `ScrollView`.

The final safety check detected that the live database had received only the new v6 schema migration during the build and test cycle.
All user-data table counts matched the pre-session backup exactly.
With no Chessanto process running, the live file was restored from the mandatory pre-session backup and its md5 returned to the original `1d218f0371a61f85bc682cc43acb9af5`.

### What's still open

`handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` now preserves the investigation and records the completed implementation.
`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains a separate unstarted backlog and was not superseded.
The phase 3 document now records the locked design decisions, test-first sequence, and native acceptance record.
The Codex briefing remains as the historical input this implementation followed and re-verified.

## iPhone-first companion complete (2026-07-19)

The approved iPhone-first companion is implemented across the Mac app, the new iPhone target, and the new shared `CompanionKit` package.
The complete execution and verification record is in `handoffs/IPHONE-COMPANION-EXECUTION.md`.

Secure pairing uses signed five-minute invitations, a matching phrase, explicit Mac approval, wrapped content keys, authenticated encryption, replay defense, rotation, and revocation.
The phone can request the Mac's local analysis, receive exact progress and terminal status, cancel work, receive the completed portable report, and retain encrypted reports for offline review.
Local and remote analysis now share one application service, and a durable ledger prevents redelivery from starting duplicate engine work.

The Coach now has explicit speech controls on Mac and iPhone plus six deterministic emotional portraits.
Speech uses an original slower, lower-pitched sage delivery and never starts automatically.

The user corrected key-moment behavior during implementation.
Selecting a key moment now only jumps to the position and stops an existing preview.
Only Show better line or Replay better line starts playback.

Native Release QA used only `/Users/willis/Library/Containers/com.chessanto.app/Data/tmp/iphone-companion-20260719-211052/chessanto.sqlite`.
The live database MD5 remained `26f0882ad0e3ffdfc7a065a5791f8b5f` before and after QA.

The macOS suite passes 104 tests across 27 suites, `CompanionKit` passes 29 tests across 10 suites, the iPhone target passes 3 tests across 2 suites, every existing package suite passes, and the universal Release build succeeds.

Physical CloudKit pairing remains an external provisioning acceptance step.
This checkout has no Apple Developer team or private iCloud container, so the apps show an honest blocker until the owner configures the same container and `ChessantoCloudKitContainerIdentifier` for both targets.

## Final companion hardening and Kokoro TTS integration (2026-07-19)

The companion implementation has been fully audited, finalized, committed, and pushed. On top of that, Kokoro TTS has been integrated as the primary natural-sounding voice for the Coach.

### Companion Delivery
- The companion work was committed under hash `c2e349d1140950d1e6457cc1e4916fcb5f4a21a7` and pushed to remote `main`.
- Pre-commit audits verified no secrets, no trailing whitespaces, and no accidental files.
- The live SQLite database was restored to its backup state with MD5 `26f0882ad0e3ffdfc7a065a5791f8b5f` and WAL/SHM sidecars were removed.
- All test counts are fully verified:
  - macOS app: 107 tests in 27 suites.
  - CompanionKit: 32 tests in 11 suites.
  - iPhone app: 4 tests in 3 suites.
  - Local packages and grounding/smoke targets all green.

### Kokoro TTS Integration
- **Selected Voice:** George (`bm_george` preset), British male (deeper, measured).
- **Server:** A local lightweight HTTP server (`server.py` in `.voice-demo/`) exposes `/tts` (and `/v1/audio/speech`) running on port `8888` using the Kokoro-82M ONNX model.
- **Client:** `DesktopCoachSpeechController.swift` (macOS) and `OfflineReportReader.swift` (iOS) check if `http://127.0.0.1:8888/tts` is active. If so, they send a POST request with text, stream audio via `AVAudioPlayer`, and support standard speech controls.
- **Fallback:** If the local server is completely offline/unreachable, the app falls back to Apple's native `AVSpeechSynthesizer` voices. However, if the server is healthy/online, the app **always** uses George's voice and waits up to **60.0s** for the synthesis to complete, completely bypassing the native system voice fallback even in the event of timeouts or failures.
- Committed under hash `9ddb070997ce06253c651f4c7590823522f778ea` and pushed to remote `main`.
- Physical CloudKit pairing remains blocked on Apple Developer team and container setup.
- The latest compiled Release app is located at:
  `/Users/willis/Library/Developer/Xcode/DerivedData/Chessanto-dvybgihmaxaffpbutfmycvjeqlkn/Build/Products/Release/Chessanto.app`



## Future directions (explicitly out of v1)

Repertoire training, play-vs-engine, Lichess import, iCloud sync, Chess960, richer search/filtering, and a dedicated accessibility UI-test matrix.
Post-v1 priorities not yet decided with the user - ask before starting new work here.

## Multi-ply practice exchange (2026-08-24)

P4.5 multi-ply practice is implemented on branch multiply-practice-p4.5.
PracticeSessionViewModel now owns one Equatable PracticeExchange value containing the legal rank-one prefix, learner cursor, applied prefix, stage, learner evaluations, outcomes, and first-attempt flag.
The rank-one line is replayed once at card load and malformed tails are truncated to the legal prefix.
Board position, legal-move context, promotion checks, and last-move highlighting all derive from the applied prefix.
Rich lines grade exact UCI moves without engine calls, automatically show one stored opponent reply at a time, and terminate on line exhaustion or checkmate.
Wrong learner moves persist one incorrect attempt, reset the whole exchange on retry, and permanently clear first-attempt success for that card.
A fully correct exchange persists one strong attempt and increments first-attempt success once, while intermediate learner moves and opponent replies do not schedule or persist attempts.
Legacy one-learner cards retain the evaluator path and existing alternative-move feedback semantics.
Hint level one reads a typed ignored-threat marker carried in the existing themes JSON, and marker strings are excluded from display themes and recurring-theme aggregation.
The practice view shows step progress, three stable hint slots, an accessible opponent-reply status, and a disabled display-only board outside learner prompts.
Focused PracticeSessionViewModel and TrainingDomain tests pass, including successful exchanges, wrong-ply reset, both checkmate endings, stale reply cancellation, scheduler atomicity, marker generation and compatibility, and malformed lines.
Native visual capture remains unavailable in this agent environment, so the reply flow was verified through injected-delay tests, compiled SwiftUI state paths, and accessibility-oriented source checks.
