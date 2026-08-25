# Overnight integration resume: faster procedure

The previous run of this task merged 4 branches in several hours before
being stopped for taking too long - roughly 1.5-2 hours per branch. That
is too slow for a task this mechanical. This file supersedes Phase 1's
procedure in `handoffs/OVERNIGHT-INTEGRATION-MASTER.md` with a faster
one. Read that file first for everything else (safety rules, ground
truth, the verification bar's exact commands, Phase 2, Phase 3,
bookkeeping) - all of it still applies. Only the per-branch merge
procedure below replaces its Phase 1 section.

## Why the last run was slow, and what changes

The previous procedure did, per branch: read the branch's full devlog,
re-verify standalone in its own worktree (full build + full test), merge
into main, resolve conflicts, re-verify again on main (another full
build + full test), commit, push. That is two complete build-and-test
cycles per branch plus a lot of reading, on a task where the actual
git-level work (merge, resolve two predictable conflict spots) is small.

Faster procedure, same safety guarantees:

1. **Skip the standalone worktree re-verification step entirely.** Do
   not `cd` into each branch's own worktree and build/test it there
   first. Go straight to merging into `main`. If the merged result fails
   to build or test, that tells you just as much as a standalone check
   would have, and you've saved the redundant cycle for every branch
   that would have passed anyway (most of them, based on the first four).
2. **Don't read full devlogs up front.** You don't need the branch
   author's narrative to perform a mechanical merge. Only look at a
   branch's devlog or `HANDOFF.md` section if you actually hit a merge
   conflict you don't understand from the diff alone.
3. **Batch straightforward branches before verifying, when it's safe
   to.** If a branch's diff clearly doesn't touch files another
   already-merged-this-run branch touched (check with
   `git diff --stat main..<branch>` before merging), you may merge two
   or three such branches back to back and run the verification bar
   once at the end of the batch instead of after each one. If the batch
   verification fails, bisect by re-running the build/test after each
   branch in the batch (in the order you merged them) until you find
   which one broke it - don't guess.
   Do NOT batch branches you have reason to expect will conflict with
   each other or with what's already merged (the QA branches touching
   `Packages/AnalysisKit/Package.swift` are a known conflict pattern -
   merge those one at a time, per the guidance in the master doc, since
   conflict resolution needs to happen at each step anyway).
4. **One verification bar run per branch or batch, not two.** After
   merging (a single branch or a batch), run the full verification bar
   from `handoffs/OVERNIGHT-INTEGRATION-MASTER.md` exactly once. If it
   passes, commit and push immediately, then move on.
5. **Tighter time-box: 20 minutes per branch, not 45.** This is a
   mechanical task; if a single branch's merge-plus-verify is taking
   longer than that, something is actually wrong (a real conflict you're
   struggling with, or a stuck build) - apply the circuit breaker from
   the master doc immediately rather than continuing to grind.
6. **If a single build or test run is taking more than about 10
   minutes**, that's very likely the known stale-DerivedData/SPM-cache
   quirk documented in the master doc, not real compilation work -
   check for the `unable to write file ... pack/*.pack` error pattern
   and clear that specific `DerivedData/Chessanto-*` folder rather than
   waiting it out.

## Current real state (verified just now, use this instead of rediscovering it)

Merged into `main` already: `qa/edge-case-pgns`, `qa/carlsen-games`,
`feature/chess960-core`, `feature/play-vs-engine-core`. Do a quick
`git log --oneline -5` yourself to confirm this is still accurate (it
should be - nothing else has touched `main` since), then move straight
to the remaining branches without re-verifying the four above:

```
qa/hikaru-games
qa/caruana-games
feature/chess960-app-integration      (depends on feature/chess960-core, already in main - fine to do now)
feature/play-vs-engine-ui             (depends on feature/play-vs-engine-core, already in main - fine to do now)
feature/library-search-filter
feature/accessibility-matrix
qa/visual-pass
qa/coach-real-model-verification
feature/opening-book-quality
```

`qa/hikaru-games` and `qa/caruana-games` both likely touch
`Packages/AnalysisKit/Package.swift` the same way `qa/carlsen-games` did
(a throwaway scan-runner executable target) - handle exactly like the
master doc's conflict-resolution guidance says: drop the throwaway
runner, keep the real fixes and tests. Do these two one at a time, not
batched together, since both are likely to conflict with each other in
the same file.

The rest (`chess960-app-integration`, `play-vs-engine-ui`,
`library-search-filter`, `accessibility-matrix`, `visual-pass`,
`coach-real-model-verification`, `opening-book-quality`) are much less
likely to conflict with each other - check each one's `git diff --stat`
against `main` before merging, and batch together any that clearly don't
overlap in files touched.

After all nine are in, proceed to Phase 2 and Phase 3 exactly as
`handoffs/OVERNIGHT-INTEGRATION-MASTER.md` describes.
