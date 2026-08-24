# Resume: Performance/scalability hardening pass for Chessanto

Start by reading `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING.md` in
`/Users/willis/Documents/chessanto`, then `handoffs/HANDOFF.md` and
`PLAN.md` in full, and follow them.
Do not re-litigate PLAN.md's already-made decisions.
This is a profiling-driven task: every fix needs a quoted before/after
measurement against a large real library.
The verification bar and devlog/handoff/commit rules are all specified in
that file - follow them exactly.

## State already in place (reuse it, do not redo)

1. Worktree: `/Users/willis/Documents/chessanto-perf-hardening` on branch
   `perf/hardening-pass` (from main @ `0267e6b`).
   Do all edits there.
   XcodeGen project: run `xcodegen generate` after adding/removing Swift files.

2. Large real library fixture: 3594 real chess.com games (Hikaru 2284,
   DanielNaroditsky 935, MagnusCarlsen 375 recent monthly archives),
   imported through the same field extraction as `GameLibrary.importPGN`.
   userProfile row: `chessComUsername='Hikaru'`, confirmed=1, onboarded=1,
   coachEnabled=0.
   Copies of the fixture DB (14MB):
   - `/var/folders/94/2p2pbcss4pddjvbrslnjbtyc0000gp/T/opencode/chessanto-perf/chessanto-perf.sqlite`
   - `~/Library/Containers/com.chessanto.app/Data/tmp/perf-hardening/chessanto-perf.sqlite`

   THE APP IS SANDBOXED: it can only open the container copy.
   Launches must set BOTH `CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1` and
   `CHESSANTO_DATABASE_PATH=<container path>`.
   Launching the inner binary `<App>/Contents/MacOS/Chessanto` directly via
   Process passes env vars; `open -a` does NOT pass env and would hit the
   live database.

3. Scratch tooling (SPM package, release-built) at
   `/var/folders/94/2p2pbcss4pddjvbrslnjbtyc0000gp/T/opencode/chessanto-perf/bulkimport`
   with path deps on the worktree's Packages.
   Three executables:
   - `bulkimport <db> <pgn-dir>`: rebuilds the fixture (`pgns` dir sits next to it).
   - `analyzer <db> <count> <fast|standard>`: real in-process Stockfish via
     EngineKit, production-shaped per-ply rows (MultiPV 3, depth budget +
     movetime ceiling stop, white-perspective normalization, delete-first
     per-ply save, terminal-mate synthetic record), picks every 90th
     unanalyzed game, idempotent (reuse check).
     NNUE nets are already fetched into the WORKTREE `App/Resources/`.
     Smoke test passed: 1 game, 147 plies, 71s wall under heavy load.
   - `bench <db> <case>`: micro-benchmarks (`allGames | openings |
     queueSnapshot | analysisAll`), prints CPU time per iteration.
   These tools are throwaway; do not commit them.

4. Baselines measured so far (3594-game library):
   - `GameStore.allGames()`: ~46-66ms CPU per call (median ~50ms), because it
     materializes the full `pgn` column of every game.
     It runs synchronously on the MAIN actor at every app launch
     (`GameLibrary.init -> reload()`) and again after every mutation,
     including once per finished game during batch analysis
     (`ContentView.startBatchAnalysis` calls `library.reload()` inside the
     per-game closure).
   - Live database safety verified: SHA-256 of
     `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`
     = `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`
     (matches the recorded hash in HANDOFF.md; 15 games; byte-identical,
     untouched).

5. Bottleneck shortlist from code reading (confirm each with a measurement
   before fixing):
   - Sidebar/library list loads full PGN text for all games on main actor
     (above), plus `GameLibrary.openings(for:)` re-parses and FEN-replays
     EVERY analyzed game on EVERY reload (`GameLibrary.swift:185-197`).
   - Batch analysis: serial engine loop is by design; but per-finished-game
     `library.reload()` makes batch cost O(games x library) and re-runs the
     openings replay.
   - `DashboardView.load`: `backfillTrainingCards` + `computeDashboard` each
     do an N+1 `store.analysis(gameId:)` over every user-matched game and
     rebuild a complete `GameReport` per game per open; backfill additionally
     takes a write transaction per game even when nothing changed
     (`DashboardView.swift:253-368`, `330-438`).
     `PlayerBriefView.buildSnapshot` repeats the same pattern.
   - `saveAnalysis` is one transaction per ply (crash-safe by design; only
     change if measurement shows fsync overhead matters).
   - Missing-index candidates to check with EXPLAIN QUERY PLAN:
     `chatMessage.gameId`; trainingQueueSnapshot's COLLATE NOCASE OR filter
     (may scan joined rows).

## Measurement discipline (important)

This Mac is shared with several concurrent agent sessions right now (load
average was ~90 on 8 cores).
Wall-clock numbers are noisy.
Use medians over >=5 runs and/or getrusage CPU time (bench does this), quote
conditions, and interleave A/B where practical.
Before any timed app launch:
`pkill -9 -f "Chessanto.app/Contents/MacOS"` (stray instances poison
AX-based probes).
A cold-start timer script exists at
`/var/folders/94/2p2pbcss4pddjvbrslnjbtyc0000gp/T/opencode/chessanto-perf/coldstart-timer.swift`
(spawns the Release binary directly with the override env, polls the spawned
PID's AX tree until sidebar shows game text, prints window=/ready= seconds).
Its last run failed only because the Release build product had vanished from
DerivedData (`Chessanto-hewhmgdnznguifbwstbpqxzurlct`) - rebuild Release in
the worktree first:

```
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' -configuration Release build
```

## Suggested remaining sequence

a) Kick off `.build/release/analyzer <fixture-db-copy> 40 fast` in the
   background (about 45-75 min under load) to give the dashboard real
   analyzed games.
   Use a COPY of the fixture, not the only copy.
b) While it runs: implement + test the launch-path fixes (metadata-only
   sidebar query, incremental/cached openings enrichment, suppress full
   reloads during batch), each justified by the allGames/openings baseline
   numbers.
c) When analysis lands: baseline Dashboard open (`computeDashboard` +
   `backfillTrainingCards` + `trainingQueueSnapshot` wall/CPU via bench cases
   `queueSnapshot`/`analysisAll` and an app-level probe), then fix what the
   numbers justify (e.g. skip write when reconcile is unchanged; avoid double
   N+1 by reusing backfilled reports or fetching analysis rows in one query).
d) Spot-check UI responsiveness during a small real batch via the app + AX
   scripts in the repo (`scripts/axprobe.swift` etc.), and memory with
   `footprint`/Instruments if available.
e) Regression tests: Persistence test asserting metadata-only fetch does not
   load pgn text (or equivalent observable), plus whatever guards your fixes
   need.
f) Full verification bar from the handoff doc:
   `swift test --package-path Packages/Persistence`,
   `swift test --package-path Packages/EngineKit`, `xcodegen generate`,
   `xcodebuild build + test` (quote the exact final lines and the
   "Test run with N tests in M suites" line).
g) Write `devlogs/<date>-performance-hardening.md` (library size,
   bottlenecks with measurements, fixes with before/after numbers,
   verification output).
   Add a new `## Current state - Performance hardening` section at the TOP of
   `handoffs/HANDOFF.md` (do not delete existing history).
   Commit everything on `perf/hardening-pass`.
   Do NOT merge to main.
   Do NOT push.

## Style/rules

Never use an em dash anywhere (use plain dash).
No boilerplate or speculative abstractions; smallest fix that addresses the
measured cause.
Never touch files owned by the other in-progress feature branches (Play vs
Engine, Chess960, search/filter, accessibility, visual QA) - note issues in
the devlog instead.
Never write to the live database; verify its SHA-256 stays
`3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f` after any
app launches you do.
