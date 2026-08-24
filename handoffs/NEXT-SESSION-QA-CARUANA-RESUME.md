# Session: QA hardening - Caruana games (RESUME)

A prior instance was working on this and hit a usage limit mid-task. Its
worktree already exists with uncommitted changes. Do not start over and
do not discard that work without reading it first.

## Read first

Read `handoffs/NEXT-SESSION-QA-CARUANA.md` in full - it has the complete
scope, non-goals, and verification bar for this task. Everything in it
still applies. This file only covers how to resume correctly.

## Resuming (do this before anything else)

```
cd /Users/willis/Documents/chessanto-qa-caruana
git status
git diff
git diff --stat
```

Read every changed and new file shown there. The prior instance left:
- Modifications to `App/Sources/Chessanto/ChessComFetchView.swift`,
  `Packages/AnalysisKit/Package.swift`,
  `Packages/ChessComKit/Sources/ChessComKit/ChessComClient.swift`, and
  `Packages/ChessComKit/Tests/ChessComKitTests/ChessComKitTests.swift`.
- A modification to `Packages/ChessComKit/Sources/chesscom-smoke/main.swift`.
- A new `Packages/AnalysisKit/Sources/qa-caruana-runner/` directory (looks
  like a scan runner executable target).

The `ChessComFetchView.swift` change is notable - that's app UI, and this
session's scope was meant to be scan-and-fix, not UI. Check carefully
whether that edit is actually necessary for the scan (e.g. a real bug it
uncovered in the fetch flow) or scope creep that should be reverted or
narrowed.

Evaluate this work on its merits: is it heading toward the actual goal
(scan the real Caruana archive end-to-end, find and fix real bugs), or is
it scaffolding that never got to the point of finding anything? If sound,
continue it. If wrong, over-built, or out of scope, fix, simplify, or
revert rather than preserving it out of inertia.

Once you understand what's there, commit it as a checkpoint before
changing anything further:

```
git add -A
git commit -m "Checkpoint: carry forward Caruana QA scan work in progress"
```

Then continue the task through to actual completion per
`handoffs/NEXT-SESSION-QA-CARUANA.md`: run the full scan against every
real game in the archive, find and root-cause-fix any real failures, and
meet the file's full verification bar (the exact `swift test` and
`xcodebuild` commands, with real quoted output, not a summary).

## When done

Follow the "When done" section of `handoffs/NEXT-SESSION-QA-CARUANA.md`
exactly (devlog, `HANDOFF.md` section, commit on `qa/caruana-games`, no
merge, no push).
