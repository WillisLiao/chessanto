# UI/UX clarity phase 3 - locked design and implementation record

This document began as a scoping stub for library management, Player Brief, and chess.com identity confirmation.
The phase 3 implementation session re-verified those inputs, locked the decisions below, executed the test-first build sequence, and completed the native acceptance scenarios on 2026-07-19.

Phase 2 and phase 3 are now implemented, tested, committed, and pushed.
Nothing in this document authorizes or claims the playable-line-preview or Coach-density work specified in `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md`.

## Product direction

Chessanto is a native macOS chess study workspace.
It should feel like a scorebook, analysis desk, and evidence memo rather than a generic dashboard assembled from interchangeable cards.

The implementation compared three concrete interface directions:

1. A native Scorebook centered on dense game rows, direct selection, and macOS controls.
2. An editorial Analysis Desk centered on evidence hierarchy, ruled sections, and compact written findings.
3. A Workbench centered on information density, persistent sources, and square analytical instruments.

The locked direction combines the strongest part of each.
Library navigation follows the Scorebook.
Player Brief follows the Analysis Desk.
Replay and report follow the Workbench.
One shared visual grammar connects all three.

## Shared visual decisions

### DD1 - Structure with alignment and rules

Use aligned rows, registers, dividers, and whitespace for hierarchy.
Do not use a rounded card as the default container.

Why: the product is an analytical desktop tool, and its information has real tabular and sequential structure that should remain visible.

### DD2 - Use system typography

Use system sans-serif for titles, body copy, navigation, and controls.
Use monospaced digits and notation only where alignment or chess notation benefits from it.
Use sentence-case section labels.

Why: rounded display type and uppercase tracking made unrelated surfaces feel like the same generated template.

### DD3 - Brass is a cursor, not decoration

Use brass for the selected-source rule, selected-move cursor, evidence lead rule, active links, and one primary action per context.
Do not use brass as a large decorative fill or as the color for ordinary metadata.

Why: a limited accent makes state and evidence easier to read.

### DD4 - Remove decorative product chrome

Remove capsules, generic icon tiles, the crown and sparkle emblem, gradients, and decorative shadows.
Retain rounded shapes only where a native control or a real geometry needs them.

Why: repeated ornamental treatments made every feature look equally important and obscured the app's native structure.

### DD5 - Use square analytical instruments

Evaluation bars and graphs use square corners, hairlines, and direct labels.
Move classifications use compact marks or inline text rather than pills.

Why: evaluation and classification are measurements, not promotional badges.

### DD6 - Preserve native behavior

Use standard SwiftUI buttons, menus, forms, alerts, context menus, keyboard actions, and accessibility labels.
Custom styling may change hierarchy but must not replace native interaction semantics.

Why: macOS focus, keyboard, and accessibility behavior should remain predictable.

## Item A - library organization and recoverable deletion

### Re-verified facts

`GameStore.deleteGame(id:)` permanently cascaded through dependent tables.
Pinning and favoriting had no persisted representation through migration v5.
The existing detail selection was a single `Int64?`.
Training-card queries could include any game unless explicitly filtered.

### Corrections to the stub

The presence of an end-to-end destructive delete method did not mean ordinary deletion should call it.
A recoverable boundary is required because analysis, variations, chat, training cards, and attempts are valuable derived work.

Bulk selection did not require replacing the detail selection with `Set<Int64>`.
A separate organization selection keeps game navigation and bulk commands independent.

### DD-A1 - Add recoverable deletion

Add nullable `deletedAt` to `game`.
Moving a game to Recently Deleted updates the game row and preserves every dependent record.
Restore clears `deletedAt`.
Permanent deletion is allowed only for a game that is already in Recently Deleted.

Why: the common action becomes reversible while the existing foreign-key cascade remains available behind an explicit boundary.

### DD-A2 - Require two deliberate steps for permanent deletion

Permanent deletion lives only in Recently Deleted.
The user selects the rows, invokes Permanent Delete, and types the required confirmation text.

Why: a stray keyboard action cannot erase analysis and practice history.

### DD-A3 - Keep navigation and organization selection separate

Normal browsing keeps one selected game and one replay detail.
Organize mode owns a separate `Set<Int64>` for bulk pin, favorite, and move-to-Recently-Deleted commands.

Why: selection state has one meaning in each mode and the replay identity remains stable.

### DD-A4 - Model sidebar destinations exclusively

Use one `LibrarySource` enum for All Games, Favorites, Player Brief, and Recently Deleted.
Exactly one source row is selected at a time.

Why: independent booleans can visually select contradictory destinations.

### DD-A5 - Pinning and favoriting are independent

`pinnedAt` controls ordering.
`isFavorite` controls membership in Favorites.
Changing one must not change the other.

Why: pinning is priority while favoriting is classification.

### DD-A6 - Deleted games leave active consumers

Exclude deleted games from active library queries and every training queue query.
Do not delete or rewrite their dependent records until permanent deletion.

Why: hidden games must not create surprise reviews, and restored games must return intact.

### Persistence shape

`v6_gameOrganization` adds:

- `game.pinnedAt DATETIME NULL`.
- `game.isFavorite BOOLEAN NOT NULL DEFAULT 0`.
- `game.deletedAt DATETIME NULL`.
- `game_deletedAt_pinnedAt_playedAt` for active ordering.

`LibraryCommand` is the only product-facing mutation seam:

- `setPinned(Set<Int64>, Bool)`.
- `setFavorite(Set<Int64>, Bool)`.
- `moveToRecentlyDeleted(Set<Int64>)`.
- `restore(Set<Int64>)`.
- `deletePermanently(Set<Int64>)`.

`GameStore.perform` applies one command atomically and reports affected and stale IDs.
The old public direct-delete method is removed so active games cannot bypass the recoverable boundary.

### UI shape

`ContentView` owns `LibrarySource`, the normal replay destination, Organize state, bulk selection, confirmation, and immediate Undo.
`RecentlyDeletedView` owns its finite selectable list, Restore, and typed permanent-delete confirmation.
`GameRow` renders result, pairing, metadata, opening, analyzed state, pin, and favorite in a dense two-line ledger row.

## Item B - evidence-based Player Brief

### Re-verified facts

The former dashboard had only two accuracy points, a review-queue card, three hardcoded themes, and a coverage footer in the QA snapshot.
The report pipeline can cheaply derive per-game accuracy, classifications, selected audited facts, result, color, time control, and opening.
The current fact model cannot reliably label an evaluation swing as tactical or positional.
Dividing a game into equal ply thirds is not formal opening, middlegame, and endgame detection.

### DD-B1 - Make Player Brief a persistent source

Replace the hidden Progress glyph with a labeled Player Brief destination in the source list.

Why: a primary product outcome should not be hidden in a footer icon.

### DD-B2 - Build insights only from stored evidence

`PlayerInsightBuilder` accepts pure `AnalyzedPlayerGame` summaries.
It returns observations with counts, sample sizes, and thresholds.
It does not call the engine, database, or network.

Why: the UI can be tested deterministically and cannot invent a claim beyond the evidence supplied.

### DD-B3 - Show both an improvement focus and a strength

The lead finding identifies a repeated audited motif when it appears across at least two games.
Otherwise it reports the count of costly classified moves or asks for more analysis.

A strength requires at least three games on both sides of a color or time-control comparison and at least a five-point accuracy difference.
When that threshold is not met, the UI says there is not enough comparable evidence to name a strength.

Why: the brief should answer both where the player struggles and where the sample supports a real advantage.

### DD-B4 - Treat sparse evidence honestly

Accuracy history requires at least four games before drawing a trend chart.
Color and time-control comparisons require at least three games per compared group.
Recurring openings require at least two games.
Unsupported sections show threshold copy or remain absent.

Why: two points or a one-game group should not be dressed up as a stable pattern.

### DD-B5 - Call equal thirds what they are

Use First third, Middle third, and Final third.
Include the methodology note that these are equal segments of game length and not formal chess phases.

Why: the computation is useful for clustering mistakes but cannot support stronger terminology.

### DD-B6 - Do not promise unsupported tactical labels

Expose loose-piece punishment, missed forced mate, and allowed forced mate only when those audited facts exist.
Do not add tactical-versus-positional language.

Why: the current model does not encode that distinction reliably.

### Data shape

`PlayerBriefSnapshot` contains:

- Mean accuracy.
- Improvement focus.
- Optional evidence-thresholded strength.
- Context observations.
- Accuracy history.
- Classification counts.
- Audited motif evidence.
- Per-third costly-move rates.
- Color, time-control, and recurring-opening breakdowns.
- Analyzed and imported coverage.

### UI shape

`PlayerBriefView` renders one brass lead rule, a metric register, a responsive main and evidence column, aligned tables, and a final coverage line.
The compact fallback stacks the same sections without changing reading order.
No empty chart or progress-track metaphor appears when the sample is below threshold.

## Item C - confirmed chess.com identity

### Re-verified facts

Chess.com usernames are unique and the public profile endpoint is keyed by username.
The profile endpoint provides username, display name, country, profile URL, and optional avatar URL.
The stats endpoint provides independent current ratings and may fail even when the profile exists.
Only a username string was persisted before this phase.

### DD-C1 - Separate lookup, candidate, and confirmation

Typing or looking up a username never persists it.
Lookup produces a candidate account proof.
Only Use this account confirms the candidate and crosses the caller's persistence seam.

Why: existence is not identity ownership.

### DD-C2 - Share one confirmation component

Use `ChessComUsernameField` in both onboarding and Settings.
Both surfaces show the same account evidence and require the same explicit confirmation.

Why: onboarding and later account changes must not develop different identity guarantees.

### DD-C3 - Keep account proof text-only

Show display name, exact username, country code, profile link, and available ratings.
State in the UI that no remote profile image is loaded.
Do not fetch the avatar.

Why: text supplies the identity evidence without adding a routine outbound image request to a local-first app.

### DD-C4 - Degrade stats independently

If profile lookup succeeds and stats fail, present the candidate with Current ratings unavailable.
Do not discard the valid identity candidate.

Why: optional proof enrichment must not make the primary lookup brittle.

### DD-C5 - Reject stale asynchronous results

Every lookup advances a generation.
Only the latest generation may update the candidate or failure state.
Editing the username invalidates an older candidate and confirmation.

Why: a slow earlier request must not overwrite the account the user most recently requested.

### DD-C6 - Mark persisted confirmation explicitly

Add `userProfile.isChessComAccountConfirmed` through forward-only migration `v7_confirmedChessComIdentity`.
Existing saved usernames migrate with false and must be looked up and confirmed once.
Only an explicitly confirmed account may be presented as Connected or used to open Player Brief.

Why: legacy free text is not proof and cannot be retroactively treated as confirmed.

## Test-first build sequence

### Step 1 - persistence organization commands

Write failing Persistence tests:

- `recentlyDeletedGamesCanBeRestoredWithTheirAnalysis`.
- `pinAndFavoriteAreIndependentBulkOrganizationStates`.
- `permanentDeletionOnlyRemovesGamesAlreadyInRecentlyDeleted`.
- `recentlyDeletedGamesAreExcludedFromThePracticeQueue`.
- `v6MigrationPreservesExistingGamesAndAddsSafeOrganizationDefaults`.

Implement v6, `LibraryCommand`, active and deleted queries, atomic commands, and deleted-game training filters.
Remove the direct permanent-delete API after cascade tests move to the guarded two-step command path.

### Step 2 - Player Brief model

Write failing app tests:

- `recurringAuditedMotifBecomesThePrimaryFocusWithEvidence`.
- `sparseColorDataReportsFactsWithoutCallingThemStrengths`.
- `supportedColorDifferenceBecomesAnEvidenceThresholdedStrength`.

Implement the pure summary types, thresholds, focus selection, strength selection, aggregation, and coverage.
Connect report and analysis data only after the pure tests pass.

### Step 3 - chess.com account proof

Write failing ChessComKit and app tests:

- Rich profile and stats decoding.
- Stats failure preserving a valid profile candidate.
- `lookupPresentsCandidateWithoutConfirmingIt`.
- Stale lookup results cannot replace a newer candidate.

Implement the additive API models and `ChessComAccountLookupModel`.
Connect the shared field to Settings and onboarding only after candidate and confirmation state are independent.

### Step 4 - persisted confirmation

Write failing Persistence tests:

- New profiles default to unconfirmed.
- Confirmation round-trips.
- `v7MigrationRequiresLegacyChessComUsernamesToBeConfirmed`.

Implement v7 and the `UserProfileRecord` field.
Gate Connected presentation and Player Brief on the persisted confirmation flag.

### Step 5 - library UI

Implement exclusive `LibrarySource` navigation.
Implement the scorebook ledger, Organize selection, context commands, confirmation, Undo, and Recently Deleted.
Verify keyboard delete cannot bypass confirmation.

### Step 6 - Player Brief UI

Implement the responsive evidence memo.
Verify sparse, populated, strength, and no-confirmed-account states.

### Step 7 - identity UI

Implement text-only account proof, explicit confirmation, change, disconnect, errors, and no-ratings fallback.
Verify onboarding cannot save typed but unconfirmed text.
Verify a legacy username is prefilled but not labeled Connected.

### Step 8 - visual-system pass

Update shared colors, typography, spacing, and components.
Apply the locked visual grammar to library, replay, report, Coach, onboarding, Settings, evaluation instruments, move classifications, and player identity.
Search the source for retired rounded type, capsules, shadows, uppercase tracking, and emblem use.

## Native E2E acceptance scenarios

All scenarios use a disposable copy of the live database and both QA override environment variables.
The live database md5 is recorded before launch and verified at the end.

### E2E-1 - exclusive source navigation

Click All Games, Favorites, Player Brief, and Recently Deleted.
Exactly one source row shows the brass cursor and selection fill after each click.

### E2E-2 - recoverable deletion

Select one analyzed game in Organize mode.
Move it to Recently Deleted through the count-aware confirmation.
Verify it leaves All Games and the Player Brief coverage decreases.

### E2E-3 - restore with derived work intact

Open Recently Deleted.
Select the moved game and click Restore.
Verify it returns to All Games with its Analyzed marker.
Verify Player Brief coverage returns to its prior count.

### E2E-4 - permanent-delete safeguard

Verify Permanent Delete is unavailable without a selection.
Verify the command requires typed confirmation.
Cancel without mutating the QA database.

### E2E-5 - Player Brief evidence

Open Player Brief for the confirmed account.
Verify the lead finding, metric register, per-third table, strength threshold state, context evidence, and coverage copy match the analyzed sample.

### E2E-6 - identity confirmation

Enter a real chess.com username.
Verify the account proof appears before persistence.
Verify Not me clears it.
Look it up again and use the explicit confirmation action.
Verify Settings presents Connected only after that action.

### E2E-7 - legacy identity

Open a profile migrated from before v7.
Verify the username is prefilled but not labeled Connected.
Verify Player Brief asks for confirmation until the lookup and confirmation flow completes.

### E2E-8 - whole-app visual coherence

Inspect library, replay, Review, report, Coach, onboarding, Settings, evaluation graph, and evaluation bar at the supported minimum window.
Verify one coherent system of typography, rules, selection, and controls.
Verify no clipped labels, double-selected sources, floating dashboard cards, decorative emblem, or narrow evaluation-label wrap remains.

## Acceptance record

Native QA used the database copy under `.../Data/tmp/uiux-phase3-20260719-144827/`.
The implementation moved one analyzed game to Recently Deleted and restored it.
The restored row retained its Analyzed state.
Player Brief returned to 2 of 11 analyzed games after restore.

The first Recently Deleted implementation exposed an oversized internal navigation height and moved its content off-screen.
A finite outer frame did not fix the nested `List`.
Replacing that list with a bounded selectable `ScrollView` fixed the running app.

Library, Player Brief, replay, onboarding, and Settings were captured and inspected in the built app.
The full app suite passed 75 tests across 19 suites.
The package suites passed with counts recorded in `handoffs/HANDOFF.md`.
`engine-smoke`, `coach-grounding`, and the universal Release build passed.

The final safety check detected that only v6 had been applied to the live database during the earlier build and test cycle.
All checked user-data counts matched the pre-session backup.
The live file was restored from the mandatory backup and its md5 returned to `1d218f0371a61f85bc682cc43acb9af5`.

## Still open

UI/UX clarity phase 2 remains unimplemented.
The separate V1 hardening phase 3 backlog remains unstarted.
No richer tactical-versus-positional insight should be claimed until the analysis fact model can support it.
