# Session: QA hardening - Hikaru games (RESUME)

A prior instance was working on this and hit a usage limit mid-task. Its
worktree already exists with uncommitted changes. Do not start over and
do not discard that work without reading it first.

## Read first

Read `handoffs/NEXT-SESSION-QA-HIKARU.md` in full - it has the complete
scope, non-goals, and verification bar for this task. Everything in it
still applies. This file only covers how to resume correctly.

## Resuming (do this before anything else)

```
cd /Users/willis/Documents/chessanto-qa-hikaru
git status
git diff
git diff --stat
```

Read every changed and new file shown there. The prior instance left:
- A modification to `Packages/AnalysisKit/Package.swift`.
- A new `Packages/AnalysisKit/Sources/hikaru-qa/` directory (looks like a
  scan runner executable target, similar in shape to the Carlsen QA
  session - worth comparing against
  `../chessanto-qa-carlsen/Packages/AnalysisKit/Sources/carlsen-qa/` if
  that worktree still exists, to reuse the same pattern rather than
  diverging for no reason).

Evaluate this work on its merits: is it heading toward the actual goal
(scan the real Hikaru archive end-to-end, find and fix real bugs), or is
it scaffolding that never got to the point of finding anything? If sound,
continue it. If wrong or over-built, fix or simplify rather than
preserving it out of inertia.

Once you understand what's there, commit it as a checkpoint before
changing anything further:

```
git add -A
git commit -m "Checkpoint: carry forward Hikaru QA scan work in progress"
```

Then continue the task through to actual completion per
`handoffs/NEXT-SESSION-QA-HIKARU.md`: run the full scan against every
real game in the archive, find and root-cause-fix any real failures, and
meet the file's full verification bar (the exact `swift test` and
`xcodebuild` commands, with real quoted output, not a summary).

## When done

Follow the "When done" section of `handoffs/NEXT-SESSION-QA-HIKARU.md`
exactly (devlog, `HANDOFF.md` section, commit on `qa/hikaru-games`, no
merge, no push).
