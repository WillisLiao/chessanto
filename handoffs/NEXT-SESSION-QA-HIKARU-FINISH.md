# Session: Finish QA hardening - Hikaru games (run the scan)

A prior session built and verified the full harness on `qa/hikaru-games`
(worktree `../chessanto-qa-hikaru`) but was cut short before running the
actual scan. Read `devlogs/2026-08-25-qa-hikaru.md` there first; it has the
complete state. The original task spec in
`handoffs/NEXT-SESSION-QA-HIKARU.md` still applies in full.

## What already exists (do not rebuild)

- All 152 Hikaru archives are fetched and cached as JSON (70,182 games) at
  `/Users/willis/.gemini/antigravity-cli/brain/ed28d818-b105-4ad9-9eaf-a0314594e75b/scratch/hikaru_archives`.
  No network needed.
- `App/Tests/ChessantoTests/HikaruQAScanTests.swift` runs the real app path
  (`GameReplayViewModel(record:store:)` -> `ReportBuilding.buildInput`/
  `buildReport`) over the cache, with the env var override
  `HIKARU_QA_ARCHIVES_DIR`.
- One shared-layer bug already fixed with regression test:
  PGN-less bughouse games no longer poison whole-archive decoding
  (`ChessComGame` decodes missing `pgn` as `""`; ChessComKit has 5 tests).

## Do this

1. In `/Users/willis/Documents/chessanto-qa-hikaru`, run:

   ```
   HIKARU_QA_ARCHIVES_DIR=/Users/willis/.gemini/antigravity-cli/brain/ed28d818-b105-4ad9-9eaf-a0314594e75b/scratch/hikaru_archives \
     xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' \
     -only-testing:ChessantoTests/HikaruQAScanTests test
   ```

   Expect a long run (70k games, roughly 7x the Carlsen corpus). Quote the
   HIKARU QA SCAN SUMMARY block.

2. Triage every failure. Variant/no-PGN games are skipped by the test itself.
   For standard-chess failures: minimize to a small fixture, root-cause in the
   shared layer (`ChessCore`/`ChessComKit`), fix once, add a regression test.
   Check first whether the failure matches one of the three defects already
   fixed unmerged on `qa/carlsen-games` (en passant after replayed double push,
   silently-wrong disambiguated captures, rank/square disambiguation +
   castling-with-check suffix, all in `PGNCompatibility`/`ChessGame`). If it
   does, port that identical fix here rather than re-deriving it.

3. Meet the full verification bar from `handoffs/NEXT-SESSION-QA-HIKARU.md`
   with real quoted output (three package suites, xcodegen if files changed,
   xcodebuild build ending `** BUILD SUCCEEDED **`, test ending
   `** TEST SUCCEEDED **` plus its "Test run with N tests in M suites" line).

4. Update `devlogs/2026-08-25-qa-hikaru.md` with findings and verification
   output, add/update the QA Hikaru section at the top of
   `handoffs/HANDOFF.md`, commit everything on `qa/hikaru-games`.
   Do not merge to main. Do not push.
