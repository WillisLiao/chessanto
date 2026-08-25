# Overnight master session: integrate everything, finish the roadmap, polish the app

You are running unattended overnight with effectively unlimited budget.
Read the "Hard safety rules" section below FIRST and follow it for the
entire session, not just at the start - the two failures it exists to
prevent (a silent infinite retry loop, and runaway process accumulation)
are exactly what happened the last time this kind of run went out
unsupervised: zero commits landed all night while several copies of the
app accumulated and consumed 70+ GB of RAM. Do not repeat that.

## Hard safety rules (apply at every step, no exceptions)

1. **Stay on branch `main`, in `/Users/willis/Documents/chessanto`, the
   whole session.** Do not create your own working branch for yourself.
   Merges happen directly onto `main`; feature/QA work happens in the
   worktrees named below, on their existing branches - never invent a
   new branch name of your own.

2. **Process hygiene, every single time you launch the app or run a
   test target that launches it:**
   ```
   pkill -9 -f "Chessanto.app/Contents/MacOS" 2>/dev/null
   ```
   Run that BEFORE every launch and AFTER you're done inspecting it. Confirm
   with `ps aux | grep -i "Chessanto.app" | grep -v grep` that nothing is
   running before you start a new one. At most one instance of the app
   may be running at any moment, ever, for any reason (manual AX
   inspection, `xcodebuild test`, a background analyzer run - one at a
   time, full stop). If you are ever unsure whether a prior launch is
   still alive, check and kill it before doing anything else.

3. **Circuit breaker on retries.** If the same command fails with the
   same or a clearly-related error twice in a row, STOP retrying it a
   third time blindly. Instead: write down the exact error text, form an
   explicit hypothesis about the root cause, and either (a) try one
   different, reasoned fix for that specific hypothesis, or (b) if you
   don't have a concrete hypothesis, mark that branch/task as blocked in
   `handoffs/HANDOFF.md` with the exact error and move on to the next
   item in the plan. Never loop on the same failing command more than
   twice without a state change in your approach. This applies to
   builds, tests, app launches, and merge conflict resolution alike.

4. **Time-box stuck problems.** If you have spent what feels like a
   long stretch (roughly 30+ minutes of real attempts, not counting
   long-running background analysis) on a single build/test failure
   without resolving it, that is itself a signal to invoke rule 3(b):
   mark it blocked, move on. Coming back to a blocked item later in the
   session, with fresh eyes after other progress, is fine and
   encouraged - grinding on it uninterrupted for hours is not.

5. **Checkpoint after every branch, not at the end of the night.**
   Commit and `git push origin main` immediately after each successful
   merge and its verification, before starting the next branch. Never
   let more than one branch's worth of work sit unpushed. This means
   that if something goes wrong later in the session, everything landed
   so far is already safe on `origin/main`, not lost.

6. **One known environment quirk, not a real bug:** if a build fails
   with `unable to write file ... .git/modules/.../pack/*.pack: No such
   file or directory`, that's a stale/corrupted local SPM checkout cache
   in DerivedData from running many worktrees in parallel, not broken
   code. Fix: `rm -rf ~/Library/Developer/Xcode/DerivedData/Chessanto-*`
   for the affected one (find the exact hash in the error path) and
   rebuild. This does not count against the circuit breaker in rule 3 -
   it's a known fix, apply it once and continue normally.

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
`3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`; confirm
it still matches before and after anything that touches the app.

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.

## The verification bar (non-negotiable, every single time)

Nothing is ever "done" without you having actually run it yourself and
being able to quote the real output. A prior session's devlog claiming
success is a claim to verify, not a fact to trust.

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
directly, before the full app-level run. Note that `xcodebuild test`
launches the app itself as part of running - rule 2 above still applies:
if a prior launch (yours or a stray one) is still around, kill it first.

## Phase 1: land all branches with real work on main

These branches exist right now, each in its own worktree, each already
committed (nothing uncommitted was left in any of them):

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
| `qa/visual-pass` | `../chessanto-visual-qa` | Has a commit; re-verify from scratch. |
| `qa/coach-real-model-verification` | `../chessanto-coach-real-model` | Has a commit; re-verify from scratch. |
| `feature/opening-book-quality` | `../chessanto-opening-book-quality` | Has a commit; re-verify from scratch. |
| `perf/hardening-pass` | `../chessanto-perf-hardening` | Zero commits - only investigation notes exist, in `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md`. Nothing to merge yet; this branch is Phase 2 work, not a Phase 1 merge. |

For each of the thirteen branches with real commits (every row above
except `perf/hardening-pass`), in this order:

1. **Re-verify it standalone first**, inside its own worktree, before
   touching main: `cd` into the worktree, `xcodegen generate`, full build
   and test (obeying the safety rules above - kill any stray app
   instance first, apply the circuit breaker if something fails
   repeatedly). If it fails for a reason that traces back to real broken
   code (not the DerivedData cache issue in rule 6), fix it right there
   in that worktree, commit the fix on that branch, and only then
   proceed. If you cannot resolve it within the time-box in rule 4, mark
   that branch blocked in `handoffs/HANDOFF.md` with the specifics and
   move to the next branch in the table - come back to blocked branches
   at the end of Phase 1 rather than losing the rest of the night to one
   branch.
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
   main before moving to the next branch - subject to the same circuit
   breaker and time-box rules as anything else.
6. Commit the merge (or the merge plus your integration fix), then
   **push to `origin main` immediately** per rule 5 before starting the
   next branch.
7. Move to the next branch in the table.

After all resolvable branches are merged and the full suite is green on
`main`, delete the now-merged local branches and worktrees:
`git worktree remove <path>` then `git branch -d <branch>` for each. Keep
`perf/hardening-pass` and its worktree, and keep any branch you marked
blocked (with a note on why) rather than deleting it.

## Phase 2: finish what's left open

1. **Performance hardening.** Read
   `handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md` in full - it
   has real baseline measurements, a fixture database already built (3594
   real games), scratch tooling locations, and a suggested sequence. A
   background analyzer process may already be running or may have
   finished/died - check `ps aux | grep analyzer` and the row count
   before relaunching anything, per that file's own instructions.
   Work in `../chessanto-perf-hardening` on branch `perf/hardening-pass`.
   Follow its own verification bar and "When done" section, then merge it
   into `main` the same way as Phase 1 (re-verify standalone, merge,
   resolve conflicts, re-verify on main, push immediately after).

2. **Release packaging audit.** This one was queued but never assigned to
   an instance. Read `handoffs/NEXT-SESSION-RELEASE-PACKAGING-AUDIT.md`
   and do it yourself now, directly on `main` (create the worktree it
   specifies, `../chessanto-release-packaging` on branch
   `chore/release-packaging-audit`, do the work there, then merge back
   the same way, pushing immediately after).

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
  now that so much has changed. Commit and push this on its own.
- Go through every screen in the app (onboarding, library with its new
  search/filter, game replay and report, exploration mode, Play vs
  Engine, Chess960 game creation, Coach chat, Dashboard/Player Brief,
  Settings including dark mode) and use the AX automation scripts under
  `scripts/` to actually drive the running app and look for anything
  broken, inconsistent, or unpolished - especially at the seams between
  tonight's merged features. Obey the process-hygiene rule for every
  single launch. Fix what you find, commit and push in reasonably small
  batches rather than one giant end-of-night commit.
- Confirm every regression test added across all merged branches is
  still meaningful post-integration (not testing a code path that got
  changed or removed during conflict resolution).
- If, after all of the above, you genuinely run out of concrete work,
  it is fair game to pick up one or two of PLAN.md's remaining
  historically-out-of-scope items (repertoire training, a dedicated
  accessibility UI-test matrix beyond what was already done, richer
  library sorting beyond filtering) EXCEPT iCloud sync and Lichess
  import, which stay off the table. Use judgment on what's actually
  valuable versus scope for its own sake.

Keep looping Phase 3 (sweep, find real issues, fix, re-verify, commit,
push) for as long as you're running, always pushing after each
meaningful, verified chunk rather than batching. There is no fixed
stopping point other than genuinely running out of real work to do.

## Bookkeeping, every single commit

After any meaningful chunk of work, write or update the relevant
`devlogs/<date>-<slug>.md` with what changed and the real verification
output, keep `handoffs/HANDOFF.md`'s top section current (newest state
first, don't delete history), commit with a clear message (no em dashes,
no fabricated co-author), and push. Small, frequent, verified commits
that are always pushed beat one large batch at the end - the whole point
is that progress is visible and safe throughout the night, not just
claimed in the morning.
