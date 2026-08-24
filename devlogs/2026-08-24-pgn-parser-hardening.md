# PGN Parser Hardening Devlog (2026-08-24)

## Summary

This session diagnosed and resolved the real end-user PGN load failure reported as `ChessKit.PGNParser.Error error 2` and `invalidMove("Rb5")`.
The defect prevented importing and viewing real Chess.com games such as `Hikaru vs Casablanca` (57 moves, 113 plies).
A targeted compatibility adapter was implemented in `ChessCore` as a fallback when upstream `ChessKit.Game(pgn:)` throws.
The compatibility parser resolves affected disambiguated piece-capture tokens using `ChessKit.Board.move(pieceAt:to:)` to obtain canonical move metadata, requiring exactly one legal source candidate, while preserving upstream behavior for ordinary PGNs.

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
- **GREEN Evidence**: With the compatibility fallback in place, running `swift test` passed all 47 tests across 4 suites in `ChessCoreTests`, including `minimalDisambiguatedCaptureRegression` and `parsesHikaruVsCasablancaGame` (validating all 113 plies, final FEN `1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57`, and UCI moves `f1e1` and `b1b5`).

## 5. Architectural Design and Guarantees

1. `ChessGame.init(pgn:)` retains `ChessKit.Game(pgn:)` as the primary parser and invokes `PGNCompatibility.parse(pgn:)` only when upstream parsing throws.
2. In `PGNCompatibility.parseSAN`, only affected disambiguated piece-capture tokens (`[KQRBN]` moves containing `x` with a preceding disambiguator) are intercepted.
3. Candidate source pieces are filtered using `Board.canMove` and the SAN disambiguator (`file`, `rank`, or `square`).
4. Exactly one legal source candidate is required (`guard candidates.count == 1 else { return nil }`).
5. Legal move creation, capture metadata, check state, and canonical disambiguation are obtained directly through `ChessKit.Board.move(pieceAt:to:)` with no JSON encoding or synthetic serialization.
6. All other tokens (pawn moves, non-disambiguated piece moves, castling) delegate directly to `ChessKit.SANParser.parse`.
7. Full regression coverage verifies ordinary upstream games, compact PGN formats (`1.e4 e5`), attached move numbers (`1...d5`), comments (`{[%clk ...]}`), NAGs (`$1`, `$2`), annotations (`!`, `?`, `!?`, `??`), variations, custom `SetUp`/`FEN` positions, castling, promotion, and en passant.
8. Illegal chess moves remain strictly rejected with `PGNCompatibility.Error.invalidMove(san)`.
9. Canonical SAN is never mutated globally; re-exporting via `game.pgnString` preserves standard SAN notation.

## 6. Exact Verification Commands and Test Counts

- `swift test` in `Packages/ChessCore`: Executed 47 tests across 4 suites with 0 failures in `0.016s`.
- `swift test` in `Packages/Persistence`: Executed 44 tests across 2 suites with 0 failures in `0.570s`.
- `swift test` in `Packages/AnalysisKit`: Executed 172 tests across 6 suites with 0 failures in `111.342s`.
- `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test`: Full test suite passed with `** TEST SUCCEEDED **`.
- `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' -configuration Release build`: Build succeeded with `** BUILD SUCCEEDED **`.
- Database safety verified: live database SHA-256 hash at `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite` remains `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`.
- `git diff --check` passed with 0 errors.
- Verified 0 em dash characters across all project code and documentation.
