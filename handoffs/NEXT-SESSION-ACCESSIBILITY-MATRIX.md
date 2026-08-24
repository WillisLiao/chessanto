# Session: Accessibility UI-test matrix

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: a dedicated accessibility UI-test matrix is currently listed as
explicitly out of scope for v1 in PLAN.md's "Out of scope for v1" section.
That decision has been overridden for this session - build it - but do
not otherwise re-litigate anything else under "Product decisions (already
made)".

You have unlimited usage for this session. Do not ration effort or stop
early to save budget. Accessibility basics are never something to
simplify away (input validation, error handling, security, and
accessibility are the four categories this project explicitly protects
from being cut for expediency) - treat every real finding as worth fixing,
not just cataloguing.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/accessibility-matrix ../chessanto-accessibility-matrix main
```

Do all your work inside `../chessanto-accessibility-matrix`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

This is a real audit-and-fix pass across the whole macOS app (the iPhone
companion under `Mobile/` is out of scope for this session), not a report
that lists problems for someone else to fix later. Cover:

- **VoiceOver**: every interactive control (buttons, the board itself,
  the move list, the engine lines panel, chat input, settings toggles,
  dashboard cards) needs a sensible accessibility label and, where the
  visible text alone doesn't convey state, a value/hint too. The chess
  board specifically is the hard case: a sighted user reads piece
  positions visually, so VoiceOver needs a real strategy for exposing
  "what's on this square" and "what changed on the last move," not just
  a generic label on the whole board view. Look at how the board view is
  structured today (`App/Sources/Chessanto/` - find the board rendering
  code) before designing this.
- **Keyboard navigation**: every screen must be fully operable without a
  mouse or trackpad - tab order, focus indication, and keyboard
  equivalents for drag-and-drop interactions (the board already supports
  click-to-move per existing AX automation scripts in `scripts/axclick.swift`
  and `scripts/axdrag.swift` - verify keyboard-only piece movement works
  too, or add it if it's currently mouse-only).
- **Dynamic Type**: text must scale with the user's system text-size
  setting without truncating, overlapping, or breaking layout. Check
  every screen at at least the largest accessibility text size, not just
  the default.
- **Contrast**: verify text and interactive elements meet WCAG AA
  contrast ratios in both light and dark mode (dark mode was added
  recently - `App/Sources/Chessanto/DesignSystem/DesignColors.swift` -
  make sure its contrast is actually checked, not just visually
  plausible).
- **Reduced motion**: respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  (or the SwiftUI equivalent) for any animation you find, particularly
  the coordinate/annotation/arrival animations mentioned in prior
  handoff notes as still needing visual verification.

For every real finding: fix it directly in the relevant view. Where a fix
isn't self-evidently correct without a live VoiceOver session (e.g. board
square semantics), use the existing AX automation scripts under
`scripts/` (`axprobe.swift` in particular) to actually inspect the live
accessibility tree of the running app and confirm your fix produces
sensible output, rather than guessing from source alone.

## Non-goals

- Don't touch the iPhone companion (`Mobile/`) - Mac app only for this
  session.
- Don't touch Play vs Engine, Chess960, or the search/filter work
  (separate sessions own those) beyond making sure any UI you touch for
  accessibility reasons doesn't collide - if any of those branches have
  already changed a view you need to touch, note the conflict in your
  devlog rather than trying to merge their work yourself.

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

Beyond the build/test gate, this session's real bar is the audit itself:
produce a matrix (screen x accessibility dimension) in your devlog
showing what you checked, what you found, and what you fixed, with actual
`axprobe.swift` output or VoiceOver transcript excerpts as evidence for
the board-semantics work specifically - not just "should be fine."

## When done

Write `devlogs/<date>-accessibility-matrix.md` containing the full matrix
described above and the exact verification output.
Add a new `## Current state - Accessibility matrix` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/accessibility-matrix`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
