# Session: iPhone companion feature-parity and hardening pass

## Why this session is safe to run in parallel

An overnight `opencode` run is working through `handoffs/OVERNIGHT-INTEGRATION-MASTER.md`
right now, merging thirteen branches into `main` and then doing a
polish sweep. Its scope is `App/`, `Packages/ChessCore`,
`Packages/AnalysisKit`, `Packages/CoachKit`, `Packages/Persistence`,
`Packages/EngineKit`, and `Packages/ChessComKit`. This session's scope is
the iPhone companion instead: `Mobile/` and `Packages/CompanionKit/`.
Nobody has touched those tonight and nothing in the other run's plan
touches them either, so this can run fully in parallel without
collision. Because the other run periodically merges into `main`, you
should periodically pull those changes into your own branch (see
"Staying in sync" below) rather than working from a stale base all
night.

## Read first

Read `handoffs/HANDOFF.md` and `PLAN.md` in full before doing anything
else. Search `handoffs/HANDOFF.md` for "iPhone-first companion complete"
and "Kokoro TTS" to see what the companion already has - it was built and
hardened on 2026-07-19, before nearly everything that's landed since
(dark mode, the four new tactical detectors, absolute pins, fork
detection, move-quality flags, [%clk] time-pressure takeaways, the Coach
model floor, and whatever tonight's overnight run adds on top: Play vs
Engine, Chess960, library search/filter, accessibility work,
performance fixes). Do not re-litigate anything under PLAN.md's "Product
decisions (already made)" section.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/mobile-companion-parity ../chessanto-mobile-parity main
```

Do all your work inside `../chessanto-mobile-parity`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited. Any time you add or remove a Swift file
under `Mobile/` or `Packages/CompanionKit/`, run `xcodegen generate` in
your worktree before building.

## Staying in sync with the overnight run

Every couple of hours (or whenever you're about to start a new chunk of
work), fetch and merge whatever the overnight run has landed on `main`
so far:

```
git fetch origin
git merge origin/main
```

Resolve any conflict the normal way (`Mobile/` and `CompanionKit/` should
almost never conflict with the other run's scope, so a conflict here is
worth reading carefully rather than blindly resolving - it may mean
scope actually overlapped somewhere, most likely in a shared type both
`CompanionKit` and `AnalysisKit`/`CoachKit` reference). Re-run your full
verification bar after every sync merge, not just at the end.

## Scope

Audit and close the gap between what the Mac app can now do and what the
companion (iPhone app plus the `CompanionKit` shared package plus
whatever surfaces on the Mac side specifically to talk to the phone) can
show or do. Concretely:

- **New Facts and detectors**: `CoachFactsPayload`/`KeyMoment` grew a lot
  since July - absolute pins, skewers, discovered attacks, back-rank
  weakness, trapped pieces, forks, ignored threats, move-quality flags.
  Confirm every one of these actually renders something sensible on the
  phone (`CompanionDomain` and the mobile UI), not just on Mac. If the
  companion's rendering layer assumes an older, smaller `KeyMoment`
  shape and silently drops newer fact types, that's a real bug to fix,
  not a gap to document.
- **Dark mode**: the Mac app gained a dark-mode toggle recently
  (`DesignColors.dynamic(light:dark:)`). Check whether the companion has
  its own equivalent design-system colors and whether they need the same
  treatment, or whether iOS's own automatic appearance handling already
  covers it - don't build a toggle if the platform default already does
  the right thing.
- **Coach model floor**: the Mac Coach now refuses to enable itself below
  an 8B model and shows a warning. Confirm the companion's Coach-related
  UI (if it surfaces model status at all) reflects the same floor rather
  than showing stale or absent information.
- **[%clk] time-pressure takeaways**: confirm these render on the
  companion's report view the same way they do on Mac, if the companion
  shows takeaways at all.
- **`ClassificationContext.forGame`**: `handoffs/HANDOFF.md` already
  documents this as the single source of truth so "the phone companion
  cannot label a move Best that the Mac calls Book" - spot-check that
  this guarantee still holds after everything that's changed since it
  was written, across a handful of real games.
- **Pairing and sync robustness**: re-read the `CompanionSecurity` and
  `CompanionCloudKit` code and its existing tests. If you find a real
  correctness or security issue (not just a style nit), fix it. Physical
  CloudKit pairing testing across two real devices isn't possible in
  this environment - if you hit that wall, say so explicitly in your
  devlog rather than claiming untested behavior works.
- **Visual/UX pass on the phone UI itself**: use the iOS Simulator if
  available in this environment to actually run the companion and look
  for anything broken or unpolished, the same standard of pickiness
  applied to the Mac app elsewhere in this project. If no simulator is
  available, say so explicitly and do what you can from source-level
  review plus the existing test suite instead of fabricating a visual
  verification you didn't actually do.

## Non-goals

- Don't touch `App/`, `Packages/ChessCore`, `Packages/AnalysisKit`,
  `Packages/CoachKit`, `Packages/Persistence`, `Packages/EngineKit`, or
  `Packages/ChessComKit` unless a real bug you find genuinely traces back
  into one of those (e.g. a Fact type itself is wrong, not just how the
  companion renders it) - in that rare case, fix it at the root, but keep
  the change as narrow as the actual defect.
- Don't build any feature the Mac app doesn't already have (no new
  companion-only functionality) - this session is about parity and
  hardening, not expanding scope.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/CompanionKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'generic/platform=iOS Simulator' test
```

(Check the exact scheme name in `project.yml` if `ChessantoMobile` isn't
right - it's whatever the Mobile target is registered as.)

Every build must end `** BUILD SUCCEEDED **` and every test run must end
`** TEST SUCCEEDED **`, with the real "Test run with N tests in M suites"
line quoted in your devlog. When piping xcodebuild output, use `tail` or
`grep -E "error:|BUILD SUCCEEDED|TEST SUCCEEDED|Test run with"` rather
than reading the full raw output - it's routinely thousands of lines.

## Bookkeeping

Write `devlogs/<date>-mobile-companion-parity.md` describing the parity
gaps you found, what you fixed, and the exact verification output for
both the macOS and iOS targets. Add a new
`## Current state - Mobile companion parity` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there). Commit
everything on your branch (`feature/mobile-companion-parity`). Do not
merge to main yourself and do not push - bring the branch name back when
you're done so it can be reviewed and merged alongside (or after) the
overnight run's own work.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
