# 2026-08-24 - Move-quality flags (P4.2 slice)

## Context & %clk premise re-verification

The backlog document `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` claimed that `[%clk]` comments are "already parsed from chess.com PGNs per the M1 and M2 records and are never used".
Before writing any code, we performed a thorough codebase-wide scan across all packages and the app target for `%clk`, `clock`, `timeSpent`, and related terms.

### Investigation findings on %clk:
1. `Packages/ChessComKit`: `ChessComGame` decodes the raw JSON response from chess.com where `pgn` is stored as an unparsed `String`. No PGN comment or clock parsing exists in `ChessComKit`.
2. `Packages/ChessCore`: `ChessGame.init(pgn:)` passes the PGN string into `chesskit-swift`'s `Game(pgn:)`. No per-move clock annotations are extracted or surfaced.
3. `Packages/AnalysisKit`: `PlyRecord` and `ReportInput` carry `fen`, `lines`, and `playedUCI`. Neither struct has any per-move clock or timeSpent field.
4. `App`: `EngineService` uses `ContinuousClock()` for engine evaluation timeouts, but nowhere in the app is clock time extracted from imported PGNs.

**Conclusion**: The backlog premise was false. No clock parsing exists in the codebase today. As directed in `handoffs/NEXT-SESSION-MOVE-QUALITY.md`, because the premise was disproven, we treated clock parsing from scratch as a stretch goal and prioritized the core scope: the move-quality flags.

## The core scope: move-quality flags

We implemented move-quality detection as structural facts derivable directly from `ReportInput` move replay, requiring no new engine evaluations or attack-geometry primitives.

### 1. `MoveQualityFact` definition
In `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift`, we introduced `MoveQualityFact`:
- `ply: Int`
- `movedPieceKind: PieceKind`
- `isCapture: Bool`
- `capturedPieceKind: PieceKind?`
- `isCheck: Bool`
- `isCheckmate: Bool`
- `isRedevelopedPiece: Bool`
- `isMovedTwiceBeforeCastling: Bool`
- `isEarlyQueenMove: Bool`

`MoveQualityFact` is attached to `KeyMoment` as an optional field (`moveQuality: MoveQualityFact? = nil`), preserving backwards compatibility across all callers.

### 2. Operational rules and design decisions

#### Capture, check, and checkmate detection
- `ThemeDetector.moveQuality` replays the played UCI move (`input.plies[p].playedUCI`) starting from the pre-move FEN (`input.plies[p - 1].fen`) using `ChessGame.replayLine`.
- The replayed move directly supplies `movedPieceKind`, `capturedPieceKind`, `isCapture` (`capturedPieceKind != nil`), `isCheck`, and `isCheckmate`.

#### Opening phase definition and piece tracking
- **Definition of opening phase**: Moves 1 through 10 (plies 1 to 20).
- **Reasoning**: In classical chess pedagogy, opening principles (developing minor pieces, securing the center, achieving king safety) govern the first 10 full moves. Setting a fixed threshold of `ply <= 20` is reliable, standard, and independent of whether opening book matches end early.
- **Piece tracking**: `ThemeDetector.trackMainline` parses the starting board from `input.plies[0].fen` and tracks each piece's movement count and current square as mainline moves are replayed up to ply `p`.
- **Redeveloped piece**: If a piece (non-pawn and non-king) is on its 2nd or later move (`moveCount >= 1` before the move is made) during the opening phase (`ply <= 20`), `isRedevelopedPiece` is flagged `true`. Pawn moves (e.g. 1. e3 ... 2. e4) do not constitute piece redevelopment and are not flagged.

#### Same piece moved twice before castling
- We track castling events per side (`whiteCastled`, `blackCastled`) during mainline replay.
- If a piece (non-pawn, non-king) moves for a 2nd or later time in the opening phase while the mover's side has not yet castled, `isMovedTwiceBeforeCastling` is flagged `true`.
- **Pedagogical distinction from general redevelopment**: Moving the same piece multiple times while the king remains uncastled in the center is a classic beginner error that compromises king safety. In contrast, moving a piece again *after* castling (such as Ng5 attacking f7 once the king is tucked away) is often a sound tactical operation. Distinguishing these two states provides clearer diagnostic feedback.

#### Early queen move
- **Definition**: The mover's queen first leaves its starting square (`d1` for White, `d8` for Black) on move 1, 2, 3, or 4 (move number `(ply + 1) / 2 < 5`, i.e. `ply <= 8`).
- **Reasoning**: Bringing the queen out before minor piece development (e.g. 2. Qh5 or 3. Qf3) exposes the queen to tempo-gaining attacks by opponent minor pieces.
- If the queen leaves its home square on move 5 or later, or never moves, `isEarlyQueenMove` is `false`. Subsequent queen moves after its first departure are categorized under piece redevelopment rather than early queen departure.

### 3. `FactAuditor` and `ReportBuilder` integration
- `FactAuditor.verify(_ fact: MoveQualityFact, input: ReportInput)` independently re-derives `ThemeDetector.moveQuality(input: input, ply: fact.ply)` and asserts equality across all fields.
- `FactAuditor.audit` audits `moment.moveQuality` alongside existing facts.
- `ReportBuilder.build` passes `ThemeDetector.moveQuality(input: input, ply: p)` when building each candidate `KeyMoment`.
- `KeyMomentSelector` retains its eval-swing and tactical consequence prioritization, allowing `MoveQualityFact` to serve as explanatory context on selected moments without prematurely promoting non-blunders to key moments.

## Real fixture validation (Magnus Carlsen vs artin10862)

We ran a comprehensive scan of all 55 plies in `real-fixture-game-report-input.json` via `RealFixtureGoldenTests.swift`:
- All 54 played plies produced valid, audited `MoveQualityFact` records with zero dropped facts.
- Specific key plies hand-verified:
  - Ply 8 (4... exd4): Pawn capture correctly flagged (`isCapture: true`, `capturedPieceKind: .pawn`, `isCheck: false`, `isRedevelopedPiece: false`).
  - Ply 9 (5. Qxd4): Queen capture on move 5 (`isCapture: true`, `capturedPieceKind: .pawn`, `movedPieceKind: .queen`, `isEarlyQueenMove: false` since move 5 is not < 5, `isRedevelopedPiece: false` as first queen move).
  - Ply 17 (9. Qd3): Queen moving a second time in the opening before White castled (White castled on move 10, ply 19) correctly flagged as `isRedevelopedPiece: true` and `isMovedTwiceBeforeCastling: true`.
  - Ply 21 (11. Nxd5): Knight capture on move 11 correctly flagged as `isCapture: true`, `isRedevelopedPiece: false` (past move 10 opening cutoff), `isMovedTwiceBeforeCastling: false` (White castled at ply 19).
  - Ply 43 (22. Qxd8+): Queen capture with check correctly flagged (`isCapture: true`, `capturedPieceKind: .rook`, `isCheck: true`, `isCheckmate: false`).
- Both standard and beginner golden report fixtures pass unmodified.

## Validation results

1. `swift test` in `Packages/AnalysisKit`: 135 tests across 6 suites (all passed, up from 126).
2. `swift test` in `Packages/CoachKit`: 74 tests across 8 suites (all passed).
3. `swift test` in `Packages/CompanionKit`: 32 tests across 3 suites (all passed).
4. `swift test` in `Packages/ChessCore`: 29 tests across 4 suites (all passed).
5. `swift test` in `Packages/Persistence`: 44 tests across 2 suites (all passed).
6. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build`: `** BUILD SUCCEEDED **`.
7. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test`: `** TEST SUCCEEDED **`, 179 tests across 34 suites passed.
