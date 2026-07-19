# Next session - UI/UX clarity phase 1: inline practice, plain language, and real hit targets

This is a self-contained execution plan for one Claude Sonnet medium session.
Every diagnosis below was reproduced live in the Release app against a disposable database copy during the Opus planning session on 2026-07-19.
Where the planning session's own bootstrap made a claim that live testing contradicted, this document records the correction rather than the claim.

## Starting point

The expected tip is `ad40e49` "Rewrite the Opus planning bootstrap for a UI/UX clarity pass".
The last commit that changed product code is its parent `f55eeb6` "Harden engine search and training grading for V1"; `ad40e49` touched only `handoffs/NEXT-CLAUDE-OPUS-PLANNING.md`.
Confirm `main` is clean and synchronized with `origin/main` before starting.

This checkout has no physical `AGENTS.md` and no project-level `CLAUDE.md`.
The repository rules reach the agent only through the session prompt, exactly as in every prior session.
Do not create either file to satisfy an instruction that references it; authoring a project `CLAUDE.md` is still carried as Follow-up A in `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md`.

## Relationship to the still-open V1 hardening backlog

`handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` remains open and separate.
Two of its items overlap this phase and are deliberately pulled forward here, because this phase restructures the exact views they concern and leaving them behind would mean touching the same code twice:

- The "900-point replay and practice layout" item is partly absorbed, because Step 1 removes the fixed 420pt practice board and the 760x560 sheet entirely.
- The "contrast, target size, keyboard, focus" item is partly absorbed for the two surfaces this phase rebuilds, and only for those.

Everything else in phase 3 stays out of scope, including the full practice render-state machine, non-disclosing incorrect feedback, duplicate-submit rejection, review decisions for Reveal and Skip, promotion moves in practice, and README and version alignment.

## Verified diagnosis

Each item below states what was observed live, with the file and symbol that produces it.
Screenshots were captured with `scripts/capture-window.swift` and text was read with `scripts/axprobe.swift` against the Release build.

### D1 - Practice teaches chess jargon without explaining it

Live evidence, `PracticeSessionView.promptCard`:

- The classification chip renders as a bare `?!` glyph with no words.
  `ClassificationChip(classification: card.classification)` is called with no count and no label, so a learner sees punctuation only.
- Hint level 1 rendered the literal string `Material left en prise`.
  Source: `TrainingCardFactory.themes(for:)` in `App/Sources/Chessanto/Training/TrainingDomain.swift`, which appends `"Material left en prise"` whenever `moment.punishment != nil`.
  Five of the eight training cards in the QA snapshot carry this theme.
- The `.strong` feedback rendered, verbatim from `axprobe`:
  `4... Nxe4 drops your winning chances from 41% to 24%. Better was Nb8 (Nb8 Bd3 d6 c4 g6 h3), keeping the evaluation around +1.0. This also left the knight on c6 hanging: dxc6 winning the knight.`
  Source: `card.explanation`, which is `ReportText.momentSummary(_:report:)` persisted into `trainingCard.explanation` by `TrainingCardFactory.drafts`.
  This is the densest text in the feature and it appears when the learner answers correctly.

The user's verbatim example, `Better was O-O (O-O Nd3 Qe7+ Be2 Nxh1 Nxc5)`, is training card id 6 in the QA snapshot (gameId 9, sourcePly 14).
It is real persisted data, not a paraphrase.

### D2 - Hint level 2 names a square but does not show it

Live evidence: with two hints taken, the prompt rendered `Start from c6.` while the board showed no highlight of any kind on c6.
Source: `PracticeSessionView.promptCard` renders `Text("Start from \(String(best.prefix(2))).")` and `BoardView` is passed no highlight for that square.
`BoardView` already has three square-overlay channels (`theme.highlight` for last move, `theme.selected`, `theme.destination`) and an `arrows` channel, but nothing wired to a hint.

### D3 - Practice opens a small board in a modal sheet

Live evidence: `Practice key moments` opened an `AXSheet` of exactly 760x560 containing a 420x420 board, over a dimmed replay window whose own board renders at roughly 600pt.
The right-hand prompt column occupied about a third of the sheet height and the remainder was empty.
Source: `PracticeSessionView.body` has `.frame(minWidth: 760, minHeight: 560)`, `practiceBody` pins the board with `.frame(width: 420, height: 420)`, and both entry points present it with `.sheet` (`GameReplayView.movesReportColumn` and `DashboardView.nextLesson`).

The user raised this directly during the planning session and confirmed the intended resolution:
practice should run inline on the existing full-size board with no modal sheet, while the training-card data model, the spaced-repetition scheduler, and the Progress queue all stay exactly as they are.
Only the presentation changes.

### D4 - Key-moment row hit target: the bootstrap's diagnosis is wrong

The planning bootstrap asserted that `keyMomentRow`'s label `HStack` lacks `.frame(maxWidth: .infinity, ...)` unlike `moveCell`, and named this the one item that could be treated as a confirmed diagnosis.
Live testing contradicts it.

- A real `CGEvent` click at the far right edge of the `4... Nxe4` row, deep inside the `Spacer()` region and far from any text, **did** jump the board to that ply.
  The `Spacer()` plus `.contentShape(Rectangle())` already extends the hit area across the full row width.
- A real click on the summary prose directly beneath the same header line did **not** move the board.

The actual root cause is vertical, not horizontal.
In `GameReportView.keyMomentRow`, the `Button` wraps only the header `HStack` (move number, SAN, classification chip).
The summary `Text`, the Coach narration block, its `Coach` / `Rule-based` caption, and the `Practice` button are siblings inside the enclosing `VStack`, outside the `Button` entirely.
The visual block is roughly 200pt tall in the current layout; the clickable region is a single text line of roughly 20pt at its top.
From the user's seat that reads as "only near the move-number text", because the header line is short, left-aligned, and the prose below is where the cursor naturally lands.

The structurally similar `moveCell` in `GameReplayView` is not affected, because it is a single-line cell with no sibling content.
No other row-style button in the app has a tall non-interactive body under a short button: `GameRow` in `ContentView` is a `List` row whose selection is handled by `List` itself, and the chat message rows expose their own per-message jump buttons.

### D5 - No player identity anywhere near the board

Live evidence: with `adamzainuri vs WillisLiao` open, the only place either name appeared was the window title bar at the very top of the window, far above the board and separated from it by the whole toolbar.
Nothing adjacent to the board indicated which side was which.
In this specific game the user played Black, so the user's own pieces were at the top of a default-orientation board with no label at all.
Source: `GameReplayView.body` sets `.navigationTitle("\(game.white) vs \(game.black)")` and `boardColumn` contains only `EvalBarView` and `BoardView`.

### D6 - Incidental defects observed live

Recorded so they are not lost.
Only the first is in scope for this phase, because this phase rebuilds the view that contains it.

- Clicking `Hint` shifts the `Hint` and `Reveal` buttons downward as the new hint text is inserted above them, so a second click at the same screen point misses the button.
  This was reproduced live and cost a click during verification.
  In scope: the practice prompt must reserve stable space for hint text so the controls do not move.
- The eval bar's value label wrapped to two lines, rendering `+0.` above `3`, in `EvalBarView`.
  Out of scope for this phase; log it in the devlog and carry it into phase 3.

## In scope for this phase

1. D3: practice runs inline on the full-size board, with the modal sheet removed from both entry points.
2. D4: the whole key-moment block becomes the jump target.
3. D5: player identity labels adjacent to the board, correct under flip.
4. D1 partial: plain-language explanation of chess terms and classification marks in the practice prompt and feedback.
5. D2: the hint square is highlighted on the board.
6. D6 first bullet: stable hint layout.

## Explicitly out of scope for this phase

Name these in the final checklist and do not claim them.

- Playable variations, meaning stepping the better line or the actual game continuation out on the board.
  This is deferred to phase 2 and is the single largest item in the whole UI/UX clarity backlog.
  It depends on inline practice existing first, which is precisely why this phase lands the container and phase 2 lands the feature.
- Coach text density, meaning any change to `CoachPrompt` or the narration rendering.
  Deferred to phase 2, where it can be paired with a live `coach-grounding` re-verification.
- Sidebar select, delete, pin, and favorite.
  Deferred to phase 3.
- The richer player dashboard.
  Deferred to phase 3.
- chess.com identity confirmation during onboarding.
  Deferred to phase 3.
- Everything in `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` except the two items named in the overlap section above.

## Fixed design decisions

These are settled.
Do not reopen them; implement them.

### DD1 - Practice becomes a mode of the replay workspace, not a sheet

Add `case practice` to `GameReplayView.RightPaneTab`, entered programmatically rather than by the user clicking a segment, and rendered as a full-width mode rather than a third segment.

While practice is active:

- `boardColumn` renders the practice position, orientation, selection, legal destinations, hint highlight, and reveal arrow, driven by `PracticeSessionViewModel` instead of `GameReplayViewModel`.
- The board keeps whatever size the window gives it.
  Do not reintroduce a fixed width or height.
- The replay-only chrome that is meaningless during practice is hidden: the step and jump controls, the eval graph, the lines panel, and the analysis controls.
  The flip button stays.
- The right pane shows the practice prompt, hints, feedback, and session progress, in the same `Card` idiom the Report uses.
- A clear `Exit practice` control returns to `.report`.

`DashboardView.nextLesson` currently presents its own `.sheet`.
The dashboard is itself a sheet over `ContentView`, so nesting a second sheet inside it is the thing to remove.
Replace it with a callback that dismisses the dashboard and asks `ContentView` to open the selected game in practice mode.
`ContentView` owns game selection already, so this is the natural owner.

Rationale: the user asked for the same board at the same size with no popup.
A mode of the existing workspace gives that for free and also inherits the responsive behavior the replay pane already has, which is why the fixed 420pt board and the 760x560 minimum can simply be deleted rather than re-tuned.

### DD2 - Plain language sits beside the term, never replaces it

The user asked for clarification "while still teaching the real term".
So every jargon token keeps its real name and gains a short plain-language gloss immediately after it, in `DesignColors.textSecondary` at `.dsSecondary`.

Concrete form, in the practice prompt and feedback only:

- The bare classification chip gains its word: `?!` becomes the chip plus `Inaccuracy`, using the existing `MoveClassification` label vocabulary rather than a new one.
- Theme hints gain a gloss: `Material left en prise` renders as the term followed by `left where the opponent can capture it for free`.
- Introduce one new type, `ChessGlossary`, in `App/Sources/Chessanto/Training/`, mapping a term to a one-sentence plain-language gloss.
  Seed it with exactly the terms this codebase can actually produce, verified against source rather than invented:
  `en prise`, `hanging`, `forced mate`, `O-O`, `O-O-O`, and the eight `MoveClassification` cases.
  `O-O` and `O-O-O` are produced by `ChessCore` SAN and appear in real card explanations, confirmed in the QA snapshot.
- Do not build a tooltip or a hover affordance.
  Do not build an expandable disclosure.
  Inline secondary text is already the card's own idiom, adds no new visual language, and survives at every width.

`ChessGlossary` is a pure lookup with no view dependency, so it is unit-testable without a host app.

### DD3 - The hint square uses its own board token

Add `var hint: Color` to `BoardTheme`, and a `hintSquares: Set<BoardSquare>` parameter to `BoardView`, rendered in the same overlay `ZStack` the existing highlights use.

Do not reuse `theme.destination`, which is green and already means "a legal destination for the piece you selected".
Do not reuse `theme.selected`, which is blue and already means "you picked this piece".
Do not reuse `theme.highlight`, which is yellow and already means "this was the last move played".
Reusing any of the three would overload a meaning the learner has already been taught elsewhere in the same board.

Use the brass accent at low opacity plus a stroked ring, so it reads as a distinct fourth channel.
This does not violate the green rule, which constrains green from entering application chrome and says nothing about brass appearing on the board; and brass is already the app's accent everywhere else, so this introduces no new hue.

### DD4 - The whole key-moment block is the jump target

Restructure `GameReportView.keyMomentRow` so the `Button` wraps the entire moment block: header line, summary, Coach narration, and source caption.
The nested `Practice` button stays a separate control and must remain independently clickable, which is why it moves outside the outer button's label and sits beneath it.

Keep `.buttonStyle(.plain)` and `.contentShape(Rectangle())`.
Add a hover and pressed background using `DesignColors.surface1` so the block visibly reads as clickable, which it currently does not.
Keep the existing `.accessibilityLabel` and `.contextMenu`.

Do not add `.frame(maxWidth: .infinity, ...)` "to fix the hit target".
Live testing proved the horizontal extent already works, and adding it would be a change made against evidence.

### DD5 - Player labels are a board-adjacent strip, above and below

Render a compact identity strip immediately above and immediately below `BoardView` in `boardColumn`, each showing the side's name and, when present, its rating from `GameRecord.whiteRating` / `blackRating`.

Behavior under flip:
the strips are bound to screen position, not to color.
The bottom strip always names whoever is at the bottom of the board as currently drawn, so flipping swaps the two strips.
This is what every mainstream analysis board does and it is the only behavior that stays true to what the user sees.

Mark the user's own side when `GameLibrary.chessComUsername` matches, reusing the case-insensitive comparison already used by `GameRow.userOutcome` and `ReportInput.isUser`.
Do not introduce a second matching rule.

During practice mode the same strips render from the practice card's own orientation, which is `PracticeSessionViewModel.flipped`.

### DD6 - Hint layout is stable

Reserve the vertical space for both hint lines from the start of a card, so revealing a hint fills reserved space rather than growing the card and displacing the controls beneath it.

## Build sequence

Follow red-green-refactor.
Each step has a verification gate that must pass before the next step starts.
Run `xcodegen generate` after adding any file, because `Chessanto.xcodeproj` is generated and gitignored.

### Step 1 - `ChessGlossary`

Red: add `App/Tests/ChessantoTests/ChessGlossaryTests.swift`.

- `testGlossesEveryTermThemeGenerationCanProduce` asserts a gloss exists for each of the three strings `TrainingCardFactory.themes(for:)` can emit.
- `testGlossesEveryMoveClassification` iterates `MoveClassification.allCases` and asserts a non-empty plain-language gloss for each.
- `testGlossesCastlingNotation` asserts `O-O` and `O-O-O` resolve.
- `testUnknownTermReturnsNil` asserts the lookup does not invent text.

Green: add `App/Sources/Chessanto/Training/ChessGlossary.swift`.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/ChessGlossaryTests`.

### Step 2 - Hint square on the board

Red: add `testHintSquaresAreEmptyBeforeSecondHint` and `testSecondHintExposesBestMoveOriginSquare` to `PracticeSessionViewModelTests`, driving a new `hintSquares: Set<BoardSquare>` computed property that is empty at `hintCount < 2` and contains exactly the best move's origin square at `hintCount >= 2`.

Green: add the property to `PracticeSessionViewModel`, add `hint` to `BoardTheme`, add `hintSquares` to `BoardView`, and render it.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/PracticeSessionViewModelTests`.

### Step 3 - Key-moment block hit target

This is a view-structure change with no view-model seam, so it is verified natively rather than by unit test.
Restructure `keyMomentRow` per DD4.

Gate: build, then the native check in the E2E section below, specifically E2E-2.
Do not mark this step done on source reading alone.
The bootstrap's own source-reading diagnosis of this exact code was wrong.

### Step 4 - Player identity strips

Red: add `App/Tests/ChessantoTests/BoardIdentityStripTests.swift` covering a small pure helper that decides, given white name, black name, ratings, `flipped`, and the configured username, what the top and bottom strips say and which one is marked as the user.

- `testBottomStripIsWhiteWhenNotFlipped`
- `testBottomStripIsBlackWhenFlipped`
- `testMarksConfiguredUserCaseInsensitively`
- `testNoUserMarkWhenUsernameIsEmpty`
- `testOmitsRatingWhenAbsent`

Green: add the helper and render the strips in `boardColumn`.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/BoardIdentityStripTests`.

### Step 5 - Plain language in the practice prompt and feedback

Red: extend `PracticeSessionViewModelTests` with `testPromptExposesClassificationLabelNotOnlyGlyph` and `testThemeHintExposesGlossForEnPrise`, driving whatever view-model-level accessors the view will read so the text is testable without a view.

Green: wire `ChessGlossary` into the prompt and feedback, and implement DD6's reserved hint space.

Gate: the same focused test command as Step 2.

### Step 6 - Inline practice mode

The largest step.
Take it in this order so the app compiles at each substep.

1. Add `PracticeSessionView`'s content as a right-pane mode and a board-source seam, without deleting the sheet yet.
2. Switch `GameReplayView` to drive `boardColumn` from the practice view model while in practice mode.
3. Delete the `.sheet` from `GameReplayView.movesReportColumn`, and delete `.frame(minWidth: 760, minHeight: 560)` and `.frame(width: 420, height: 420)`.
4. Replace `DashboardView.nextLesson`'s nested `.sheet` with a callback that dismisses the dashboard and opens the game in practice mode via `ContentView`.

Red: extend `GameReplayViewModelTrainingTests` with `testEnteringPracticeModeSuspendsLiveAnalysis` and `testExitingPracticeModeRestoresReportTab`.
Live engine analysis follows the displayed ply, and during practice the displayed position is not a ply of this game, so it must not keep running against a position the practice board is not showing.

Green: implement.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS'`, the full suite.
Baseline is 55 tests in 15 suites; this phase adds suites, so the count must go up and nothing may regress.

### Step 7 - Full verification

Run every gate in the standard set:

```
swift test --package-path Packages/ChessCore
swift test --package-path Packages/AnalysisKit
swift test --package-path Packages/CoachKit
swift test --package-path Packages/EngineKit
swift test --package-path Packages/ChessComKit
swift test --package-path Packages/Persistence
swift run --package-path Packages/EngineKit engine-smoke
swift run --package-path Packages/CoachKit coach-grounding
xcodebuild test -scheme Chessanto -destination 'platform=macOS'
scripts/release-build.sh
git diff --check
```

`coach-grounding` must still pass even though this phase changes no Coach code, because it is the release-safety gate.
No schema migration is added in this phase, so `Packages/Persistence` should be unchanged; if it is not, stop and work out why.

## Native E2E reproduction and acceptance

### Database safety, mandatory

Never run native QA against the live database.

```
LIVE="$HOME/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite"
STAMP=$(date +%Y%m%d-%H%M%S)
cp "$LIVE" "$LIVE.before-uiux-phase1-$STAMP"
md5 -q "$LIVE" > /tmp/chessanto-live-md5-before.txt
QA="$HOME/Library/Containers/com.chessanto.app/Data/tmp/uiux-phase1-$STAMP"
mkdir -p "$QA"
cp "$LIVE" "$QA/chessanto.sqlite"
```

The QA copy must live inside the app's own container, because the app is sandboxed and cannot open a path outside it.

Launch with both opt-in variables set:

```
open -n "<Release>/Chessanto.app" \
  --env CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1 \
  --env CHESSANTO_DATABASE_PATH="$QA/chessanto.sqlite"
```

At the end of the session, confirm the live database is byte-identical:

```
md5 -q "$LIVE"
```

It must equal the recorded before value.
Record both the backup path and the QA path in the devlog, as prior sessions did.

### Fixture

Use game 9, `adamzainuri vs WillisLiao`, in the existing QA snapshot.
It is analyzed, the configured username `WillisLiao` played Black so the board defaults to the user's pieces at the top, and it owns four training cards including card id 6, whose explanation is the user's verbatim `Better was O-O (O-O Nd3 Qe7+ Be2 Nxh1 Nxc5)` example.
Its first practice card is gameId 9 sourcePly 8, whose best move is `Nb8`, playable as `c6` then `b8`.

### Tooling notes learned live

- `scripts/axprobe.swift` reads real text through `AXDescription`; the System Events AppleScript bridge does not.
- `scripts/axclick.swift` needs `--last` when a match string could collide, for example `Analyze` inside `Analyzed`.
- `scripts/axclickat.swift`'s raw coordinate clicks were unreliable for at least one toolbar button in the phase-2 session, though a plain `CGEvent` click at a computed board square worked reliably in this planning session.
- The app must be frontmost for real clicks to land, and sheets do not render at all while backgrounded.
- When computing board square coordinates, remember the board is drawn flipped whenever the card's side to move is Black, so file order runs `h` to `a` left to right.

### Acceptance scenarios

- **E2E-1, inline practice.**
  Open game 9, open Report, press `Practice key moments`.
  Assert via `axprobe` that no `AXSheet` exists.
  Assert the board is materially larger than 420pt and that it grows when the window is widened.
  Confirm the step controls, eval graph, and lines panel are hidden and the flip button remains.
- **E2E-2, key-moment hit target.**
  With the board at the start position, click the summary prose of a key moment, well below its header line.
  The board must jump to that ply.
  Repeat at the far right edge of the header line, which already worked before the fix and must not regress.
  Then click the nested `Practice` button and confirm it still opens that single moment rather than jumping the board.
- **E2E-3, player labels.**
  With game 9 open, confirm both strips render adjacent to the board, that `WillisLiao` is marked as the user's side, and that pressing flip swaps which name is on top.
- **E2E-4, hint clarity and stability.**
  In practice, press `Hint` twice from the same screen point without recomputing coordinates.
  Both presses must register, proving DD6.
  Confirm the first hint shows the term and its gloss, and the second highlights the named square on the board.
- **E2E-5, plain language on a correct answer.**
  Play `c6` to `b8`.
  Read the feedback with `axprobe` and confirm the classification is stated in words, not only as `?!`.
- **E2E-6, dashboard entry point.**
  Open Progress, press `Review next lesson`, and confirm practice opens inline with no nested sheet.
- **E2E-7, no data loss.**
  Confirm the QA copy recorded the attempt and the live database md5 is unchanged.

Capture a screenshot for each scenario with `scripts/capture-window.swift` and reference the paths in the devlog.

## Documentation, commit, and push

- Update the top of `handoffs/HANDOFF.md` with a `UI/UX clarity phase 1 complete` section, following the shape of the existing `V1 hardening phase 2 complete` section.
- Append a dated section to `devlogs/2026-07-19.md`, or to the current date's devlog if the session runs later, recording the live evidence, the two corrections this plan already carries, and any new one found during implementation.
- Write `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-2.md` forward from the stub, expanding it with anything learned that phase 2 needs.
- Commit and push the docs alongside the code, in the same commit or an adjacent one, so they survive across machines.
- Do not modify `CHANGELOG.md` or any generated file.
- Do not add an agent co-author to the commit.
- One full sentence per physical line in Markdown, and never the em dash character.

## Final checklist

Confirm each line honestly.
Do not claim a deferred item.

- [ ] Practice runs inline on the full-size board and no `AXSheet` is involved, from both the Report and the Dashboard entry points.
- [ ] The fixed 420pt board and the 760x560 sheet minimum are deleted, not merely enlarged.
- [ ] The training-card model, the scheduler, and the Progress queue are functionally unchanged, and no migration was added.
- [ ] Clicking anywhere in a key-moment block jumps the board, verified natively, not by reading source.
- [ ] The nested `Practice` button still works independently.
- [ ] Player identity strips render adjacent to the board and swap correctly on flip.
- [ ] Jargon keeps its real term and gains a plain-language gloss; no term was replaced.
- [ ] The hint square is highlighted with its own board token, not by overloading last-move, selected, or destination.
- [ ] Hint presses do not displace the controls.
- [ ] Full app suite, all package suites, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` all pass.
- [ ] The live database md5 is unchanged from the pre-session value.
- [ ] NOT DONE and not claimed: playable variations on the board (phase 2).
- [ ] NOT DONE and not claimed: Coach text density and any `CoachPrompt` change (phase 2).
- [ ] NOT DONE and not claimed: sidebar select, delete, pin, favorite (phase 3).
- [ ] NOT DONE and not claimed: the richer player dashboard (phase 3).
- [ ] NOT DONE and not claimed: chess.com identity confirmation in onboarding (phase 3).
- [ ] NOT DONE and not claimed: the remaining V1 hardening phase 3 backlog.

## Suggested skills

- `ui-ux-pro-max` together with `frontend-design` for every step that touches visual or interaction design, which here means Steps 2 through 6.
  This pairing is a standing repository rule for any substantial UI/UX change, not a suggestion.
- `diagnosing-bugs` before changing anything this plan calls broken, and specifically before Step 3.
  This plan already contains one case where a confident source-reading diagnosis was wrong.
- `tdd` for Steps 1, 2, 4, 5, and the view-model parts of 6.
- `codebase-design` for Step 6's seam between the replay board and the practice board.
- `mattpocock-skills:code-review` before the final commit, with this document as the spec axis.
