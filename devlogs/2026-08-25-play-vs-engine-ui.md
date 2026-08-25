# Devlog: Play vs Engine UI (2026-08-25)

## Overview
Built the full SwiftUI interface and interaction flow for playing against the engine on top of `LiveGameSession` and `EngineService`.

## Changes Built
1. **`PlayVsEngineViewModel` (`App/Sources/Chessanto/Play/PlayVsEngineViewModel.swift`)**:
   - Manages stage transitions between `.setup`, `.playing`, and `.completed(GameOutcome)`.
   - Drives live board interaction via `BoardInteraction`, translating tap, drag-and-drop, and promotion choices into legal moves through `LiveGameSession`.
   - Supports board orientation flipping (defaults to black-at-bottom when playing as Black).
   - Handles live in-game actions including resignation and draw claims.

2. **`PlayVsEngineSetupView` (`App/Sources/Chessanto/Play/PlayVsEngineSetupView.swift`)**:
   - Clean setup screen matching the warm-neutral design tokens.
   - Side selector allowing choice of White (play first), Random (50/50), or Black (engine plays first).
   - Engine strength selector listing all 5 presets (`beginner`, `casual`, `intermediate`, `advanced`, `master`) with skill levels, search depths, movetime ceilings, and estimated Elos.

3. **`PlayVsEngineView` (`App/Sources/Chessanto/Play/PlayVsEngineView.swift`)**:
   - Two-column live play screen reusing `BoardView` directly without forking.
   - Live board identity strips with opponent calculating indicator and player turn indicator.
   - Live move scoresheet formatted via `MoveNotationFormatter`.
   - Resignation confirmation dialog and draw claim alerts.
   - Game over banner with outcome and direct transition button ("Review Game & Report") that routes into the existing `GameReplayView` review report.

4. **`ContentView` & `ChessantoApp` Integration**:
   - Added `.playVsEngine` destination in `ContentView`.
   - Added entry points in sidebar "Add game" menu, library controls source list, and empty library state.
   - Added menu bar command (Cmd+N) for "Play vs Engine...".
   - Finished games reload `GameLibrary` and transition smoothly into `GameReplayView`.

5. **Unit Tests (`App/Tests/ChessantoTests/PlayVsEngineViewModelTests.swift`)**:
   - Added 8 unit tests covering initial setup, White turn cycle, Black first move with board flip, drag and drop, resignation, draw claim alerts, automatic threefold repetition completion, and board flip toggle.

## Core Session API Assumptions
- Assumed `LiveGameSession` provides `@Published` state for `status`, `position`, `lastMove`, `playedMovesSAN`, `outcome`, and `persistedRecord`.
- Assumed `LiveGameSession.playUserMove(from:to:promotion:)`, `resign()`, `claimDraw()`, `legalDestinations(from:)`, and `isPromotion(from:to:)`.
- Assumed `EngineStrength.allCases` provides difficulty presets.
- Assumed `EngineService` conforms to `EngineOpponent`.
- Result: All assumptions matched the core implementation on `feature/play-vs-engine-core` exactly.

## Verification Output
```
xcodegen generate
Created project at /Users/willis/Documents/chessanto-play-vs-engine-ui/Chessanto.xcodeproj

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
** BUILD SUCCEEDED **

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
Test run with 219 tests in 38 suites passed after 4.559 seconds.
** TEST SUCCEEDED **
```
Visual layout and piece arrival animations remain to be verified on a composited display.
