# Next Claude session - Opus planning for Sonnet medium

## Purpose

Use Claude Opus for one planning-only session.
The output must be a concrete, self-contained execution plan for one subsequent Claude Sonnet medium session.
Do not implement product code during the Opus planning session.

The next implementation session is a UI/UX clarity and interaction pass over the practice, report, and replay surfaces, driven directly by live user feedback given while looking at the running app after V1 hardening phase 2 landed.
This is a new feature area, not a continuation of V1 hardening's engine/grading correctness work, which is now closed out (see `handoffs/HANDOFF.md`'s "V1 hardening phase 2 complete" section and `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md`).

## Prompt to give Claude Opus

```text
You are planning the next Chessanto implementation session.
Use Claude Opus for this task.
This is planning and live verification only.
Do not change product code.

Start from the latest main branch and verify that it is clean and synchronized with origin/main.
The expected tip is the commit named "Harden engine search and training grading for V1".

Read these files completely before planning:

- The repository and workspace AGENTS.md instructions that apply to this checkout (there is currently no physical AGENTS.md file; the repository rules live in the session prompt instead - note this in your plan exactly as prior sessions have).
- handoffs/HANDOFF.md, in full.
- The "V1 hardening phase 2" section of devlogs/2026-07-19.md.
- handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md (the currently open V1 hardening backlog - this new UI/UX work is separate from it, but check for overlap, e.g. the "900-point replay and practice layout" and "contrast, target size, keyboard, focus" items already listed there).
- App/Sources/Chessanto/Training/PracticeSessionView.swift and PracticeSessionViewModel.swift in full.
- App/Sources/Chessanto/Board/BoardView.swift in full.
- App/Sources/Chessanto/GameReportView.swift in full.
- App/Sources/Chessanto/GameReplayView.swift in full.
- App/Sources/Chessanto/Training/TrainingDomain.swift, specifically TrainingCardFactory.themes(for:) and DefaultTrainingMoveEvaluator.feedback(...).
- Packages/CoachKit's CoachPrompt.swift and CoachNarrator.swift, to understand how key-moment narration text is generated today and what levers exist to shorten it without weakening CoachVerifier's grounding guarantee.
- Packages/AnalysisKit's ReportText.swift, since the rule-based (non-Coach) explanation strings shown in practice feedback and Report key moments originate there.
- App/Sources/Chessanto/ContentView.swift in full, specifically the sidebar `List(library.games, selection:...)` and the private `GameRow` type.
- App/Sources/Chessanto/GameLibrary.swift, specifically `deleteGame` and `saveChessComUsername` - both already exist as data-layer capabilities that new UI may just need to wire up rather than build from scratch.
- App/Sources/Chessanto/Dashboard/DashboardView.swift in full - `accuracyTrend` and `mistakeThemes` already exist from M8 as a starting point, so "a full insightful dashboard" is most likely an enhancement of an existing feature, not a from-scratch build. Verify this live before assuming otherwise.
- App/Sources/Chessanto/Onboarding/OnboardingView.swift in full, specifically the `.username` page and `ChessComUsernameField` - username entry and validation already exist; verify exactly what "choose the exact same player" requires beyond that (e.g. a confirmation step showing the matched profile's avatar/rating before proceeding) against the real chess.com public API, the way M4's chesscom-smoke executable already does for other endpoints.
- Packages/Persistence's schema/migrations, since a pin/favorite concept for games does not exist in the current schema (confirm this by reading the migrations, not by assuming) and would need a new forward-only migration if added.

## The live feedback driving this session

The user reviewed several screens in the running Release app (screenshots are not attached to this plan; describe what you independently observe live instead of trusting this paraphrase) and gave this feedback, verbatim intent preserved:

1. Practice feedback card (PracticeSessionView, the `.feedback` state inside `promptCard`): chess terminology like "en prise" and "O-O" is not explained for users unfamiliar with chess notation - it should be clarified in plain language, while still teaching the real term. "Start from e8" (the hint-level-2 text) should also make the board glow or otherwise highlight square e8, not just state it in text. Moves mentioned in the explanation prose - both the suggested better line (e.g. "Better was O-O (O-O Nd3 Qe7+ Be2 Nxh1 Nxc5)") and the actual bad continuation that was played - should be able to play out on the board itself when the user chooses to see them, not just appear as SAN text in a paragraph.
2. Main replay board (GameReplayView): there is currently no indication near the board itself of which side (top vs. bottom) belongs to which named player. The window's navigation title has "White vs Black" player names, but nothing next to the board does.
3. Report key moments (GameReportView.keyMomentRow, the Coach-generated narration path specifically): the Coach's prose is too dense/packed for the space it's shown in and needs simplifying while still keeping the material facts (the actual move played, the eval swing, the better alternative) intact. This is LLM-generated text gated by CoachVerifier's grounding checks, so any prompt change must be re-verified live against coach-grounding, not just visually shortened after the fact.
4. Report key moments row click target: clicking a key moment only jumps the board to that position when the click lands near the move-number/SAN text at the left edge of the row, not anywhere else in the row. Read `keyMomentRow` in GameReportView.swift closely - the Button's label HStack has `.contentShape(Rectangle())` but the HStack itself has no `.frame(maxWidth: .infinity, ...)` modifier, unlike the structurally similar `moveCell` in GameReplayView.swift which does have one. Verify live (native app, real clicks via the existing scripts/axclickat.swift or scripts/axclick.swift, not just source reading) whether this is the actual root cause before committing to a fix, and check whether the same pattern (or lack of it) affects any other row-style button in the app (e.g. sidebar game rows, chat message rows).
5. Sidebar game list (ContentView's `List`/`GameRow`): the user wants to be able to select and delete games they don't want from the sidebar, and to pin or favorite ("heart") specific games. `GameLibrary.deleteGame` already exists; the UI to select/multi-select/swipe-to-delete does not. Pinning/favoriting has no existing data model at all - confirm this by reading the schema, then decide whether it needs a new column/migration.
6. The bottom-left "Progress"/dashboard entry point: the user wants this to open a genuinely useful, insightful dashboard of the player's strengths and weaknesses - a generalized analysis of where they lack and what to work on - not just the current accuracy-trend chart and mistake-theme list. Investigate what `DashboardView` already computes (`computeDashboard`, `AccuracyPoint`, `ThemeCount`, `MoveClassificationCount`) before deciding what is missing versus what already exists and is merely under-surfaced or under-explained.
7. Onboarding: whenever the user enters the app (or on first run), they should enter their name and select/confirm the exact matching player on chess.com, not just type a free-text username. `OnboardingView`'s `.username` page and `ChessComUsernameField` already validate a chess.com username exists; verify live against the real chess.com API (per `chesscom-smoke`'s pattern) what additional confirmation is possible or meaningful - chess.com usernames are unique, so "choose the exact same player" most likely means a confirmation step (show the matched profile back to the user, e.g. avatar/rating/name) rather than a disambiguation among multiple candidates. Verify this assumption live before designing around it.

Do not treat any of the above as a confirmed diagnosis except item 4's specific code-reading observation.
Reproduce each issue live in the running app first, the way the phase-2 planning session reproduced F1/F2 before writing that plan - this project's own convention (see the diagnosing-bugs skill and every prior planning session in this repo) is that a plan built on live-verified facts survives contact with implementation; a plan built on a paraphrase of a screenshot does not.

## Known project constraints to respect while planning

- The forced-light warm-neutral and brass visual identity, the board, the pieces, the app icon, and the Chessanto identity are not to be redesigned - this is a clarity and interaction pass, not a redesign.
- Green stays confined to the board arrow and the reserved move-classification colors, and never enters application chrome.
- CoachVerifier's grounding guarantee (nothing unverified renders) must not be weakened by any Coach-prompt change aimed at brevity. If shortening the prompt risks the verifier rejecting more responses and falling back to rule-based text more often, say so explicitly and decide whether that tradeoff is acceptable, rather than silently accepting a worse fallback rate.
- `RankedLine` (Packages/AnalysisKit/Sources/AnalysisKit/ReportInput.swift) is `Codable` and persisted in `trainingCard.rankedLinesJSON` - do not change its shape without a migration plan if playable-variation support needs more data than it currently carries (e.g. full PV move lists per ranked line, which `RankedLine.principalVariationUCI` may already provide - verify what is already persisted before assuming new fields are needed).
- The native database-safety procedure from prior sessions applies to any native QA: sandbox backup, disposable copy, both opt-in environment variables.

## What the plan must decide

1. Whether the playable-variation feature (item 1's second half) is in scope for one Sonnet medium session, or should be split into its own follow-up - it is one of the largest single items here (board state must be able to step through moves that are not part of the actual game tree, then return cleanly to the practice/prompt state).
2. A concrete design for glossary/plain-language explanation of chess terms (en prise, O-O, and any others found during investigation) - inline parenthetical, tooltip, or expandable disclosure - that fits the existing warm-neutral card design without adding a new visual language.
3. A concrete design for the hint-square highlight (reuse BoardView's existing arrow/highlight mechanism if one already exists and fits, rather than inventing a new visual affordance).
4. Where the player-name labels near the main board should live and how they should behave when the board is flipped.
5. Whether the Coach-text-density fix is a prompt change (CoachKit), a rendering change (truncate/expand in the view), or both - and how it will be verified live against coach-grounding, not just read for length.
6. The exact root cause and fix for the key-moment row hit-target bug, confirmed live, and whether the same fix is needed elsewhere.
7. A concrete design for sidebar select/delete and pin/favorite, including whether pin/favorite needs a schema migration, and how a multi-select delete confirms before an irreversible `deleteGame` cascade.
8. What "a full insightful player dashboard" concretely adds beyond the existing accuracy trend and mistake themes - name the specific new metrics or views, sourced from what the engine/report pipeline can already produce without a new analysis pass, versus what would need one.
9. What "choose the exact same player on chess.com" concretely means and where it fits in the app's lifecycle (first-run onboarding only, or also re-editable later from Settings) - verify against the real chess.com API before designing the confirmation UI.

This is a substantially larger scope than one Sonnet medium session, spanning at least three largely independent feature areas: practice/report clarity (items 1-4), Coach text density (item 3, but engine/prompt work is its own risk category), and library/dashboard/onboarding (items 5-9).
Do not compress this into one plan.
Split it into multiple self-contained phase plans, each independently executable by one Claude Sonnet medium session, the same way V1 hardening was split into phase 2 and phase 3.
Order the phases by user value and risk, and say explicitly why you chose that order.
Write only the first phase's plan in full detail during this planning session; for the remaining phases, write a short scoping stub (in the same style as this document's own "carried-forward follow-up" sections) that a later planning session can expand, rather than fully designing work that is two or three sessions away and may drift by the time it is picked up.

Write the first phase's plan to handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md, and name subsequent phase stubs handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md, -PHASE-3.md, and so on, following the same naming convention V1 hardening used.
Make the first phase plan directly executable by Claude Sonnet medium with no further design interview.

The first phase plan must contain:

- A short verified diagnosis for each item it covers, with file and symbol references, and live reproduction evidence (native app, real interaction, not just source reading) wherever the issue is observable live.
- Explicit in-scope and out-of-scope boundaries sized for one Sonnet medium session, naming which of the 9 numbered items above are deferred to a later phase.
- Fixed design decisions for the visual/interaction questions above and the reasons for each.
- A red-green-refactor sequence with small verification gates, following this project's established TDD pattern.
- Exact test names and commands.
- If the Coach prompt changes: an explicit live coach-grounding re-verification step, not just a visual check.
- A production-aligned E2E reproduction and acceptance scenario using the native app and the existing scripts/axprobe.swift, scripts/axclick.swift, scripts/axclickat.swift, scripts/capture-window.swift tooling.
- Native data-safety instructions (sandbox backup, disposable copy, both opt-in environment variables).
- Documentation, devlog, commit, and push requirements.
- A final checklist that prevents claiming out-of-scope items as complete.
- Suggested skills for the Sonnet session, explicitly including ui-ux-pro-max and this repository's frontend-design skill for every part of the plan that touches visual or interaction design, per the standing repository rule that both are used together for any substantial UI/UX change.

Apply the repository rule that every full sentence in a substantially edited Markdown document occupies its own physical line.
Never use the em dash character.
Do not modify CHANGELOG.md or generated files.
Do not add an agent co-author to commits.

End the Opus session by reporting:

- The path to the new plan.
- The verified starting commit.
- The exact one-line prompt the user should give Claude Sonnet medium.
- Any blocker or scope-split decision that needs the user's sign-off before implementation.
```

## Suggested skills for the Opus planning session

- Use `diagnosing-bugs` to reproduce each of the seven feedback items live before settling the plan, especially the row hit-target bug's root cause.
- Use `ui-ux-pro-max` together with this repository's `frontend-design` skill to design the glossary/highlight/player-label/text-density solutions before committing to an approach in the plan.
- Use `codebase-design` if a new seam is needed for playable-variation board state (e.g. a preview mode distinct from the practice game tree).
- Use `grill-with-docs` only if a real design ambiguity survives live investigation.

## Suggested skills for the Sonnet medium implementation session

- Use `implement` to execute the plan.
- Use `tdd` for every logic change (theme/explanation text generation, hit-target fix, highlight state).
- Use `diagnosing-bugs` for native reproduction before each fix, per this plan's own diagnosis section.
- Use `ui-ux-pro-max` together with `frontend-design` for every visual or interaction change, per the standing repository rule.
- Use `mattpocock-skills:code-review` before the final commit, with the phase-specific plan as the spec axis.

## Sources of truth

`handoffs/HANDOFF.md` is the chronological project snapshot.
`devlogs/2026-07-19.md` contains the exact V1 hardening phase 2 record, including the native AX-scripting tooling's sharp edges (the `--last` flag requirement for `axclick.swift`, and `axclickat.swift`'s unreliable raw-coordinate clicks on at least one toolbar button) that the next native QA pass should expect.
`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` is the still-open V1 hardening backlog, kept separate from this UI/UX clarity work.
This document only routes the next planning session and intentionally does not duplicate those artifacts.
