# Overnight master session: integrate everything, finish the roadmap, polish the app

You are running unattended overnight with effectively unlimited budget.
Do not stop early, do not summarize-and-quit, and do not ask for
permission mid-task - keep working through the entire plan below until
there is genuinely nothing productive left to do. If you hit something
you cannot resolve (needs credentials you don't have, needs physical
hardware, needs a human product decision that isn't already covered by
this file), write it clearly into `handoffs/HANDOFF.md` as an open item
and move on to the next thing rather than stalling.

Work directly in `/Users/willis/Documents/chessanto` on branch `main`.
This is different from every prior session tonight - you are the
integrator, not one more isolated worktree. Fourteen other agent sessions
ran in parallel worktrees earlier and were paused; their branches are
sitting on disk right now with real, mostly-verified work. Your first job
is to land all of it on `main`, one branch at a time, verifying for real
at every step. Your second job is to keep finding and finishing real work
until the product is actually done.

## Ground truth before you start

Read `handoffs/HANDOFF.md` and `PLAN.md` in full. Do not re-litigate
anything under PLAN.md's "Product decisions (already made)" section.
Two explicitly out-of-scope items from that file have been confirmed
still out of scope for this batch of work and must NOT be built: iCloud
sync and Lichess import. Everything else in that "Out of scope for v1"
list has already been greenlit and is either in progress below or fair
game if you finish everything else and still have time (see Phase 3).

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, never hand-edit it. Run `xcodegen generate` after adding
or removing any Swift file, before every build/test.

Never touch the live database at
`~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
If any session's work involves launching the real app, verify that file's
SHA-256 is unchanged afterward - prior sessions recorded it as
`3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f` (15
games); confirm it still matches before and after anything that touches
the app.

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.

## The verification bar (non-negotiable, every single time)

Nothing is ever "done" without you having actually run this yourself and
being able to quote the real output. A prior session's devlog claiming
success is a claim to verify, not a fact to trust - you have already seen
tonight that claims can be wrong (a stale DerivedData/SPM cache once made
a genuinely-fine branch look broken; treat that as recoverable, not as
evidence of a real bug, and just clear
`~/Library/Developer/Xcode/DerivedData/Chessanto-*` and retry if you see
`unable to write file ... .git/modules/.../pack/*.pack`).

After every merge and every fix, at minimum:

```
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

Build must end `** BUILD SUCCEEDED **`. Test must end
`** TEST SUCCEEDED **`, and you should be able to quote the current
"Test run with N tests in M suites" line at any point - it should only
ever go up as you integrate more branches. Also run
`swift test --package-path Packages/<X>` for any package you touch
directly, before the full app-level run.

## Phase 1: land all fourteen branches on main

These branches exist right now, each in its own worktree, each already
committed (nothing uncommitted was left behind):

| Branch | Worktree | Status going in |
|---|---|---|
| `qa/edge-case-pgns` | `../chessanto-qa-edge-cases` | Verified complete and green already. |
| `qa/carlsen-games` | `../chessanto-qa-carlsen` | Verified complete and green already. |
| `feature/chess960-core` | `../chessanto-chess960-core` | Verified complete and green already (76 ChessCore, 196 AnalysisKit/6 suites, 200 app/36 suites at last check). |
| `feature/play-vs-engine-core` | `../chessanto-play-vs-engine-core` | Verified complete and green already. |
| `qa/hikaru-games` | `../chessanto-qa-hikaru` | Has commits; re-verify from scratch. |
| `qa/caruana-games` | `../chessanto-qa-caruana` | Has commits; re-verify from scratch. |
| `feature/chess960-app-integration` | `../chessanto-chess960-app-integration` | Has commits; depends on chess960-core; re-verify from scratch. |
| `feature/play-vs-engine-ui` | `../chessanto-play-vs-engine-ui` | Has commits; depends on play-vs-engine-core; re-verify from scratch. |
| `feature/library-search-filter` | `../chessanto-library-search-filter` | Has a commit; build succeeded at last check, full test suite not yet confirmed; re-verify. |
| `feature/accessibility-matrix` | `../chessanto-accessibility-matrix` | Has a commit; build succeeded at last check, full test suite not yet confirmed; re-verify. |
| `qa/visual-pass` | `../chessanto-visual-qa` | Has a commit now (an earlier attempt on this branch stalled with nothing committed; a later attempt landed real work) - re-verify from scratch, do not assume the earlier stall means anything about this commit. |
| `qa/coach-real-model-verification` | `../chessanto-coach-real-model` | Has a commit; re-verify from scratch. |
| `feature/opening-book-quality` | `../chessanto-opening-book-quality` | Has a commit; re-verify from scratch. |
| `perf/hardening-pass` | `../chessanto-perf-hardening` | Zero commits - only investigation notes exist, in `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md`. Nothing to merge yet; this branch is Phase 2 work, not a Phase 1 merge. |

For each of the thirteen branches with real commits (every row above
except `perf/hardening-pass`), in this order:

1. **Re-verify it standalone first**, inside its own worktree, before
   touching main: `cd` into the worktree, `xcodegen generate`, full build
   and test. If it fails for a reason that traces back to real broken
   code (not the DerivedData cache issue above), fix it right there in
   that worktree, commit the fix on that branch, and only then proceed.
2. Read that branch's devlog(s) under `devlogs/` (they'll have today's
   date) and its `## Current state - ...` section it added to the top of
   `handoffs/HANDOFF.md` - these exist per-branch until merged, so you
   need to read them on the branch, not on main.
3. From the `main` worktree (`/Users/willis/Documents/chessanto`), merge:
   `git merge --no-ff <branch> -m "Merge <description>"`.
4. **Resolve conflicts by understanding both sides, never by blindly
   taking one.** The most likely conflict source: several QA branches
   (Carlsen, Hikaru, Caruana) each added their own throwaway scan-runner
   executable target to `Packages/AnalysisKit/Package.swift`
   (`carlsen-qa`, `hikaru-qa`, `qa-caruana-runner`). Per the perf-hardening
   session's own convention ("these tools are throwaway; do not commit
   them"), these one-off scanning executables are not product code -
   when you hit this conflict, keep the real fixes and regression tests
   from each branch, but drop the throwaway scan-runner executable
   targets from `Package.swift` and delete their source directories,
   noting in your merge commit message that you did this and why. If a
   branch's regression tests actually depend on that runner code (rather
   than on ChessCore/AnalysisKit/App test targets), keep only what the
   tests need and cut the rest.
   `handoffs/HANDOFF.md` will also conflict on nearly every merge, since
   every branch added its own section at the top - resolve by keeping
   both sections (newest branch's section goes above, in the position it
   was added), never by discarding one side's history.
5. After resolving, run the full verification bar from main. If a defect
   only appears once two branches are combined (an integration bug
   neither branch could see alone), root-cause and fix it directly on
   main before moving to the next branch - do not proceed with a known
   integration bug outstanding.
6. Commit the merge (or the merge plus your integration fix).
7. Move to the next branch in the table.

After all thirteen are merged and the full suite is green on `main`,
delete the now-merged local branches and worktrees:
`git worktree remove <path>` then `git branch -d <branch>` for each. Keep
`perf/hardening-pass` and its worktree - that one still has real work
ahead of it in Phase 2.

Push `main` after Phase 1 completes:
`git push origin main`.

## Phase 2: finish what's left open

1. **Performance hardening.** Read
   `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md` in full - it
   has real baseline measurements, a fixture database already built (3594
   real games), scratch tooling locations, and a suggested sequence.
   Work in `../chessanto-perf-hardening` on branch `perf/hardening-pass`.
   Follow its own verification bar and "When done" section, then merge it
   into `main` the same way as Phase 1 (re-verify standalone, merge,
   resolve conflicts, re-verify on main, push).

2. **Release packaging audit.** This one was queued but never assigned to
   an instance. Read `handoffs/NEXT-SESSION-RELEASE-PACKAGING-AUDIT.md`
   and do it yourself now, directly on `main` (create the worktree it
   specifies, `../chessanto-release-packaging` on branch
   `chore/release-packaging-audit`, do the work there, then merge back
   the same way).

## Phase 3: full roadmap sweep - keep going until actually done

Once Phase 1 and 2 are merged and green, re-read `PLAN.md` and
`handoffs/HANDOFF.md` top to bottom with fresh eyes, now that the app
has grown a lot since those documents were last fully accurate. Your job
here is to make the roadmap statement "feature-complete and fully
polished" become actually true, not just asserted.

Concretely, at minimum:

- Update `PLAN.md` and `README.md` to reflect everything merged tonight
  (Play vs Engine, Chess960, search/filter, accessibility work,
  performance work, release audit, all the QA fixes) - the same kind of
  documentation-truth pass a prior session already did once; do it again
  now that so much has changed.
- Go through every screen in the app (onboarding, library with its new
  search/filter, game replay and report, exploration mode, Play vs
  Engine, Chess960 game creation, Coach chat, Dashboard/Player Brief,
  Settings including dark mode) and use the AX automation scripts under
  `scripts/` to actually drive the running app and look for anything
  broken, inconsistent, or unpolished - especially at the seams between
  tonight's merged features (does the accessibility work still hold up
  on the new search/filter UI and the new Play vs Engine screens? does
  dark mode look right on the Chess960 board setup view? does the
  library list stay fast with search/filter active during a live Play vs
  Engine game?). Fix what you find.
- Confirm every regression test added across all thirteen merged
  branches is still meaningful post-integration (not testing a code path
  that got changed or removed during conflict resolution).
- If, after all of the above, you genuinely run out of concrete work,
  it is fair game to pick up one or two of PLAN.md's remaining
  historically-out-of-scope items (repertoire training, a dedicated
  accessibility UI-test matrix beyond what was already done, richer
  library sorting beyond filtering) EXCEPT iCloud sync and Lichess
  import, which stay off the table. Use judgment on what's actually
  valuable versus scope for its own sake - the ladder is: does this need
  to exist, is something close already built tonight that covers it,
  before reaching for something new.

Keep looping Phase 3 (sweep, find real issues, fix, re-verify, commit,
push) for as long as you're running. There is no fixed stopping point
other than genuinely running out of real work to do.

## Bookkeeping, every single commit

Same discipline as every branch tonight followed: after any meaningful
chunk of work, write or update the relevant `devlogs/<date>-<slug>.md`
with what changed and the real verification output, keep
`handoffs/HANDOFF.md`'s top section current (newest state first, don't
delete history), and commit with a clear message (no em dashes, no
fabricated co-author). Push to `origin main` periodically as you land
verified, working states - don't hoard a night's worth of work
unpushed.
