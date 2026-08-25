# 2026-08-25 - QA hardening: Carlsen games

Branch: `qa/carlsen-games` (worktree `../chessanto-qa-carlsen`). This session
resumed a prior instance's uncommitted work per
`handoffs/NEXT-SESSION-QA-CARLSEN-RESUME.md`.

## What was scanned

All 65 monthly public archives of chess.com user `MagnusCarlsen`: 9,677 games,
849,519 mainline plies on standard-chess games. Archives were fetched once via
the extended `chesscom-smoke` tool (`--all --out-dir`) and cached as decoded
JSON, so rescans never touch the network.

## What was found and fixed (all in ChessCore, the shared layer)

The scan surfaced three distinct upstream defects. All three live in or behind
chesskit-swift's SAN handling; all three are fixed once in
`PGNCompatibility`/`ChessGame`, so every caller (app import, dashboard,
companion, report building) is covered.

1. **En passant after a replayed double push killed whole-game imports (603
   standard games).** Upstream `Game.make(move:from:)` applies moves directly
   to positions and never sets en passant state on double pushes (only
   `Board.move` does that), so any later genuine ep capture (`18. exf6` in the
   KIA game against TigranLPetrosyan was the first finding) failed with
   `invalidMove`. Fix: `parseSAN` now recognizes pawn-capture-to-empty-square
   tokens, validates the geometry strictly (mover pawn beside the victim,
   correct landing rank, destination empty), and constructs the capture move
   manually.
2. **Silently wrong disambiguated captures corrupted replays (53 games ended
   in FEN mismatches against chess.com's CurrentPosition tag).** Upstream
   `SANParser` drops the disambiguator when a capture marker is present:
   `Rhxf1` moved the d1 rook instead of the h1 rook without throwing, so the
   compatibility fallback never engaged and the final position diverged.
   Verified ply-by-ply against python-chess ground truth (divergence at exactly
   the `Rhxf1` ply). Fix, part one: `ChessGame.init(pgn:)` now routes any game
   whose move text contains an explicitly disambiguated piece move
   (`requiresFallback(for:)`, strict token-boundary regex) straight to
   `PGNCompatibility.parse`, because upstream cannot be trusted not to throw
   but to be silently wrong.
3. **Non-capture rank/square disambiguation and castling-with-check threw
   (43 more games).** `Rfd1`-style file disambiguation without a capture and
   `R1xe1`-style rank disambiguation returned nil upstream, and `O-O-O+`
   failed upstream's pattern matching when a check suffix was attached. Fix,
   part two: `parseSAN` now resolves all disambiguation forms itself (file,
   rank, square, with or without `x`), requiring exactly one legal source
   candidate, and delegates to upstream with the check/mate suffix stripped as
   a last resort.

Regression tests added to `PGNCompatibilityTests.swift`: routing predicate,
correct-source assertions for file/rank disambiguated captures, non-capture
file disambiguation, rejection of disambiguated moves naming no legal source,
en passant after a replayed double push (with captured-pawn removal asserted
in the resulting FEN), and castling-with-check suffix. ChessCore: 64 tests.

## What was found and deliberately not fixed

Chess960 and three-check games (313 of 9,677) still fail to load. PLAN.md line
199 declares Chess960 explicitly out of product scope, and the failures are
structural: upstream's `Castling` type computes king/rook squares from fixed
standard-chess coordinates with no way to express variant geometry, and
three-check FENs carry a `+0+0` counter suffix upstream rejects. Parsing these
games with standard rules would produce silently-wrong analysis rather than a
clean error, so they remain on the existing graceful load-error path. The scan
counts them separately (`Skipped variant games`) and does not assert on them.
This is recorded for triage, not silently swallowed.

Also noted, not fixed: `fen(at:)` reports `-` in the en passant field even
immediately after a double push (same upstream gap as defect 1). Harmless
today - stored analysis rows come from the same `fen(at:)` output, so both
sides agree - but worth knowing before anyone compares these FENs against
Stockfish-generated ones.

## Scan harness disposition

The prior instance left two overlapping scanners: an app-target test using the
real end-user path (`GameReplayViewModel(record:store:)` ->
`ReportBuilding.buildInput`/`buildReport`) and a redundant AnalysisKit package
executable that could not reach the app path at all (it re-implemented
`buildInput` inline). Kept the test, deleted the executable and its
Package.swift target, and removed its dead code from the smoke tool. The test
now takes its archives directory from `CARLSEN_QA_ARCHIVES_DIR` (falling back
to the directory used when the archives were fetched) and logs zero-key-moment
reports separately. The 9,361 zero-key-moment logs are an artifact of the
synthetic +-20cp analysis rows (no move ever loses eval to the played line, so
almost nothing is selectable as a key moment), not a product signal; realistic
classification would require running Stockfish over ~850k positions, out of
scope for this session.

## Verification (all commands run in the worktree, real output)

```
swift test --package-path Packages/ChessCore
-> Test run with 64 tests in 1 suite passed after 0.263 seconds.

swift test --package-path Packages/ChessComKit
-> Test run with 4 tests in 1 suite passed after 0.007 seconds.

swift test --package-path Packages/AnalysisKit
-> Test run with 195 tests in 6 suites passed after 21.035 seconds.

xcodegen generate
-> Created project at .../chessanto-qa-carlsen/Chessanto.xcodeproj

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
-> ** BUILD SUCCEEDED **

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
-> Test run with 201 tests in 37 suites passed after 1639.759 seconds.
-> ** TEST SUCCEEDED **
```

Full-archive scan through the app-path test
(`TEST_RUNNER_CARLSEN_QA_ARCHIVES_DIR=... xcodebuild ... -only-testing:
ChessantoTests/CarlsenQAScanTests`):

```
CARLSEN QA SCAN SUMMARY
Total games scanned: 9677
Skipped variant games (out of product scope): 313
Total plies replayed: 849519
PGN parse failures: 0
FEN mismatches: 0
Report building failures: 0
Zero key moment reports (logged, not asserted): 9361
Other issues: 0
** TEST SUCCEEDED **
```

Before the fixes the same scan reported 853 parse failures and 60 FEN
mismatches; every standard-chess failure is accounted for by the three defects
above and none remains.
