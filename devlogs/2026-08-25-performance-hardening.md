# 2026-08-25 - Performance hardening pass (session 1: setup and code reading)

This session resumed `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md` and got through state
verification plus the code-reading half of step (b).
No code was changed anywhere.
The worktree is untouched and still clean at `0267e6b` on `perf/hardening-pass`.

## State verified this session

- Worktree `/Users/willis/Documents/chessanto-perf-hardening` exists, is on
  `perf/hardening-pass` at `0267e6b`, and has a clean `git status`.
- Scratch tooling at `/var/folders/.../chessanto-perf/bulkimport/.build/release/` still holds
  release-built `analyzer`, `bench`, and `bulkimport`.
- Fixture `chessanto-perf.sqlite`: 3594 games, 0 analysis rows (untouched by this session's run,
  see below).
- Live database SHA-256 re-checked and still
  `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`.
  The app was not launched this session.

## Background analysis run started (step a)

Launched the analyzer against a NEW dedicated copy so the two recorded fixture copies stay pristine:

- Database: `/var/folders/94/2p2pbcss4pddjvbrslnjbtyc0000gp/T/opencode/chessanto-perf/chessanto-analyzer.sqlite`
- Command: `analyzer <that db> 40 fast`
- Log: `/var/folders/94/2p2pbcss4pddjvbrslnjbtyc0000gp/T/opencode/chessanto-perf/analyzer-run.log`
- At wrap-up (14 minutes in) it had finished about 1 game under heavy machine load, consistent with
  the 71 s/game smoke figure.
  It runs under `nohup`, so it may still be alive when the next session starts - check
  `ps -ef | grep bulkimport/.build/release/analyzer` and the row count before relaunching anything.
- The analyzer is idempotent, so if the process died the next session can simply rerun the same
  command on the same copy and it resumes from whatever landed.
- Next session should treat this copy as the dashboard fixture (step c) once it reaches a useful
  analyzed count, and can stop waiting on it at any time - every finished game adds coverage.

## Code reading done for step (b) - the seam map

These findings save the next session the reading pass.
All paths are relative to the worktree root.

### Fix 1: metadata-only sidebar fetch

- `GameStore.allGames()` (`Packages/Persistence/Sources/Persistence/GameStore.swift:165`) fetches
  full rows including `pgn`.
  `recentlyDeletedGames()` right below it has the same problem and should be fixed in the same
  change.
- `GameRecord.pgn` is a non-optional `String` (`Packages/Persistence/Sources/Persistence/GameRecord.swift:15`),
  so a column-limited fetch cannot decode into `GameRecord`.
  The clean shape is a small metadata-only struct in Persistence (same columns minus `pgn`) plus an
  `allGameMetadata()` query, with `GameLibrary.games` switching to it.
- Every sidebar consumer needs only metadata: `GameRow` fields, `BriefIdentity.candidates(in:)`
  (white/black only), `BatchAnalysisCoordinator.unanalyzed` and `.title(for:)` (id and names only),
  pin/favorite/context-menu actions (id plus flags).
- Consumers that genuinely need PGN text from the library list, and their lazy-fix shapes:
  - Detail pane: `ContentView.swift:56` passes the whole record into `GameReplayViewModel.init`,
    which parses `record.pgn`.
    Change the detail destination to fetch the full record via `library.store.game(id:)` when a
    game is opened - one row, one time.
  - Dashboard backfill/dashboard compute and Player Brief: `DashboardView.backfillTrainingCards`
    and `.computeDashboard` plus `PlayerBriefView.buildSnapshot` call
    `ReportBuilding.buildInput(record:analysisRows:)`, which parses `record.pgn`.
    They only need PGNs for user-matched games that have analysis rows, so add one Persistence
    helper like `pgns(gameIds:) -> [Int64: String]` fetched in a single query inside those static
    functions instead of keeping PGNs in the published library array.
  - Openings enrichment (fix 2): `GameLibrary.openings(for:)` (`App/Sources/Chessanto/GameLibrary.swift:185`)
    re-parses and FEN-replays EVERY analyzed game on EVERY reload.
    PGN text never changes after import, so opening names are stable per gameId - memoize
    `[Int64: String]` across reloads and only parse games whose id is missing from the cache.
    With the metadata-only library this function also needs the bulk PGN map above rather than
    `game.pgn`.

### Fix 3: suppress full reloads during batch

- `ContentView.startBatchAnalysis(of:)` (`App/Sources/Chessanto/ContentView.swift:555`) calls
  `library.reload()` inside the per-finished-game closure (line 567), making batch cost
  O(games x library) and re-running the openings replay each time.
- Smallest shape: one targeted method on `GameLibrary` that refreshes only what batch progress
  changes (`analyzedGameIDs`, maybe the single changed game's row) or defers the full reload to
  batch completion.
  Note `ContentView.onChange(of: library.games.map(\.id))` fires companion catalog publishing on
  every reload - another reason the current per-game reload is expensive.

### Step (c) notes (dashboard)

- Confirmed in source: `DashboardView.load` runs `backfillTrainingCards` and then
  `computeDashboard`, and EACH loops `store.analysis(gameId:)` over every user-matched game and
  builds a full `GameReport` per game per open (`DashboardView.swift:330-438`).
  `PlayerBriefView.buildSnapshot` (`PlayerBriefView.swift:558`) is a third copy of the same N+1.
  A single shared fetch (one `WHERE gameId IN (...)` read of analysis rows grouped in memory)
  would collapse all three.
- Backfill also takes a write transaction per game via reconcile even when nothing changed;
  measure whether skipping unchanged reconciles matters before touching it.

## Not done this session

- No measurements taken beyond the previous session's quoted baselines (allGames ~46-66 ms CPU,
  median ~50 ms).
- No fixes implemented, so no regression tests written yet.
- Verification bar not run (nothing to run it on).

## Next session pickup

1. Check the analyzer run (log + `SELECT COUNT(DISTINCT gameId) FROM analysis` on
   `chessanto-analyzer.sqlite`); let it finish 40 games or proceed early.
2. Implement fixes 1-3 using the seam map above, measuring each against the bench tool
   (`bench <db> allGames | openings | queueSnapshot | analysisAll`) before and after.
3. Then steps (c) through (g) of the resume doc as written.
