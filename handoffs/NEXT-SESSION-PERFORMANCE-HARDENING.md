# Session: Performance and scalability hardening

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md.

You have unlimited usage for this session. Do not ration effort or stop
early to save budget - this is a profiling-driven task, so real
measurement (Instruments, or at minimum wall-clock timing of real
operations) matters more than intuition about what's slow.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b perf/hardening-pass ../chessanto-perf-hardening main
```

Do all your work inside `../chessanto-perf-hardening`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

This app is a local-first analyzer built and tested so far mostly against
one or a handful of games at a time. Find out what actually happens at
real scale, and fix what's actually slow - don't optimize speculatively.

- **Build a large real library first**: fetch full chess.com archives for
  several prolific players (reuse the same approach as the QA-Carlsen /
  QA-Hikaru / QA-Caruana sessions if their branches exist, or fetch fresh)
  to get a library in the hundreds to low thousands of games. This is
  your test fixture for everything below.
- **App launch and library load time**: measure cold start with a large
  library. `Packages/Persistence` uses GRDB/SQLite - check query patterns
  (N+1 queries, missing indexes, loading full game records when only
  metadata is needed for a list view) before assuming the fix is caching
  or pagination.
- **Batch analysis throughput**: `App/Sources/Chessanto/Analysis/BatchAnalysisCoordinator.swift`
  and `EngineService.swift` drive Stockfish analysis across many
  positions. Profile whether the background queue is actually using
  available cores well, whether SQLite writes are batched sensibly
  (individual per-position writes vs. transactions), and whether
  cancellation/progress reporting stays responsive under load.
- **Dashboard/Player Brief aggregation**: `DashboardView.computeDashboard`
  and `backfillTrainingCards` (just changed recently by the rating-register
  propagation work - re-check their current form) aggregate across the
  whole library. At hundreds of games, confirm this doesn't become an
  every-launch bottleneck - if it's recomputing from scratch each time
  where incremental update would do, fix that, but only if profiling
  actually shows it matters.
- **Memory**: watch for retained state that should be releasable (analysis
  results for games not currently displayed, chat history for closed
  games) using Instruments' memory graph, not guesswork.
- **UI responsiveness under load**: scrubbing/exploration mode while a
  batch analysis is running in the background - confirm the generation-
  counter debouncing mentioned in `PLAN.md` actually holds up and the UI
  thread never blocks on engine or database work.

For every real bottleneck found: fix it with the smallest change that
addresses the measured cause. A missing SQLite index is one line; don't
reach for a new caching layer if an index or a batched transaction
already solves it.

## Non-goals

- Don't touch Play vs Engine, Chess960, search/filter, accessibility, or
  visual QA (separate sessions own those) - if a performance issue is
  inside one of their in-progress screens, note it in your devlog instead
  of editing their not-yet-merged work.
- Don't rewrite EngineKit's core UCI plumbing unless profiling proves it's
  the actual bottleneck - it already handles MultiPV parsing and
  generation-counter debouncing; verify before assuming it needs work.
- Don't add speculative caching, background pre-warming, or config knobs
  for scale the app doesn't actually need yet - every change here should
  be justified by a specific measurement you took and can quote.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable,
and for this session, "should be faster" without a before/after number is
equally not acceptable.

```
swift test --package-path Packages/Persistence
swift test --package-path Packages/EngineKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

For every fix, record the actual before/after measurement (wall-clock
time, query count, memory footprint - whatever's relevant to that fix)
against the large real library you built. A regression test or
benchmark that would catch the issue coming back is expected for
anything non-trivial (an N+1 query, a missing index, a blocking main-
thread call).

## When done

Write `devlogs/<date>-performance-hardening.md` with the library size you
tested against, every bottleneck found with its measurement, every fix
made with its before/after numbers, and the exact verification output.
Add a new `## Current state - Performance hardening` section at the TOP
of `handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`perf/hardening-pass`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
