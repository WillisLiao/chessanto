# QA Edge Cases and Adversarial PGN Ingestion

**Date**: 2026-08-24
**Branch**: `qa/edge-case-pgns`
**Scope**: Hardening PGN parsing, library ingestion, move replay, clock annotations, and report generation against adversarial and edge-case PGNs.

---

## 1. Summary of Work

We systematically tested, discovered edge-case bugs, and hardened the entire PGN pipeline across `ChessCore`, `AnalysisKit`, `Persistence`, and `App`:

1. **Adversarial PGN Ingestion & Formats**:
   - **Castling Notation**: Normalized numeric castling (`0-0`, `0-0-0`, `0-0+`, `0-0#`) to standard algebraic letters (`O-O`, `O-O-O`) across PGN movetext preprocessing and SAN parsers. Upstream ChessKit previously silently swallowed `0-0` without throwing, leading to truncated games; normalization ensures flawless parsing everywhere.
   - **Line Endings & Character Encodings**: Standardized Windows CRLF (`\r\n`), classic Mac CR (`\r`), and UTF-8 Byte Order Mark (`\u{FEFF}`).
   - **PGN Escapes & Comments**: Stripped PGN `%` escape lines and movetext semicolon line comments (`;...`) while preserving brace comments (`{...}`).
   - **Alternative Promotions**: Handled `e8Q`, `exd8N`, `e8(Q)`, `e8/Q` alongside standard `e8=Q`.
   - **En Passant Annotations**: Handled trailing `e.p.` / `ep` suffixes (e.g. `exd6ep` -> `exd6`).
   - **Evaluation Suffixes & NAGs**: Cleaned traditional and ChessBase evaluation suffixes (`+-`, `-+`, `=+`, `+/=`, `+/-`, `~=`, `⩲`, `⩱`, `±`, `∓`, `⨁`, `∞`, `=`).
   - **Custom FEN without SetUp tag**: Supported positions with `[FEN "..."]` even when `[SetUp "1"]` tag was omitted.
   - **Headerless / Bare PGNs**: Enhanced `PGNTagScanner` and `GameLibrary.importPGN` so that pasting or dropping bare move text (e.g. `1. e4 e5 2. Nf3 Nc6`) imports successfully with default player tags.

2. **Game Terminations & Move Count Extremes**:
   - Verified games ending in abandonment (`[Termination "... won by abandonment"]`), timeout (`[Termination "... won on time"]`), stalemate, draw by agreement, and unfinished games with `*`.
   - Verified 0-move games, 1-move games, 2-move Fool's mate, and 160-move (320-ply) marathon games across `ChessGame`, `GameReplayViewModel`, and `ReportBuilding`.

3. **Clock Annotations & Time Pressure Takeaways**:
   - Expanded `ChessGame.parseClockAnnotation` to support `[%clk HH:MM:SS]`, `[%clk MM:SS]`, tenths/hundredths of a second (e.g. `[%clk 0:02:58.7]`), and plain seconds (e.g. `[%clk 300]`).
   - Added `ChessGame.clockSeconds(at:)` and wired move clock times into `ReportBuilding.buildInput`, enabling the rule-based `timePressureTakeaway` to fire on real games with time trouble.

4. **Test Suites Added**:
   - `Packages/ChessCore/Tests/ChessCoreTests/AdversarialPGNTests.swift` (20 new targeted edge-case unit tests).
   - `App/Tests/ChessantoTests/AdversarialPGNImportTests.swift` (11 new integration tests covering `PGNTagScanner`, `GameLibrary.importPGN`, `GameReplayViewModel`, and `ReportBuilding`).

---

## 2. Test Verification Suite Output

### 1. `swift test --package-path Packages/ChessCore`
```
Suite AdversarialPGNTests passed after 0.968 seconds.
Suite ChessGameTests passed after 0.559 seconds.
Suite LegalMoveCountTests passed after 0.561 seconds.
Suite PGNCompatibilityTests passed after 0.065 seconds.
Suite RealGameFixtureTests passed after 0.838 seconds.
Test run with 77 tests in 2 suites passed after 0.969 seconds.
```

### 2. `swift test --package-path Packages/ChessComKit`
```
Suite ChessComKitTests passed after 0.009 seconds.
Test run with 4 tests in 1 suite passed after 0.009 seconds.
```

### 3. `swift test --package-path Packages/AnalysisKit`
```
Suite AccuracyTests passed after 4.123 seconds.
Suite AnalysisKitTests passed after 4.124 seconds.
Suite EvalLabelTests passed after 4.124 seconds.
Suite GameAccuracyTests passed after 4.124 seconds.
Suite MoveClassifierTests passed after 4.124 seconds.
Suite WinProbabilityTests passed after 4.124 seconds.
Test run with 195 tests in 6 suites passed after 73.781 seconds.
```

### 4. `swift test --package-path Packages/Persistence`
```
Suite "Analysis provenance" passed after 0.218 seconds.
Suite PersistenceTests passed after 0.934 seconds.
Test run with 44 tests in 2 suites passed after 0.934 seconds.
```

### 5. `xcodegen generate`
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/willis/Documents/chessanto-qa-edge-cases/Chessanto.xcodeproj
```

### 6. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build`
```
** BUILD SUCCEEDED **
```

### 7. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test`
```
Test run with 211 tests in 37 suites passed after 3.238 seconds.
** TEST SUCCEEDED **
```
