# Devlog: Opening Book Coverage and Quality Pass

Date: 2026-08-25
Branch: `feature/opening-book-quality`

## Overview

Investigated opening book coverage and quality in `Packages/AnalysisKit/Sources/AnalysisKit/OpeningBook.swift`. Set up an automated coverage audit harness across a corpus of 4,698 real games from five grandmasters and masters (Hikaru Nakamura, Magnus Carlsen, Daniel Naroditsky, Levy Rozman / GothamChess, and Fabiano Caruana) fetched from Chess.com archives.

## Dataset and Architecture Analysis

- **Bundled data size**:
  - `eco.json`: 497 KB (3,803 raw entries decoded from lichess-org/chess-openings TSV files).
  - `eco-index.json`: 542 KB (3,801 precomputed unique EPD positions).
  - Total combined size is ~1.0 MB, well within the product scope ("a few MB, not a repertoire trainer").
- **Indexing mechanism**:
  - `OpeningBook.build(from:)` replays opening lines through `ChessGame` and keys entries by position EPD (`ChessGame.epd(fromFEN:)`), breaking transposition ties by preferring the longer line count and then deterministic lexicographical name order.
  - Precomputed at build time by `eco-indexer` so runtime load is a sub-second dictionary decode.
- **Audit Findings**:
  - **Endpoint-only vs Intermediate Subline Indexing**: In `OpeningBook.build`, only the final position of each line in `eco.json` is stored in `byEPD`. If a deep theoretical line (e.g. 10 moves deep) is played in a game, but intermediate plies (e.g. ply 7 or ply 9) lack dedicated separate entries in `eco.json`, games departing before the final move fall back to the last explicitly named ancestor entry.
  - **Transposition Correctness**: Position-keyed EPD hashing correctly handles move-order transpositions (e.g., 1. d4 Nf6 2. c4 e6 vs 1. c4 e6 2. d4 Nf6) to identify the resulting theoretical position.
  - **Non-standard Start Safety**: Standard book lookup gracefully returns `nil` on non-standard starts (Chess960 / FEN games).

## Verification

- **AnalysisKit Package Tests**:
  Command: `swift test --package-path Packages/AnalysisKit`
  Output:
  `Test run with 195 tests in 6 suites passed after 105.666 seconds.`
- **XcodeGen**:
  Command: `xcodegen generate`
  Output: `Created project at /Users/willis/Documents/chessanto-opening-book-quality/Chessanto.xcodeproj`
- **macOS Build**:
  Command: `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build`
  Output: `** BUILD SUCCEEDED **`

## Next Steps

- Integrate prefix/sub-ply theoretical awareness into `eco-indexer` so intermediate mainline positions are retained without ballooning index size.
- Expand coverage of modern lines in `fetch-eco.sh` where gaps occur.
