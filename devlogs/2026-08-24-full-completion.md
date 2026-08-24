# 2026-08-24 - Full roadmap completion

## What this session did

Implemented every remaining roadmap item from `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` in a single session, completing the full Chessanto roadmap.

## What landed

### P4.2 remaining tactical detectors (4 new detectors)

All four detectors follow the existing pattern: ChessGame helper + Fact struct + ThemeDetector function + FactAuditor verify + ReportText sentence + ReportBuilder wiring + CoachFactsPayload propagation.

- **Skewer detector**: `ChessGame.skewers(in:)` finds slider-vs-more-valuable-vs-less-valuable alignments using ChessKit legal moves and collinearity check. `ThemeDetector.skewer(input:ply:)` fires when exactly one new skewer appears after the played move.
- **Discovered attack detector**: `ThemeDetector.discoveredAttack(input:ply:)` compares enemy pieces attacked by the mover's pieces before and after the move, reporting new attacks from pieces other than the one that just moved.
- **Back-rank weakness detector**: `ChessGame.hasBackRankWeakness(fen:for:)` checks king on back rank, no flight squares, pawn shield present. `ThemeDetector.backRankWeakness(input:ply:)` fires for the mover's king after the played move.
- **Trapped piece detector**: `ChessGame.trappedPieces(in:)` finds pieces with no safe move (every legal destination is attacked). `ThemeDetector.trappedPiece(input:ply:)` fires for the mover's pieces after the played move.

### [%clk] clock parsing and time-pressure takeaways

- `ChessGame.parseClockAnnotation(_:)` parses `[%clk HH:MM:SS]` from PGN comments into seconds.
- `PlyRecord.clockSeconds` added (optional, no migration needed - parsed at report-building time).
- `ReportBuilder.timePressureTakeaway` fires when a player made 2+ errors while under 30 seconds on the clock.

### Coach model floor (P4.8 completion)

- `CoachModelCatalog.meetsModelFloor(_:)` checks whether a model tag meets the 8B parameter floor.
- `CoachSetupView` shows a warning when a below-floor model is selected.
- `ChatView.isCoachEnabled` gates the Coach off for below-floor models, falling back to rule-based text.

### Dark mode support

- `DesignColors` converted from static light values to adaptive `Color.dynamic(light:dark:)` that switches based on effective appearance.
- `ChessantoApp` reads `@AppStorage("prefersDarkMode")` and pins `.aqua` or `.darkAqua` accordingly.
- `GeneralSettingsView` gained an "Appearance" section with a "Dark mode" toggle.
- Default remains light per the 2026-07-18 product decision.

## Verification

- ChessCore: 44 tests pass.
- AnalysisKit: 195 tests pass across 6 suites.
- CoachKit: 114 tests pass across 8 suites.
- Persistence: 44 tests pass across 2 suites.
- App: 188 tests pass across 34 suites.
- macOS build: `** BUILD SUCCEEDED **`.
- macOS tests: `** TEST SUCCEEDED **`.

## What remains

The roadmap is feature-complete. The only items that remain are environment-dependent:
- Visual-only rendering verification (needs a composited display).
- Physical CloudKit pairing (needs Apple Developer team provisioning).
- Native E2E QA of the new detectors against real games (the detectors are tested against synthetic fixtures and the real Carlsen fixture, but live app verification was not possible in this session).
