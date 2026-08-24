# 2026-08-24 - Roadmap documentation truth audit and reconciliation

## Objective

Align all active roadmap documentation, capability claims, and milestone tracking with the verified reality of the production codebase, while preserving historical records with clear status notices.

## Authoritative evidence table

| Requirement / Area | Status | Source Evidence | Test Evidence | Notes & Open Items |
|---|---|---|---|---|
| M1: Skeleton, Board, Replay, PGN Import | Completed | `App/Sources/Chessanto/Board/BoardView.swift:1-60`, `Packages/ChessCore/Sources/ChessCore/ChessGame.swift:1-120`, `Packages/Persistence/Sources/Persistence/GameStore.swift:1-150` | `Packages/ChessCore/Tests/ChessCoreTests/ChessGameTests.swift:1-80` (34 tests in 1 suite) | Full PGN import, board display, and move list replay verified in production. |
| M2: In-Process Engine, Eval Bar, Graph, Classification | Completed | `Packages/EngineKit/Sources/EngineKit/AnalysisEngine.swift:1-80`, `App/Sources/Chessanto/Analysis/EngineService.swift:1-120`, `Packages/AnalysisKit/Sources/AnalysisKit/MoveClassifier.swift:1-90`, `Packages/AnalysisKit/Sources/AnalysisKit/Accuracy.swift:1-50` | `Packages/AnalysisKit/Tests/AnalysisKitTests/EvalLabelTests.swift:1-60`, `AnalysisKitTests.swift:1-100` (172 tests in 6 suites) | Stockfish 17 in-process analysis, MultiPV parsing, win probability, and accuracy formulas. |
| M3: Exploration Mode & Variations | Completed | `App/Sources/Chessanto/GameReplay/GameReplayViewModel.swift:1-200`, `App/Sources/Chessanto/GameReplay/LinesPanelView.swift:1-100`, `Packages/Persistence/Sources/Persistence/VariationRecord.swift:1-50` | `App/Tests/ChessantoTests/` (188 tests in 34 suites) | Variation branching, lines adoption, and delete-subtree work; promote/collapse controls remain open. |
| M4: Chess.com Fetch & Import | Completed | `Packages/ChessComKit/Sources/ChessComKit/ChessComClient.swift:1-80`, `App/Sources/Chessanto/Import/ChessComFetchSheet.swift:1-120` | `Packages/ChessComKit/Tests/ChessComKitTests/ChessComKitTests.swift:1-40` (4 tests in 1 suite) | Public archive fetching, duplicate detection, and batch import. |
| M5: Rule-Based Coaching Report & Facts | Completed | `Packages/AnalysisKit/Sources/AnalysisKit/ReportBuilder.swift:1-150`, `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift:1-120`, `Packages/AnalysisKit/Sources/AnalysisKit/FactAuditor.swift:1-80`, `Packages/AnalysisKit/Sources/AnalysisKit/ReportText.swift:1-150` | `Packages/AnalysisKit/Tests/AnalysisKitTests/ReportBuilderTests.swift:1-100`, `RealFixtureGoldenTests.swift:1-80` | Audited Facts pipeline, closed ReportText templates, and ECO opening book matching. |
| M6: Local LLM Coach & CoachVerifier Gate | Completed | `Packages/CoachKit/Sources/CoachKit/CoachVerifier.swift:1-150`, `Packages/CoachKit/Sources/CoachKit/CoachPrompt.swift:1-120`, `Packages/CoachKit/Sources/CoachKit/CoachNarrator.swift:1-100` | `Packages/CoachKit/Tests/CoachKitTests/CoachVerifierTests.swift:1-120` (112 tests in 8 suites) | Default-closed evaluation requirement, structured moment payload, and fallback to rule-based text. Mock-tested; real Ollama instance validation unavailable in CI. |
| M7: Position Chat & Tool Loop | Completed | `Packages/CoachKit/Sources/CoachKit/CoachChat.swift:1-120`, `App/Sources/Chessanto/Coach/ChatView.swift:1-100`, `Packages/Persistence/Sources/Persistence/ChatMessageRecord.swift:1-50` | `Packages/CoachKit/Tests/CoachKitTests/CoachChatTests.swift:1-100` | Conversational chat with legality precheck, current-turn evaluate tool loop, and persisted history. |
| M8: Onboarding, Settings & Packaging | Completed | `App/Sources/Chessanto/Onboarding/OnboardingView.swift:1-100`, `App/Sources/Chessanto/Settings/SettingsView.swift:1-80`, `scripts/release-build.sh:1-60` | Full App test suite (188 tests in 34 suites) | Onboarding, settings, sandbox entitlements, and release build script. |
| Active Practice & Multi-Ply Exchanges (P4.5) | Completed | `App/Sources/Chessanto/Training/PracticeSessionViewModel.swift:1-715`, `App/Sources/Chessanto/Training/PracticeContentView.swift:1-150`, `App/Sources/Chessanto/Training/TrainingDomain.swift:1-510` | `App/Tests/ChessantoTests/PracticeSessionViewModelTests.swift:1-300`, `TrainingDomainTests.swift:1-250` | Multi-ply value-type state machine (`PracticeExchange`), automated engine replies, exact PV grading, whole-exchange retry reset, and threat hint ladder. |
| Spaced Repetition (P4.6) | Completed | `App/Sources/Chessanto/Training/TrainingDomain.swift:420-510`, `Packages/Persistence/Sources/Persistence/Schema.swift:376-395` (`v12_spacedRepetition`) | `App/Tests/ChessantoTests/TrainingDomainTests.swift:200-250`, `Packages/Persistence/Tests/PersistenceTests/PersistenceTests.swift:1-80` (44 tests in 2 suites) | Ease-factor SM-2 model, lapse count dampening, and 1-day relearn interval. Reveal/Skip review tracking remains open. |
| Analysis Correctness (P1.1-P1.7) | Completed | `App/Sources/Chessanto/Analysis/EngineService.swift:20-60`, `Packages/AnalysisKit/Sources/AnalysisKit/MoveClassifier.swift:1-90`, `Packages/AnalysisKit/Sources/AnalysisKit/BrilliancyDetector.swift:1-100` | `Packages/AnalysisKit/Tests/AnalysisKitTests/BrilliancyDetectorTests.swift:1-100` | Depth budgets (depth 14/18/22), book move exemption, forced move handling, net material punishment gate, and `.brilliant` sacrifice detection. |
| Coach Entry Points & Flow (P2.1-P2.6) | Completed | `App/Sources/Chessanto/Coach/ChatView.swift:1-150`, `App/Sources/Chessanto/GameReplay/MoveListView.swift:1-100`, `App/Sources/Chessanto/GameReport/GameReportView.swift:1-100` | `App/Tests/ChessantoTests/` (188 tests in 34 suites) | Following vs pinned mode banners, scoresheet and report pin badges, and top toggle unpin behavior. Dark mode remains an open product decision. |
| Board Affordances & Native QA (P3.1-P3.3) | Completed | `App/Sources/Chessanto/Board/BoardInteraction.swift:1-200`, `App/Sources/Chessanto/Board/BoardView.swift:1-200`, `App/Sources/Chessanto/Board/RightDragCatcher.swift:1-60` | `scripts/axdrag.swift:1-80`, `scripts/axprobe.swift:1-60`, App unit tests | Drag and drop live confirmed via AX automation, promotion picker, sound effects, piece animations, and annotation routing. Visual-only capture remains unverified. |
| Ignored Threat Detector (P4.2) | Completed | `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift:90-170`, `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift:76-99` | `Packages/AnalysisKit/Tests/AnalysisKitTests/ThemeDetectorTests.swift:1-100` | Board-replay detector for unaddressed opponent tactical threats, audited `IgnoredThreatFact`, and ReportText sentences. |
| Fork Detector (P4.2) | Completed | `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift:180-260`, `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift:100-130` | `Packages/AnalysisKit/Tests/AnalysisKitTests/ThemeDetectorTests.swift:100-180` | Replay-based conservative fork detector with two valuable targets or king target and settled material gain. |
| Move Quality Flags (P4.2) | Completed | `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift:270-380`, `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift:140-180` | `Packages/AnalysisKit/Tests/AnalysisKitTests/RealFixtureGoldenTests.swift:1-80` | Composition of capture, check, checkmate, piece identity, castling, original queen, and redevelopment flags. |
| Concrete Takeaways (P4.3) | Completed | `Packages/AnalysisKit/Sources/AnalysisKit/ReportBuilder.swift:160-240` | `Packages/AnalysisKit/Tests/AnalysisKitTests/ReportBuilderTests.swift:100-150` | Recurring ignored threats and structured error-frequency summaries replacing empty fallbacks. |
| UI Polish Batch (P5.1-P5.8) | Completed | `App/Sources/Chessanto/AccuracySummaryFormatter.swift:1-40`, `App/Sources/Chessanto/GameReport/GameReportView.swift:1-150`, `App/Sources/Chessanto/GameReplay/LinesPanelView.swift:1-100` | Full App test suite (188 tests in 34 suites) | Single-line chips, collapsible glossary legend, percent-formatted user accuracy, readable sidebar results, and separate line inspection from adoption. |
| iPhone Companion & Remote Protocol | Completed | `Packages/CompanionKit/Sources/CompanionDomain/`: all modules, `Mobile/`: iOS companion app | `Packages/CompanionKit/Tests/CompanionDomainTests/` (32 tests in 11 suites across CompanionKit) | Cryptographic pairing, remote analysis requests, and portable report transfer. CloudKit pairing blocked on developer provisioning. |

## Audited contradictions and reconciliation decisions

1. **Analysis Correctness living status (NEXT-SESSION-ANALYSIS-CORRECTNESS.md)**:
   - Contradiction: Header claimed broad priorities 2 through 5 were completely unstarted.
   - Decision: Added a living status notice reflecting that Priorities 1, 2, 3, 5, and the vast majority of Priority 4 are implemented in production.
   - Preserved: The historical review analysis and the two superseded Priority 1 items (P1.3 mate-decided positions and P1.1 timing race) were preserved with explicit notes.

2. **P4.2 detectors and [%clk] clock parsing claim (HANDOFF.md and NEXT-SESSION-ANALYSIS-CORRECTNESS.md)**:
   - Contradiction: HANDOFF.md referenced a "tempo-wasting-move" detector as remaining even though the actual P4.2 plan specifies pins, skewers, discovered attacks, back-rank weaknesses, and trapped pieces, while `%clk` parsing was mistakenly claimed as already existing.
   - Decision: Updated HANDOFF.md and NEXT-SESSION-ANALYSIS-CORRECTNESS.md to correctly enumerate remaining detectors (pins, skewers, discovered attacks, back-rank weaknesses, trapped pieces) and noted that `%clk` parsing is absent across all packages.

3. **Practice and spaced repetition scope (PLAN.md and README.md)**:
   - Contradiction: PLAN.md and README.md listed mistake-derived practice cards and spaced repetition under "Out of scope for v1".
   - Decision: Updated README.md capabilities to include Active Practice and SM-2 Spaced Repetition.
   - Updated PLAN.md to include completion notes for milestones M1 through M8 and clarified that practice cards and spaced repetition were built and integrated into production, while retaining truly out-of-scope items (repertoire training, playing against engine, Lichess import, iCloud sync, Chess960).

4. **Promotion picker gap in Milestone M4 (NEXT-SESSION-M4.md)**:
   - Contradiction: NEXT-SESSION-M4.md listed "No promotion picker (auto-promotes to queen)" as an open gap.
   - Decision: Preserved the document as a completed historical record and added a note explaining that the promotion picker was subsequently implemented in Priority 3 (`BoardInteraction` and `PracticeSessionViewModel`).

5. **UI/UX Clarity Phase 3 self-contradiction (NEXT-SESSION-UIUX-CLARITY-PHASE-3.md)**:
   - Contradiction: Top of file stated Phase 2 was implemented, but lines 7 and 439 stated Phase 2 remained unimplemented.
   - Decision: Reconciled the status notice to explain that Phase 3 completed on 2026-07-19, and Phase 2 was subsequently completed in `NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` and integrated into production.

6. **Historical test counts versus current canonical validation**:
   - Contradiction: Older documents cite lower test counts from earlier milestones (e.g., 75 app tests in phase 3).
   - Decision: Preserved historical session counts in their respective completed narratives, while updating living status and integration sections with the canonical test validation (34 ChessCore, 172 AnalysisKit, 112 CoachKit, 44 Persistence, 4 ChessComKit, 32 CompanionKit, 1 EngineKit, and 188 App tests).

## Genuinely open items preserved

The following items are confirmed open and remain visible in the living documentation:
- Pin detector (`ThemeDetector.pin`) if not yet merged into this branch.
- Discovered attacks, skewers, back-rank weaknesses, and trapped piece detectors.
- Practice Reveal and Skip review record tracking in the training store.
- Propagation of `RatingRegister` across all UI views and explanations.
- Variation tree promote and collapse controls.
- Visual-only board verification (arrival animation scalar timing, coordinate label point size, drawn annotation shapes) in headless environments.
- Real local Ollama model execution against a running instance at `127.0.0.1:11434`.
- Unresolved product decisions: light appearance lock vs dark mode, and disabling Coach below 8B models.

## Canonical validation results

- `swift test --package-path Packages/ChessCore`: 34 tests in 1 suite passed.
- `swift test --package-path Packages/AnalysisKit`: 172 tests in 6 suites passed.
- `swift test --package-path Packages/CoachKit`: 112 tests in 8 suites passed.
- `swift test --package-path Packages/Persistence`: 44 tests in 2 suites passed.
- `swift test --package-path Packages/ChessComKit`: 4 tests in 1 suite passed.
- `swift test --package-path Packages/CompanionKit`: 32 tests in 11 suites passed.
- `swift test --package-path Packages/EngineKit`: 1 test in 0 suites passed.
- `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test`: 188 tests in 34 suites passed (`** TEST SUCCEEDED **`).
