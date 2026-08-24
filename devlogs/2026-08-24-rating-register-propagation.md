# Rating Register Propagation

This work propagates the resolved `AnalysisKit.RatingRegister` across every production report-building path instead of silently defaulting non-replay surfaces to `.advanced`.

## Context and Discovery

`AnalysisKit` provides three audience registers (`.beginner`, `.intermediate`, `.advanced`) that tailor move-classification summaries, evaluation-swing wording, and key-moment selection.
`GameReplayViewModel` had already been resolving the register using `RatingRegister.resolve(ratingBand:userRating:)` from the user's profile and game rating.
However, multiple other production report construction paths bypassed this resolution and invoked `ReportBuilder.build` without a register parameter, silently falling back to `.advanced`.
These paths included `DashboardView` (aggregating dashboard statistics and backfilling training cards), `PlayerBriefView` (generating aggregate insights and theme summaries), `MacGameAnalysisBackend` (preparing coach narrations for companion exports), `PortableReportAssembler` (assembling companion analysis reports), and the shared `ReportBuilding.buildReport` helper.

## Unified Shared Seam

Rather than duplicating user rating extraction and register resolution rules across views and services, `ReportBuilding` now provides a single shared seam.
`ReportBuilding.userRating(in:username:)` inspects the game record's White and Black player names case-insensitively and returns the corresponding rating.
`ReportBuilding.resolveRegister(userProfile:ratingBand:userRating:record:username:)` extracts the band and rating context, delegating to `RatingRegister.resolve(ratingBand:userRating:)`.
When genuinely no profile or rating context is provided (such as in tests or legacy callers omitting profile context), it falls back to `.advanced` to preserve backward compatibility.
`ReportBuilding.buildReport(record:analysisRows:chessComUsername:userProfile:register:)` resolves the register automatically and passes it to `ReportBuilder.build(input:openingBook:register:)`.

## Production Boundary Updates

`GameReplayViewModel.buildReport()` now delegates to `ReportBuilding.resolveRegister` and `ReportBuilding.userRating`.
`DashboardView` loads the local `UserProfileRecord` and supplies it to `ReportBuilding.buildReport` in both `computeDashboard` and `backfillTrainingCards`.
`PlayerBriefView.buildSnapshot` loads `UserProfileRecord` and passes it into `ReportBuilding.buildReport`.
`MacGameAnalysisBackend.analyze` resolves the register from the stored user profile and game record, supplies it to `ReportBuilder.build`, and forwards `register` to `MacCompletedAnalysis`.
`MacCompletedAnalysis` carries `register: RatingRegister` with an `.advanced` default.
`GameAnalysisApplicationService.analyze` forwards `result.register` into `PortableReportAssembler.assemble`.
`PortableReportAssembler.assemble` accepts an optional `register: RatingRegister = .advanced` parameter and passes it into `ReportBuilder.build`.

## Testing and Verification

Strict test-driven development was followed by first capturing failing behavior tests across the boundaries.
The new suite in `App/Tests/ChessantoTests/RatingRegisterPropagationTests.swift` covers:
- `ReportBuilding.userRating` case-insensitive matching against White and Black players.
- `ReportBuilding.resolveRegister` honoring fixed bands (`beginner`, `intermediate`, `advanced`) and adaptive ratings (<1200, 1200-1800, >1800, unrated).
- `ReportBuilding.resolveRegister` falling back to `.advanced` when missing context.
- `ReportBuilding.buildReport` producing reports with the resolved register.
- `PortableReportAssembler.assemble` propagating the explicit register and defaulting to `.advanced`.
- `MacCompletedAnalysis` storing and defaulting the register appropriately.
- `GameAnalysisApplicationService` propagating the resolved register into `PortableAnalysisReport`.
- `PlayerBriefView.buildSnapshot` building reports under the user's profile rating band.
- `DashboardView.backfillTrainingCards` reconciling cards under the user profile register.
- `DashboardView.computeDashboard` computing accuracy points and theme counts under the user profile register.

All 172 `AnalysisKit` tests passed, all 198 application tests in `ChessantoTests` passed, and the root macOS app build succeeded cleanly.
