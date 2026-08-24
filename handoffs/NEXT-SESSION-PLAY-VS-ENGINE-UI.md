# Session: Play vs Engine - UI

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: "playing against the engine" is currently listed as explicitly out
of scope for v1 in PLAN.md's "Out of scope for v1" section. That decision
has been overridden for this batch of work - build it - but do not
otherwise re-litigate anything else under "Product decisions (already
made)".

## Dependency

This session builds the screen and board interaction on top of the
session type from `handoffs/NEXT-SESSION-PLAY-VS-ENGINE-CORE.md`
(branch `feature/play-vs-engine-core`).

Check whether that branch exists and has been pushed/committed yet:

```
git branch -a | grep play-vs-engine-core
```

If it exists, read its worktree or branch directly to build against the
real session API. If it doesn't exist yet, build against a minimal stub
interface that matches the shape described in this file's "Scope"
section, and write the exact shape you needed in your devlog so the two
can be reconciled at merge time.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/play-vs-engine-ui ../chessanto-play-vs-engine-ui main
```

Do all your work inside `../chessanto-play-vs-engine-ui`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Build the SwiftUI screen/flow for playing against the engine.

- New-game setup: pick a side and an engine strength.
- The live board during play: reuse the app's existing board view
  component - do not fork or duplicate it. Find it under
  `App/Sources/Chessanto/` (it's the same board used for game replay and
  exploration mode) and drive it from the live session's state instead of
  a static position list.
- Player controls appropriate to a live game: resign, offer/accept draw,
  and a clock if the core session exposes timing (if it doesn't, a clock
  is optional for this session - don't build a full clock system that has
  nowhere to plug in on the core side).
- On game end, transition into the existing report view exactly the way
  it opens for any other completed game - same view, same navigation
  pattern, no bespoke "post-engine-game" screen.

## Non-goals

- No engine-session logic, strength mapping, or persistence here - that
  belongs to the core session (see Dependency above). If something feels
  missing from the session API, say so in your devlog rather than
  reimplementing it in the view layer.
- Don't touch Chess960 (separate sibling sessions own that).

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.
Since a composited display may not be available in this environment,
visual-only verification (layout, animation timing) can be marked as
"needs a composited display" in your devlog rather than blocking - but
every piece of view logic you can unit-test (state transitions, what's
shown when) should be tested.

## When done

Write `devlogs/<date>-play-vs-engine-ui.md` describing what you built,
what you assumed about the core session API (and whether it matched),
and the exact verification output.
Add a new `## Current state - Play vs Engine UI` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/play-vs-engine-ui`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
