# Session: Native visual QA and pixel-perfection pass

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md.

Search `handoffs/HANDOFF.md` for prior mentions of "visual-only rendering
verification" and "composited display" - several past sessions explicitly
deferred this work because no composited display was available to them.
This session exists to actually do it.

You have unlimited usage for this session. Do not ration effort or stop
early to save budget. Be picky about the UI you see: if something looks
off, even if unrelated to a specific bug you were chasing, fix it along
the way rather than filing it as a note for later.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b qa/visual-pass ../chessanto-visual-qa main
```

Do all your work inside `../chessanto-visual-qa`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Actually run the built app (not just tests) and drive it through its real
UI, using the existing AX automation scripts under `scripts/`
(`axclick.swift`, `axclickat.swift`, `axdrag.swift`, `axfocus.swift`,
`axprobe.swift`, `axsettext.swift`, `capture-window.swift`) the way prior
sessions built and used them - check those scripts first, they already
solve app activation and window-handle polling.

Cover, in both light mode and the newly-added dark mode:

- **Onboarding flow** end to end: username entry, rating band, model
  picker.
- **Game import**: file open, paste, drag-drop, and chess.com fetch -
  visually confirm each renders correctly, including error states
  (bad PGN, network failure, no games found).
- **Game replay and the report view**: move list, eval bar and graph,
  key-moment cards, accuracy summary, opening identification. Check that
  the recently-added detectors (skewer, discovered attack, back-rank
  weakness, trapped piece, absolute pin) render their sentences without
  layout breakage on realistically long text.
- **Exploration mode**: live scrubbing, drag-and-drop piece movement
  (confirm this is genuinely live, not just click-to-move), variation
  tree rendering and interaction, engine lines panel, and specifically
  the arrival-animation timing, coordinate/point sizing, and drawn
  annotation shapes that prior sessions flagged as needing a real display
  to verify.
- **Coach chat**: streaming response rendering, the six emotional
  portraits, speech controls, and the below-8B-model warning added
  recently in `CoachSetupView`.
- **Dashboard / Player Brief**: accuracy history charts, recurring motif
  cards, training card backfill.
- **Settings**: the new dark-mode toggle in `GeneralSettingsView` and
  every other settings section.
- **Window resizing**: confirm every screen above holds up at both a
  small and a large window size - this is a resizable board view per
  the product decisions, so layout must not break at the extremes.

For every real visual defect found (misalignment, clipped text, wrong
color in one theme, an animation that doesn't run or runs wrong, a
broken empty/error state, inconsistent spacing against the design system
in `App/Sources/Chessanto/DesignSystem/`): fix it directly. Use
`capture-window.swift` to get before/after screenshots as evidence in
your devlog.

## Non-goals

- Don't touch Play vs Engine, Chess960, search/filter, or the
  accessibility matrix (separate sessions own those) - if you spot a
  visual issue inside one of their in-progress screens, note it in your
  devlog for that session to pick up rather than editing their
  not-yet-merged work.
- This is visual QA, not a hunt for chess-logic correctness bugs (that's
  the QA-Carlsen/Hikaru/Caruana/edge-case sessions) - if you notice a
  logic bug along the way, note it in your devlog rather than chasing it
  down yourself.

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

The real bar for this session is the visual walkthrough itself: your
devlog must include actual screenshots (via `capture-window.swift`) for
every screen listed above, in both light and dark mode, plus before/after
pairs for anything you fixed. If a composited display genuinely isn't
available in your environment either, say so explicitly and do not
fabricate what you would have seen - report that limitation honestly
rather than describing screens you didn't actually render.

## When done

Write `devlogs/<date>-visual-qa.md` with the full walkthrough, embedded
or referenced screenshots, every defect found and fixed, and the exact
verification output.
Add a new `## Current state - Visual QA pass` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`qa/visual-pass`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
