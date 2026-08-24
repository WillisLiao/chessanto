# Session: QA hardening - edge-case and adversarial PGNs

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b qa/edge-case-pgns ../chessanto-qa-edge-cases main
```

Do all your work inside `../chessanto-qa-edge-cases`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Unlike the sibling QA sessions (one chess.com player's archive each), this
session is adversarial and data-shape focused. Collect and test PGNs that
stress the parser and pipeline in ways a single strong player's normal
games mostly won't:

- Games ending in abandonment or timeout (not checkmate/resignation).
- Very short games (under 10 moves) and very long games (over 150 moves).
- Games with missing, malformed, or partial `[%clk ...]` annotations.
- Games with unicode player names or unusual PGN header values.
- PGNs entered via the app's other three import paths, not just
  chess.com fetch: file open, paste, and drag-drop.
- PGNs exported from other tools if you can obtain legitimate public
  samples (lichess.org study exports, ChessBase exports) - these use
  slightly different but still-legal PGN conventions and are a good
  source of real-world format drift.

For every real failure found, run it through the exact end-user path
(`GameReplayViewModel(record:store:)` -> `buildReportInput`, or the
matching import entry point for file/paste/drag-drop), then:
1. Minimize it to the smallest reproducing PGN fragment. See
   `Packages/ChessCore/Tests/ChessCoreTests/RealGameFixtureTests.swift`
   for the pattern already used for the disambiguated-capture PGN bug.
2. Root-cause it. Trace every caller of the function you're about to
   touch before patching - fix it once in the shared parser/report layer,
   never patch just the one path that happened to surface it.
3. Fix it and add a regression test.

## Non-goals

- Don't touch UI beyond whatever the import entry points require in
  order to reproduce a bug.
- Don't spend time on a single player's normal-game archive (see the
  sibling Carlsen/Hikaru/Caruana QA sessions for that).
- Don't refactor unrelated code you happen to notice. Log it in your
  devlog instead so it can be triaged separately.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/ChessCore
swift test --package-path Packages/ChessComKit
swift test --package-path Packages/AnalysisKit
swift test --package-path Packages/Persistence
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

## When done

Write `devlogs/<date>-qa-edge-cases.md` describing what you found, what
you fixed, and the exact verification output.
Add a new `## Current state - QA edge cases` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`qa/edge-case-pgns`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
