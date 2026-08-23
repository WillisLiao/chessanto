# Next session - Priority 5 small UI details

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with `handoffs/NEXT-SESSION-THREAT-DETECTOR.md` and `handoffs/NEXT-SESSION-BOARD-QA.md` (separate sessions, separate git worktrees/branches - do not read or wait on either, your work is independent).

You are working in a dedicated git worktree on branch `ui-polish-p5`, checked out from `main` at commit `b5a00b4`. This is a real, separate checkout - commit and push this branch when you are done, do not attempt to merge to `main` yourself, and do not touch the primary checkout at `/Users/willis/Documents/chessanto` (a different session may be using it).

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state - especially the 2026-08-21 and 2026-08-22 entries, since some of this session's items touch code those sessions just changed (`ReportText`, `RatingRegister`) and you need to know the current shape before editing it.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "Priority 5 - smaller UI details" section in full - this is the source of every item below, written by an earlier product-review session. Re-verify each item against the current build before acting; that document says its own grounding screenshots predate later work, and two full sessions of UI change have landed since.
3. `App/Sources/Chessanto/GameReportView.swift`, `App/Sources/Chessanto/Analysis/MoveClassificationStyle.swift`, `App/Sources/Chessanto/Analysis/LinesPanelView.swift`, `App/Sources/Chessanto/Analysis/EvalGraphView.swift`, `App/Sources/Chessanto/Analysis/EvalBarView.swift`, `App/Sources/Chessanto/ContentView.swift`, `App/Sources/Chessanto/PlayerBriefView.swift` - read each in full before editing it, not just the excerpt below.
4. This repository's `ui-ux-pro-max` and `frontend-design` conventions apply to every item here - both together, per the project's standing rule, for any UI/UX change, however small each individual item looks.

## Scope: a batch of independent small UI fixes

Each item below is small enough to fix and verify on its own. Do them one at a time, in the order listed (roughly increasing effort), with a working build and passing tests after each one - do not batch several into one giant uncheckable diff. Re-verify each item's premise against the current running app before fixing it; some may already be partially or fully fixed by prior sessions' work, in which case say so and move on rather than making a speculative change.

1. **Classification chips wrap mid-word.** `GameReportView.classificationRow`'s `LazyVGrid` with `.adaptive(minimum: 58)` is undersized for "Inaccuracy" at `.dsSecondary` semibold in `ClassificationChip` (`MoveClassificationStyle.swift`), which sets no `lineLimit` or `fixedSize`. Verify live first (build and run, or at minimum lay out the text at the actual font/weight and measure) - do not just trust the backlog doc's number. Fix the minimum width and/or add `lineLimit(1)` with `fixedSize(horizontal: true, vertical: false)`, whichever is the smaller, more correct fix.

2. **No legend for the six classification marks.** Star, thumbs-up, checkmark, `?!`, `?`, `??`, `!!`, and a purple `xmark` for missed win are shown with no explanation anywhere in the UI. `MoveClassification` now has 10 cases including `.book`, `.forced`, and the newly-implemented `.brilliant` (see `handoffs/HANDOFF.md`'s 2026-08-22 entry) - your legend must cover all of them, not just the original six. Design a small, unobtrusive legend (a popover, an expandable disclosure, or a static row - your call, but match this app's existing warm-neutral, forced-light visual identity and do not introduce a new color; `ChessGlossary.swift` already has a `classificationGlosses` dictionary keyed by `MoveClassification` with the exact text to reuse, at `App/Sources/Chessanto/Training/ChessGlossary.swift` - do not write new copy, source it from there). Decide where it belongs (near `classificationRow` is the obvious place) and implement it.

3. **`accuracySummary` shows no percent sign and no indication of which player is the user.** Renders as "White 93.8 · Black 90.8". `BoardIdentityStrip` (find the actual file - search for it) already resolves the username elsewhere in the app; reuse whatever it already does to know which side is "you" rather than reimplementing that resolution. Add a percent sign. Consider (your call, but state your reasoning) whether the user's own side should be visually distinguished the way it already is elsewhere in the report (e.g. "you" replacing "White"/"Black" in `ReportText`, if that convention is what's already used nearby - read `ReportText.playerLabel` in `Packages/AnalysisKit/Sources/AnalysisKit/ReportText.swift` for the existing pattern, but do not modify that file, it belongs to a different in-flight session - only mirror its *reasoning* in the App-layer view code you do own).

4. **Sidebar rows show raw "1-0" when no chess.com username is set.** In `ContentView.swift`'s `GameRow` (or wherever the sidebar row type actually is - confirm the exact name), a learner reads "1-0" as a score rather than a chess result notation. Render it as plain language ("White won", "Black won", "Draw") when there's no username to resolve a "you won"/"you lost" framing, and keep the existing behavior when a username is available (verify what that existing behavior actually is before changing it - it may already do the "you won" framing correctly and this defect may be narrower than the backlog doc implies).

5. **`LinesPanelView` truncates every principal variation to one line and clicking a line immediately adopts it as a variation** - a destructive-feeling action from what reads as an informational row. In `App/Sources/Chessanto/Analysis/LinesPanelView.swift` (confirm exact name), within its existing 260-340pt column: decide whether truncation is the real problem (a `.truncationMode(.tail)` on a fixed-width column with no way to see the rest) or whether the adopt-on-click behavior is the real problem (no confirmation, no distinction between "look at this" and "make this the variation"), or both, and fix what you find. A reasonable minimal fix: separate "view/expand" from "adopt as variation" into two distinct affordances (e.g. a chevron or hover-expand for viewing the full line, a separate explicit action or a second click/button for adopting it) - but verify live what the current interaction actually feels like before deciding, and prefer the smaller fix if it resolves the actual problem.

6. **Eval graph key-moment dots have no independent hit target.** In `App/Sources/Chessanto/Analysis/EvalGraphView.swift`, 6-point dots marking key moments cannot be clicked directly (only the underlying graph area's own interaction, if any, responds). Give each dot a real, larger tappable hit target (e.g. `.contentShape(Circle())` sized generously beyond the visible 6pt dot, in the SwiftUI convention already used elsewhere in this codebase for small-visual/larger-hit-target patterns - search for `.contentShape` usages elsewhere in the App layer for the established idiom) that jumps the board to that moment, consistent with how key moments are already selected elsewhere (`GameReportView`'s `onSelectMoment`, or however `EvalGraphView` already communicates a ply selection outward - read its existing callback/binding shape before adding a new one).

7. **The eval bar is scaled by win probability while its label shows centipawns, with nothing explaining the mismatch.** In `App/Sources/Chessanto/Analysis/EvalBarView.swift`, decide whether to (a) add a brief visual/textual cue that the bar's fill and its label use different scales, or (b) make both use the same currency. Read `EvalLabel.format` (`Packages/AnalysisKit/Sources/AnalysisKit/EvalLabel.swift` or wherever it lives - read only, do not edit AnalysisKit) to understand what the label currently shows and why, before deciding. State your reasoning for whichever you choose.

8. **`PlayerBriefView.reviewAction` shows a disabled "Practice positions" button with no tooltip when no cards exist.** Add a tooltip or inline explanatory text (e.g. "Analyze a game first to generate practice cards") so a disabled control isn't silently unexplained. Small, low-risk fix.

## Required rigor

- TDD for any logic change (this project's standing convention) - most of these are view-layer changes without complex logic, so a passing build plus a live visual check may be the appropriate verification for a pure layout fix; write an actual test wherever real logic is involved (e.g. item 4's result-string formatting, item 3's percent/user-identification logic).
- Use `ui-ux-pro-max` together with `frontend-design` for every item here that has any visual judgment in it (nearly all of them) - this repository's standing rule for any UI/UX change, however small.
- Never use the em dash character ("—"); use a plain dash ("-").
- One full sentence per physical line in any long Markdown you write or substantially edit.
- Do not modify `CHANGELOG.md` or generated files.
- Do not add an agent name as a co-author in commit messages.
- Do not touch `Packages/AnalysisKit` or `Packages/CoachKit` - read-only if you need context from them, but every change in this session stays in the App layer.
- The forced-light warm-neutral and brass visual identity is a deliberate, standing product decision (2026-07-18) - do not redesign it, do not introduce a new color, work within it.

## Validation commands

Run after each individual item, not just once at the end:

1. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 170 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

For anything visual, look at the actual render if your environment allows screen capture (see `scripts/capture-window.swift`) - a green build proves nothing about whether a chip still wraps mid-word. If your environment cannot composite a window (a real possibility - prior sessions in this project have hit this), say so explicitly for whichever items you could not visually confirm, rather than claiming a visual fix is verified when it is not.

## Non-goals

Do not touch `Packages/AnalysisKit` or `Packages/CoachKit`. Do not redesign the visual identity, add a new color token, or add dark mode. Do not implement anything from P4 (teaching depth), P2.5 (Coach entry points), or the board-QA items (a separate parallel session owns those). If you find a defect not listed here while working, note it in your report rather than fixing it - stay inside the 8 items above.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections in the same style as the existing 2026-08-21/2026-08-22 entries.
Write a dated devlog under `devlogs/` in the same style, covering each of the 8 items: what you found on re-verification, what you changed and why, and what you left alone because it was already fine or out of scope.
Commit on this branch (`ui-polish-p5`) and push it to `origin` - do not merge to `main` yourself, a separate integration step will handle that.
Report back plainly: the result for each of the 8 items (fixed / already fine / not verifiable in this environment), the exact files changed, and validation command results.
