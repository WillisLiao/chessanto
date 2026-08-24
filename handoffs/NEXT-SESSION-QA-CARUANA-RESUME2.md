# Session: QA hardening - Caruana games (RESUME 2)

The prior two instances prepared everything but the scan never completed.
The second instance's scan run was interrupted by the user before any
output was produced. Read `handoffs/NEXT-SESSION-QA-CARUANA.md` in full
first; it still governs scope, non-goals, and the verification bar.

## State on qa/caruana-games

Commits `c8d311f` and `dfbda7b` contain all preparation:

- All 102 Caruana archives are cached at
  `/Users/willis/.gemini/antigravity-cli/brain/1f1424b9-e0b1-4afe-9dce-954ac04122f7/scratch/caruana_games`
  (`archive-YYYY-MM.json`, about 29 MB total, complete: 2013-03 through
  2026-08, 6933 games of which 6718 are standard chess).
- `ChessComKit` decode fix (optional `pgn`, `rules` field) plus its forced
  `ChessComFetchView` adaptation - already verified as a real bug fix,
  do not revert.
- The scan harness builds:
  `swift build --package-path Packages/AnalysisKit --target qa-caruana-runner`.
  It takes exactly one argument: the archive cache directory.

## Do this next

1. Run the scan to completion (do not abort it; it should take minutes,
   not hours):

   ```
   cd /Users/willis/Documents/chessanto-qa-caruana/Packages/AnalysisKit
   .build/debug/qa-caruana-runner /Users/willis/.gemini/antigravity-cli/brain/1f1424b9-e0b1-4afe-9dce-954ac04122f7/scratch/caruana_games 2>&1 | tee /tmp/caruana-scan.log
   ```

   Sanity expectations: "Found 102 archive files", 6933 raw games,
   215 non-standard skipped, roughly 6718 standard games scanned.
2. For every real failure printed: minimize to the smallest PGN fragment
   following `Packages/ChessCore/Tests/ChessCoreTests/RealGameFixtureTests.swift`,
   root-cause in the shared layer (`ChessCore`/`ChessComKit`), fix once in
   the shared function after tracing every caller, add a regression test.
3. Meet the full verification bar with quoted output per
   `handoffs/NEXT-SESSION-QA-CARUANA.md`:
   `swift test --package-path Packages/ChessCore`,
   `swift test --package-path Packages/ChessComKit`,
   `swift test --package-path Packages/AnalysisKit`,
   then from the worktree root `xcodegen generate`,
   `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build`
   and `... test`. Quote `** BUILD SUCCEEDED **`,
   `** TEST SUCCEEDED **`, and the
   "Test run with N tests in M suites" line.
4. Update `devlogs/2026-08-25-qa-caruana.md` (it exists and is honest
   about the interrupted state) and the
   `## Current state (2026-08-25) - QA Caruana games` section at the top
   of `handoffs/HANDOFF.md` with actual results.
5. Commit on `qa/caruana-games`. No merge. No push.
