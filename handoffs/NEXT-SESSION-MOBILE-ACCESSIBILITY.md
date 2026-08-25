# Session: iPhone companion accessibility pass

## Why this session is safe to run in parallel

An overnight `opencode` run is working through `handoffs/OVERNIGHT-INTEGRATION-MASTER.md`
right now, merging branches into `main` and polishing the Mac app. Its
scope is `App/`, `Packages/ChessCore`, `Packages/AnalysisKit`,
`Packages/CoachKit`, `Packages/Persistence`, `Packages/EngineKit`, and
`Packages/ChessComKit`. This session's scope is the iPhone companion
only: `Mobile/` and `Packages/CompanionKit/`. The Mac accessibility pass
(`handoffs/NEXT-SESSION-ACCESSIBILITY-MATRIX.md`, already merged)
explicitly excluded `Mobile/` as out of scope, so nothing has touched
iOS accessibility yet.

## Continue in the existing worktree - do not create a new one

This continues directly from the companion parity work already done.

```
cd /Users/willis/Documents/chessanto-mobile-parity
git status
git log --oneline -3
```

You should see branch `feature/mobile-companion-parity`, clean, with a
commit titled "iPhone companion feature parity, dark mode, and hardening
pass". Read `devlogs/2026-08-25-mobile-companion-parity.md` in that
worktree to see exactly what landed - the dynamic dark-mode color system
(`MobileColors`, `MobileDesignSystem.swift`), the new
`MobileClassificationStyle` chips and marks, and the enhanced key-moment
cards in `OfflineReportReader.swift` are the main surfaces this session
needs to audit, since they're new and unaudited for accessibility.

Sync with `main` first in case the overnight run has landed anything by
now (it shouldn't conflict - different files - but check):

```
git fetch origin
git merge origin/main
```

## Read first

Read `handoffs/HANDOFF.md` and `PLAN.md` in full if you haven't already
this session. Do not re-litigate anything under PLAN.md's "Product
decisions (already made)" section.

## Scope

A real audit-and-fix pass on the iPhone companion app
(`Mobile/Sources/ChessantoMobile`), not a report for someone else to fix
later:

- **VoiceOver**: every interactive element (tab bar, pairing
  entry/QR scan flow, report list, key-moment cards, the scoresheet move
  list with its new classification marks, coach section) needs a
  sensible accessibility label and value. The classification marks added
  in the parity pass (`★`, `!!`, `?!`, `?`, `??`) are a specific risk -
  a VoiceOver user needs to hear "brilliant move" or "blunder", not a
  bare glyph read character-by-character. Same for the evaluation pill
  indicators and move-number formatting.
- **Dynamic Type**: the new `MobileClassificationStyle` chips and the
  enhanced key-moment cards must scale with the user's text-size setting
  without truncating or breaking layout. Check at the largest
  accessibility text size, not just the default. Use SwiftUI's native
  text-scaling support rather than hand-rolled font-size math wherever
  the current code allows it.
- **Contrast**: verify the new dynamic dark-mode palette
  (`MobileColors`) actually meets WCAG AA contrast for text and
  interactive elements in both light and dark mode - it was matched to
  the Mac palette by value, but iOS renders it in a different context
  (smaller text, different default backgrounds), so don't assume the Mac
  palette's contrast passing means the mobile rendering does too.
- **Reduced motion**: check for any animation (report loading, card
  transitions, pairing flow) and respect the system's reduce-motion
  setting (`UIAccessibility.isReduceMotionEnabled` or the SwiftUI
  equivalent) if one exists and doesn't already.
- **Switch Control / Voice Control basics**: if there's any custom
  gesture-only interaction (e.g. a swipe-to-dismiss on a card) that has
  no equivalent tappable control, that's a real accessibility gap on
  iOS - add an accessible alternative.

For every real finding, fix it directly. Where you can't be certain from
source alone (e.g. how VoiceOver actually announces a compound element),
use the iOS Simulator's Accessibility Inspector if available in this
environment, or reason carefully from the Accessibility framework's
documented behavior and say explicitly in your devlog which you did.

## Non-goals

- Don't touch `App/`, `Packages/ChessCore`, `Packages/AnalysisKit`,
  `Packages/CoachKit`, `Packages/Persistence`, `Packages/EngineKit`, or
  `Packages/ChessComKit`.
- Don't re-do the parity/dark-mode/hardening work already committed -
  build on top of it.

## Verification bar

```
swift test --package-path Packages/CompanionKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' test
```

(If `iPhone 17` isn't available in this environment, run
`xcrun simctl list devices available` and use whatever real device name
is available - do not guess a name that doesn't exist and don't skip the
simulator run.)

Every build must end `** BUILD SUCCEEDED **` and every test run must end
`** TEST SUCCEEDED **`, with the real "Test run with N tests in M suites"
line quoted in your devlog. Pipe long xcodebuild output through `tail` or
`grep -E "error:|BUILD SUCCEEDED|TEST SUCCEEDED|Test run with"` rather
than reading it raw.

## Bookkeeping

Write `devlogs/<date>-mobile-accessibility.md` describing what you
audited, what you found, what you fixed, and the exact verification
output. Update the `## Current state - Mobile companion parity` section
already at the top of `handoffs/HANDOFF.md` in this worktree (extend it
or add a new dated section directly above it - don't delete the existing
one). Commit everything on the same branch
(`feature/mobile-companion-parity`). Do not merge to main yourself and do
not push - this still waits to be reviewed and merged alongside the
overnight run's work.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
