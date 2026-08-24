# Session: Richer game library search and filtering

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: richer search/filtering is currently listed as explicitly out of
scope for v1 in PLAN.md's "Out of scope for v1" section. That decision
has been overridden for this session - build it - but do not otherwise
re-litigate anything else under "Product decisions (already made)".

You have unlimited usage for this session. Do not ration effort or stop
early to save budget - go as deep as the task actually needs, including
real end-to-end verification against a large imported game library, not
just unit tests of the filter logic.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/library-search-filter ../chessanto-library-search-filter main
```

Do all your work inside `../chessanto-library-search-filter`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

The game library today (`App/Sources/Chessanto/GameLibrary.swift` and
`App/Sources/Chessanto/Library/`) has no real search or filtering. Add it.

- **Search**: free-text search across opponent name and (if you can
  derive it cheaply) opening name, matching substrings case-insensitively.
  Use SwiftUI's native `.searchable` modifier rather than building a
  custom search bar - it's a native platform feature, use it.
- **Filters**: opponent, result (win/loss/draw), opening (ECO family),
  date range, time control, and accuracy range. Design the filter state
  as a single small value type the list view reduces against, not a pile
  of independent `@State` booleans - look at how existing view models in
  this codebase (e.g. `GameReplayViewModel`) structure derived state
  before inventing a new pattern.
  Combine filters with AND semantics; leave any given filter unset =
  no constraint from it.
  If some of these fields (opening, accuracy) aren't already stored
  per-game in a form cheap to filter on, check `Packages/Persistence`
  for what's already indexed/cached before adding new derived columns -
  reuse what's there before computing it fresh on every filter change.
- **UI placement**: this belongs in the library list view, filtering the
  existing list in place - it is not a separate screen. Keep it visually
  consistent with the rest of the app's design system
  (`App/Sources/Chessanto/DesignSystem/`); do not introduce new colors,
  fonts, or spacing values that aren't already part of that system.
- **Performance**: with a library of hundreds of games, filtering must
  feel instant (no visible lag on keystroke). Debounce free-text search
  input if a naive re-filter-on-every-keystroke is measurably slow, but
  don't add a debounce speculatively if it isn't - measure first.
- **Empty states**: a search/filter combination that matches nothing
  needs a real empty state, not a blank list.

## Non-goals

- Don't touch anything related to Play vs Engine or Chess960 (separate
  sessions own those).
- Don't add sorting options unless they're trivial to add alongside what
  you're already building - this session's job is search and filter, not
  a general library-view redesign.
- Don't touch the report/analysis pipeline.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/Persistence
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

Beyond unit tests of filter/search logic, actually run the built app
against a real, reasonably large imported game library (import several
players' full chess.com archives if the library is currently small) and
verify search and every filter dimension actually narrows the list
correctly, that combinations compose correctly, and that the empty state
appears when expected. If a composited display is available to you,
capture screenshots of the search/filter UI in both light and dark mode
and describe what you see - be picky about visual correctness, not just
functional correctness.

## When done

Write `devlogs/<date>-library-search-filter.md` describing what you built
and the exact verification output, including the real-app verification
above.
Add a new `## Current state - Library search and filter` section at the
TOP of `handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/library-search-filter`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
