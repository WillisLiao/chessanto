# Session: Opening book coverage and quality pass

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md, including the explicit "keep it small, this is not a repertoire
trainer" scope for the opening book - this session improves the accuracy
and coverage of the existing feature, it does not turn it into a
repertoire trainer.

You have unlimited usage for this session. Do not ration effort or stop
early to save budget.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/opening-book-quality ../chessanto-opening-book-quality main
```

Do all your work inside `../chessanto-opening-book-quality`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Find `Packages/AnalysisKit/Sources/AnalysisKit/OpeningBook.swift` and its
bundled data first, and understand exactly what's there today (ECO code
coverage, how deep into the game it can identify, how it decides where a
player left known theory) before changing anything.

- **Coverage audit**: run the opening-identification logic against a
  large batch of real games (fetch several players' full chess.com
  archives, or reuse an existing large library if another session's
  worktree has already built one) and measure how often it successfully
  names an opening versus falls through to "no match." A high miss rate
  on genuinely common openings is a real bug in either the bundled data
  or the matching logic, not just a data-completeness gap to shrug off.
- **Deviation-point accuracy**: for games where an opening is identified,
  spot-check a real sample of the "left known theory at move N" claim
  against actual opening theory (cross-reference a couple of well-known
  lines by hand). If the deviation point is being computed wrong for a
  class of positions (e.g. transpositions, move-order-independent lines),
  root-cause and fix it.
- **Data quality**: if the bundled ECO dataset itself has gaps, wrong
  names, or wrong FENs for openings that come up often in the real games
  you tested against, fix the data - check `scripts/fetch-eco.sh` first
  to understand how the bundled data was generated, so a fix is
  reproducible rather than a one-off hand edit that the next regeneration
  silently overwrites.
- **Size discipline**: PLAN.md is explicit that this stays "a few MB, not
  a repertoire trainer." If closing a real coverage gap would require
  bundling a dramatically larger dataset, that's a real tradeoff to flag
  in your devlog rather than just doing it - use judgment on what a
  reasonable "few MB" ceiling means in practice.

## Non-goals

- No new opening-book UI or features (a repertoire browser, an opening
  explorer, book-move suggestions during play) - this is a correctness
  and coverage pass on the existing identification feature only.
- Don't touch Play vs Engine, Chess960, search/filter, accessibility,
  visual QA, or Coach verification (separate sessions own those) -
  Chess960 specifically must NOT get opening-book matches (that's that
  session's requirement, already in scope there); if you find the
  opening book firing on non-standard starting positions while doing
  this audit, note it for that session rather than fixing it yourself
  unless it's clearly a bug in the book's shared matching logic itself.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable,
and neither is a coverage claim without the actual measured numbers.

```
swift test --package-path Packages/AnalysisKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

Your devlog must include the real coverage measurement (match rate before
and after your changes, against a stated real sample size and source),
concrete examples of deviation-point or data-quality bugs found and
fixed, and the bundled data's size before and after.

## When done

Write `devlogs/<date>-opening-book-quality.md` with the coverage
measurements, every fix made, and the exact verification output.
Add a new `## Current state - Opening book quality` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/opening-book-quality`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
