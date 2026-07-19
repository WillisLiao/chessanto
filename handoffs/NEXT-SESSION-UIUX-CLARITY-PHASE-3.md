# Next session - UI/UX clarity phase 3: library management, player dashboard, and chess.com identity

This is a scoping stub, not a verified execution plan.
Expand it the way `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` was expanded, by reading the source in full and reproducing every claim live before fixing any design decision.

These three items are grouped because they are the parts of the user's feedback that live outside the board and report surfaces, and because they are largely independent of phases 1 and 2.
They could be split further if one session proves too small to hold all three.

## Item A - sidebar select, delete, pin, and favorite

The user wants to select and delete unwanted games from the sidebar, and to pin or favorite specific games.

### Verified during planning

- The delete capability already exists end to end and is simply not wired to any UI.
  `GameLibrary.delete(_ game:)` calls `GameStore.deleteGame(id:)`, and the v1 schema's foreign keys cascade to analysis, variations, chat messages, and training cards.
  Note the bootstrap referred to this as `GameLibrary.deleteGame`; the actual app-level method is `delete(_:)`.
- **Pin and favorite have no data model at all.**
  Confirmed by reading every migration in `Packages/Persistence/Sources/Persistence/Schema.swift`: `v1_games`, `v2_chatMessageSource`, `v3_m8Settings`, `v4_trainingLoop`, and `v5_trainingIndexes`.
  No column on `game` expresses pinning, favoriting, starring, or ordering.
  A forward-only `v6` migration adding a nullable or defaulted column on `game` would be required.
  Never edit a shipped migration.
- `ContentView`'s sidebar is a single-selection `List(library.games, selection: $selectedGameID)` bound to an `Int64?`.
  Multi-select requires changing that binding to a `Set<Int64>` and reconciling it with the detail pane, which currently derives the open game from the same state.

### The part that needs real care

`deleteGame` cascades irreversibly across five tables.
Multi-select delete must confirm before it runs, must say how many games it will remove, and must not be reachable by a single stray keystroke.
Decide explicitly whether an undo is offered or whether confirmation alone is the guard.

## Item B - a genuinely insightful player dashboard

The user wants the bottom-left Progress entry point to open a real analysis of strengths and weaknesses, not just the current chart and theme list.

### Verified live during planning

The current dashboard was opened in the Release app against the QA snapshot.
It rendered an accuracy trend with exactly two points, a `Next lesson` card reading `5 cards ready`, and a footer reading `2 of your games analyzed - 11 games imported`.
The mistake-themes card required scrolling to reach.

So this is confirmed to be an **enhancement of an existing feature**, not a from-scratch build, exactly as the bootstrap suspected.
`computeDashboard` already produces `AccuracyPoint`, `ThemeCount`, and `MoveClassificationCount`.

The genuine weakness is that only three themes exist, because `ThemeCount` is hardcoded to `punishment`, `missedMate`, and `allowedMate`, which are the only three facts `TrainingCardFactory.themes(for:)` also knows about.
That is a thin basis for "where you lack and what to work on".

### What a planning session should establish before designing

Separate what the existing pipeline can already produce cheaply from what would need a new analysis pass.
`ReportBuilder` was measured at roughly 3.55 ms per game in release mode during M8 prep, and the dashboard already recomputes live with no rollup table, so cheap additions are viable.
Candidates worth checking against what `GameReport` and `ReportInput` already carry: phase of game where mistakes cluster, accuracy split by colour, accuracy by time control, opening-specific results via the existing `OpeningBook`, and whether the eval swing came from a tactical or a positional fact.
Verify each against the source before promising it.

Also decide whether the entry point itself should stop being an unlabelled chart glyph in the sidebar bottom bar, which is easy to miss.

## Item C - chess.com identity confirmation

The user wants to enter their name and confirm the exact matching player on chess.com, rather than typing a free-text username.

### Verified live during planning against the real API

The planning session called the real endpoints on 2026-07-19.

`GET https://api.chess.com/pub/player/willisliao` returned, among other fields:
`avatar`, `player_id`, `url`, `name` (`Willis Liao`), `username`, `followers`, `country`, `joined`, `status`, and `league`.

`GET https://api.chess.com/pub/player/willisliao/stats` returned per-time-class ratings including `chess_blitz.last.rating` of 231, which matches the rating band recorded for this user in `NEXT-SESSION-M8.md` fact 12.

Conclusions, verified rather than assumed:

- chess.com usernames are unique and the endpoint is keyed directly by username, so there is no candidate list to disambiguate between.
  "Choose the exact same player" therefore means **a confirmation step**, not a picker.
  This is what the bootstrap hypothesized and it is now confirmed.
- The data needed for a meaningful confirmation card already exists in the public API: avatar image, real name, profile URL, and current ratings.
- `ChessComProfile` in `Packages/ChessComKit` currently decodes only `username`, `name`, and `country`.
  Adding `avatar` and `url` is additive and needs no migration, because the profile is not persisted; only the username string is.
- `ChessComUsernameField` already performs a real existence check via `client.profile(username:)` and reports `Found <name> on chess.com.`
  The gap is that it confirms existence in text rather than showing the user the account it found.

### Open questions for the planning session

- Whether the confirmation lives in first-run onboarding only, or is also re-editable from Settings.
  `CoachSettingsView` and `OnboardingView` already share `CoachSetupView`, so a shared confirmation component would follow the established pattern.
- Whether the app should fetch and display the avatar image at all, given the app is otherwise fully local and this would be its only routine outbound image request.
  This is a privacy-relevant decision and should be put to the user rather than assumed.

## Relationship to the V1 hardening backlog

`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains separately open and is not superseded by this document.
Its practice render-state machine, non-disclosing feedback, duplicate-submit rejection, promotion moves in practice, accessibility matrix, README and version alignment, and the two carried-forward follow-ups for a project `CLAUDE.md` and a root `CONTEXT.md` are all still unstarted.

One incidental defect found live during UI/UX planning belongs there rather than here:
`EvalBarView`'s value label wrapped to two lines, rendering `+0.` above `3`.

## Suggested skills

`diagnosing-bugs`, `tdd`, `ui-ux-pro-max` together with `frontend-design`, and `mattpocock-skills:code-review` before the final commit.
