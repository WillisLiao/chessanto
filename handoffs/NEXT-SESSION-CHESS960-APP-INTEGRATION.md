# Session: Chess960 - app integration

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: Chess960 is currently listed as explicitly out of scope for v1 in
PLAN.md's "Out of scope for v1" section. That decision has been
overridden for this batch of work - build it - but do not otherwise
re-litigate anything else under "Product decisions (already made)".

Chess960 (Fischer Random Chess): the back-rank pieces start in one of 960
randomized-but-mirrored arrangements instead of the standard setup, with
castling rules adapted to the non-standard starting squares. See
`handoffs/NEXT-SESSION-CHESS960-CORE.md` for the full rules explanation.

## Dependency

This session wires Chess960 into the actual app on top of the rules/import
layer from `handoffs/NEXT-SESSION-CHESS960-CORE.md`
(branch `feature/chess960-core`).

Check whether that branch exists and has been pushed/committed yet:

```
git branch -a | grep chess960-core
```

If it exists, read its worktree or branch directly to build against the
real API. If it doesn't exist yet, note in your devlog exactly what you
needed and proceed against the FEN/PGN-header shape described in the core
session's file, so the two can be reconciled at merge time.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/chess960-app-integration ../chessanto-chess960-app-integration main
```

Do all your work inside `../chessanto-chess960-app-integration`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

- A way to start or import a Chess960 game: at minimum, importing a
  960-tagged PGN (file/paste/drag-drop) must work end-to-end through the
  same import UI as a standard game. If the play-vs-engine work
  (`handoffs/NEXT-SESSION-PLAY-VS-ENGINE-CORE.md`) has landed by the time
  you do this, a "random 960 position" starting option for a new live
  game is a reasonable pairing, but don't block on it - import support
  alone is the real requirement.
- Board setup display: when a 960 game is opened, the initial position
  the user sees must actually reflect its randomized starting
  arrangement, not silently render the standard setup.
- Confirm the report/analysis pipeline (`ReportBuilder`, `ThemeDetector`,
  key-moment selection) produces sane output for games starting from a
  non-standard position. If something in that pipeline assumes the
  standard start and breaks, that's a real bug to fix, not just a note -
  trace it to its root cause the same way the PGN parser bug was found
  and fixed (reproduce via the real end-user path first).
- Confirm the opening-book UI shows nothing (not a wrong opening name)
  for 960 games, and that this degrades gracefully rather than crashing
  or showing a misleading label.

## Non-goals

- No FEN generation, castling-legality, or PGN-header parsing logic here
  - that belongs to the core session. If something feels missing from
  the core API, say so in your devlog rather than reimplementing it in
  the app layer.
- Don't touch Play vs Engine's own session/UI logic (separate sibling
  sessions own that) beyond the optional "random 960 position" pairing
  described above.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/AnalysisKit
swift test --package-path Packages/Persistence
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.
Include at least one end-to-end test that imports a real public 960 PGN
(from Lichess or chess.com export) and asserts a correct report is
produced with no opening-book misfire.

## When done

Write `devlogs/<date>-chess960-app-integration.md` describing what you
built, what you found in the report pipeline, and the exact verification
output.
Add a new `## Current state - Chess960 app integration` section at the
TOP of `handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/chess960-app-integration`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
