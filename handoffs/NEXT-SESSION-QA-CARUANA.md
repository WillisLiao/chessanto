# Session: QA hardening - Caruana games

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b qa/caruana-games ../chessanto-qa-caruana main
```

Do all your work inside `../chessanto-qa-caruana`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Fetch every public archive for chess.com user `FabianoCaruana` via
`ChessComKit` and, for every single game, run it end-to-end through PGN
parse, full-game `ChessGame` replay of every ply, and report building
(`ReportBuilding.buildReport`) exactly as the app does on the real
end-user path (`GameReplayViewModel(record:store:)` ->
`buildReportInput`).

Log every throw, crash, or silently-wrong output: a FEN that doesn't match
the actual position, a move classification that's obviously wrong, a
report with zero key moments, or anything else that looks off.

For every real failure found:
1. Minimize it to the smallest reproducing PGN fragment. See
   `Packages/ChessCore/Tests/ChessCoreTests/RealGameFixtureTests.swift`
   for the pattern already used for the disambiguated-capture PGN bug.
2. Root-cause it. Trace every caller of the function you're about to
   touch before patching - fix it once in the shared layer
   (`ChessCore`/`ChessComKit`), never patch just the one path that
   happened to surface it.
3. Fix it and add a regression test.

## Non-goals

- Don't touch UI code.
- Don't touch other players' games (see the sibling QA sessions for
  Carlsen, Hikaru, and edge cases).
- Don't refactor unrelated code you happen to notice. Log it in your
  devlog instead so it can be triaged separately.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/ChessCore
swift test --package-path Packages/ChessComKit
swift test --package-path Packages/AnalysisKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

## When done

Write `devlogs/<date>-qa-caruana.md` describing what you found, what you
fixed, and the exact verification output.
Add a new `## Current state - QA Caruana games` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`qa/caruana-games`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
