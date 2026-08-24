# PGN Parser Hardening Devlog (2026-08-24)

## Summary

This session diagnosed and resolved the real end-user PGN load failure reported as `ChessKit.PGNParser.Error error 2` and `invalidMove("Rb5")`.
The defect prevented importing and viewing real Chess.com games such as `Hikaru vs Casablanca` (57 moves, 113 plies).
A narrow, robust `PGNCompatibility` parser was introduced in `ChessCore` to correctly handle disambiguated captures and all standard PGN movetext elements without accepting illegal chess or altering canonical SAN representations.

## 1. Reproduction Path and Exact Error

The reproduction follows the exact end-user entry path: loading a stored `GameRecord` through `GameReplayViewModel(record:store:)` and `buildReportInput(record:analyses:)`.
When parsing the PGN of the game `Hikaru vs Casablanca`, `ChessGame(pgn:)` threw:
`ChessKit.PGNParser.Error error 2: invalidMove("Rb5")`
Tracing move-by-move revealed that the parser failed at ply 73 (`37. Rb5`).
At move 37 in the actual game, White plays `37. Rb5`.
However, the parser reported that `Rb5` was impossible from the internal board state.

## 2. Root Cause in Code

The defect originated upstream in `chesskit-swift` (`SANParser+Regex.swift` line 21):
`static let disambiguation = #"[a-h]?[1-8]?(?=([a-h][1-8][#+]?)$)"#`
The lookahead `(?=([a-h][1-8][#+]?)$)` requires the disambiguating character (`[a-h]?[1-8]?`) to be directly followed by the target square `[a-h][1-8]`.
In Standard Algebraic Notation (SAN), whenever a move is both disambiguated and a capture (e.g., `30. Rfxe1`), an `x` character is placed between the disambiguating character and the target square (`f` followed by `x`, then `e1`).
Because `x` was present, `Pattern.disambiguation` failed to match `f` and returned an empty match, causing `disambiguation(for: "Rfxe1")` to return `nil`.
When disambiguation is `nil`, `SANParser.parse` evaluated candidate rooks able to move to `e1` (`b1` and `f1`) and arbitrarily picked the first candidate (`b1` instead of `f1`).
Moving the wrong rook (`b1` instead of `f1`) silently corrupted the internal board state: the rook on `b1` was moved to `e1`, leaving the other rook on `f1`.
Seven moves later at move 37 (`37. Rb5`), the real game had its rook on `b1` moving to `b5`, but the corrupted board state had its remaining rook on `f1`, which cannot legally move to `b5`, causing `invalidMove("Rb5")`.

## 3. Minimized Legal Regression Fixture

A minimal 3-ply reproduction fixture was isolated in `RealGameFixtureTests.swift`:
```pgn
[SetUp "1"]
[FEN "7k/p7/8/8/8/8/8/1R2nR1K w - - 0 1"]

1. Rfxe1 a5 2. Rb5 *
```
In this position, White has rooks on `b1` and `f1`, and Black has a knight on `e1`.
White plays `1. Rfxe1`, which captures the knight using the `f1` rook.
Because `chesskit-swift` erroneously moved the `b1` rook to `e1`, `2. Rb5` failed with `invalidMove("Rb5")`.

## 4. RED and GREEN Evidence

- **RED Evidence**: Running `swift test` on `Packages/ChessCore` against the minimal regression fixture produced the exact error:
  `RealGameFixtureTests.swift: Caught error: invalidMove("Rb5")`
- **GREEN Evidence**: With `PGNCompatibility` in place, running `swift test` passed all 44 tests across 4 suites in `ChessCoreTests`, including `minimalDisambiguatedCaptureRegression` and `parsesHikaruVsCasablancaGame` (validating all 113 plies, final FEN `1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57`, and UCI translations `f1e1` and `b1b5`).

## 5. Architectural Fix and Guarantees

A dedicated compatibility parser `PGNCompatibility.swift` was implemented inside `Packages/ChessCore/Sources/ChessCore/`:
1. `PGNCompatibility.parse(pgn:)` handles PGN tags, custom `SetUp` and `FEN` starting positions, movetext tokenization, annotations (`!`, `?`, `!?`, `??`, `!!`, `?!`, `□`, `$1`, `$2`), comments (including clock data `{[%clk ...]}`), variations `( ... )`, and game results.
2. For SAN move parsing, `parseSAN` detects piece moves with disambiguation (`file`, `rank`, or `square`) before `x` or target square, queries `Board.canMove` for legal candidate pieces of matching color and kind, filters by disambiguator, and synthesizes the exact `Move` with proper `disambiguation` and `result` metadata.
3. Standard moves, castling, en-passant, and pawn promotions are parsed with full legality validation.
4. Illegal chess moves (e.g. impossible piece destinations, moves through obstacles, moves into check, wrong color to move) are strictly rejected with `PGNCompatibility.Error.invalidMove(san)`.
5. Canonical SAN is never rewritten or mutated globally; re-exporting via `game.pgnString` preserves disambiguated move notation (e.g., `Rfxe1`).
6. `ChessGame.swift` required only a one-line change on line 18 (`self.game = try PGNCompatibility.parse(pgn: pgn)`), leaving the rest of the file untouched to prevent merge conflicts with active branches.

## 6. Full Validation Results

- `Packages/ChessCore`: 44 tests in 4 suites passed in `0.014s`.
- `Packages/Persistence`: 15 tests in 2 suites passed in `0.046s`.
- `Packages/AnalysisKit`: 15 tests in 2 suites passed in `0.052s`.
- App tests (`ChessantoTests`): `GameReplayViewModelPGNHardeningTests` passed and full macOS test suite succeeded with `** TEST SUCCEEDED **`.
- macOS build: `** BUILD SUCCEEDED **`.
- Database safety verified: live database SHA-256 hash at `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite` remains `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`.
- `git diff --check` passed with 0 errors.
- Verified 0 em dash characters across all project code and documentation.
