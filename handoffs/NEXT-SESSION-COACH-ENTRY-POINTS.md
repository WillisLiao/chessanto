# Coach Entry Points Clarity (P2.5) [Completed Historical Record]

Historical note: Coach entry points clarity was completed on 2026-08-24 (see `devlogs/2026-08-24-coach-entry-points.md` and `handoffs/HANDOFF.md`).
This document is preserved as the original session plan.

You are working in a dedicated git worktree on branch `coach-entry-points-p2.5`, checked out from `main`. This is a real, separate checkout - commit and push this branch when you are done, do not attempt to merge to `main` yourself, and do not touch the primary checkout at `/Users/willis/Documents/chessanto` (other sessions may be using it).

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P2.5 Coach entry points" section, for the original framing.
3. `App/Sources/Chessanto/GameReplayView.swift`, in full - specifically the pane-header Coach toggle and the "Ask Coach" button (search for both; one was noted around line 825-832 in a prior scan, confirm the current location) and the move-row context menu's "Ask the coach about this move" (noted around line 1009-1013).
4. `App/Sources/Chessanto/GameReportView.swift`, specifically the key-moment row's context menu "Ask the coach about this moment" (noted around line 266-269).
5. `App/Sources/Chessanto/Coach/ChatView.swift`, in full - specifically the header area showing "Pinned to X" / "Following board · X" (noted around lines 78-101), which is currently the only indicator of which of the three entry points' behavior is active.
6. `App/Sources/Chessanto/GameReplayViewModel.swift` - `@Published var pinnedChatIndex: MoveIndex?` (noted around line 666), `var isChatPinned: Bool` (line 668), and `var chatPositionLabel: String` (lines 788-799), which together are the actual state model behind the indicator text. Read enough of this file to understand exactly when `pinnedChatIndex` is set and cleared, by which of the three entry points, before changing anything.
7. This repository's `ui-ux-pro-max` and `frontend-design` conventions apply to every visual/interaction decision in this session - both together, per the project's standing rule for any UI/UX change.

## The problem

Three ways into the Coach, three different behaviors, and one small line of text is the only thing that tells the user which mode they are in:

1. The pane-header toggle follows the board (moves as you step through the game).
2. "Ask Coach" in the board controls pins to the current ply.
3. The move-row / key-moment context menu's "Ask the coach about this moment" pins to that specific ply.

A user who opens the Coach from the header, then later right-clicks a different move and asks about it, may not notice the mode changed from "following" to "pinned" - the panel does not visibly change shape or color, only a small caption line updates. The backlog document calls this out explicitly as confusing, without prescribing an exact fix.

## Scope for this session

Make it visually and behaviorally obvious which of the three entry points is active and what "pinned" versus "following" actually means to the user, without adding a fourth entry point or redesigning the panel's core layout.

You have real design latitude here - this is a clarity pass, not a fully specified change. Concretely decide and implement:

1. **A stronger visual distinction between "following the board" and "pinned to a specific move"** than the current caption line alone - consider (your call, but state your reasoning): a different header treatment (icon, color accent already in the app's existing warm-neutral/brass palette, not a new color), a persistent small badge on the pinned move's row itself so the user can see which move the panel is talking about without reading the caption, or both.
2. **A visible, obvious way to un-pin** - "return to following the board" - if one does not already exist or is not discoverable (check whether `pinnedChatIndex` can currently be set back to `nil` from the UI at all, versus only by navigating away or closing the panel).
3. **Consistent labeling across all three entry points** - if the button/menu-item text differs ("Ask Coach" vs "Ask the coach about this move" vs "Ask the coach about this moment"), decide whether that's intentional (context makes the exact wording appropriate to where it appears) or should be unified, and say why.
4. **Confirm live, not just by reading the code, what actually happens today** when you trigger each of the three entry points in sequence (e.g. open via header while following, then right-click a different move and ask about it, then step the board forward) - the backlog document's description is a starting hypothesis, not a confirmed diagnosis. If your build environment can composite/screenshot a window, use it; if not (a real possibility in some environments - check `scripts/capture-window.swift` and `scripts/axprobe.swift` for the existing tooling and note explicitly if compositing is unavailable to you), verify via the accessibility tree and state clearly what you could and could not visually confirm.

## Required rigor

- Use `ui-ux-pro-max` together with `frontend-design` for the visual/interaction decisions in this session - this repository's standing rule for any UI/UX change, however small.
- The forced-light warm-neutral and brass visual identity is a deliberate, standing product decision (2026-07-18) - do not redesign it, do not introduce a new color, work within it. Green is reserved for the board arrow and move-classification colors only and must never enter this panel's chrome.
- `CoachVerifier`'s grounding guarantee (nothing unverified renders) is unrelated to this session's scope - you are changing when/how the panel indicates its mode, not what the Coach says. Do not touch `CoachPrompt.swift`, `CoachChat.swift`, `CoachNarrator.swift`, or anything in `Packages/CoachKit`.
- TDD for any logic change (e.g. if you add or change how `pinnedChatIndex` transitions) - most of this session is view-layer, so a passing build plus a live/AX-tree-verified check may be the right verification for a pure presentation change; write an actual test wherever real state-transition logic changes.
- Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in any long Markdown you write or substantially edit. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Validation commands

1. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 174 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

For anything visual, look at the actual render if your environment allows screen capture - a green build proves nothing about whether the pinned state is actually obvious to a user looking at the screen. If your environment cannot composite a window, say so explicitly for whichever items you could not visually confirm, rather than claiming a visual fix is verified when it is not.

## Non-goals

Do not touch `Packages/AnalysisKit` or `Packages/CoachKit`. Do not redesign the Coach panel's overall layout, docking behavior, or the three entry points' fundamental existence (all three stay; this is about making the active one legible, not reducing to one). Do not touch the LLM prompt or grounding/verification logic. P4.2, P4.3, P4.5, P4.6, P4.8 (separate parallel sessions or future work). The dark-mode question referenced elsewhere in the backlog is explicitly not part of this session.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries - other parallel sessions are touching this same file and it will be merged by hand afterward, so keep your addition self-contained and easy to splice in.
Write a dated devlog at **`devlogs/2026-08-24-coach-entry-points.md`** (this exact filename, not the bare date - two other sessions are writing their own devlogs today and a shared filename causes a git conflict during integration).
Commit on this branch (`coach-entry-points-p2.5`) and push it to `origin` - do not merge to `main` yourself, a separate integration step will handle that.
Report back plainly: what you found when you verified the current behavior live, the exact design decisions you made and why, what you could and could not visually confirm, and validation command results.
