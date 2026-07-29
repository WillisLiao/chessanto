# Next session - analysis correctness, flow, and teaching depth

Bootstrap document for unstarted work.
Produced by the 2026-07-30 player-lens review session, which read the codebase and ran the Release build but changed no code.

Read this together with `handoffs/HANDOFF.md`.

**Status: Priority 1 is implemented (2026-07-30), except P1.6 (`brilliant`).**
Priorities 2 through 5 are still unstarted and remain the plan.

Two items in Priority 1 were disproved while being implemented, and this document is superseded on those two points only.
See `handoffs/HANDOFF.md` and `devlogs/2026-07-30.md` for the corrections:

- P1.3's "already-decided positions" half is wrong. Moves in an already-mated position grade `.excellent`, not `.blunder`, because the mover's win probability is pinned at 0 and the drop is therefore 0. Only the forced-move half was a real defect.
- P1.1's implementation notes describe a delivery race between the final `info` line and the terminating `bestmove`. There is no such race: the line is never emitted at all, and the ±1 ply is inherent to Stockfish under MultiPV.

The rest of this document stands as written.

## What this session did

Reviewed the whole product twice, once as an intermediate 1800-rated club player and once as a 300 to 600 rated beginner.
Scope covered flow, UI, UX, chess theory, teaching method, analysis correctness, learning science, and attention design.

Method was code reading across `Packages/AnalysisKit`, `Packages/CoachKit`, `App/Sources/Chessanto`, plus a launch of the Release build at
`~/Library/Developer/Xcode/DerivedData/Chessanto-dvybgihmaxaffpbutfmycvjeqlkn/Build/Products/Release/Chessanto.app`
and inspection of the committed QA screenshots under `handoffs/screenshots/`.

Sandboxed screen capture was refused by the OS in this environment, so live screenshots could not be taken.
Visual findings below are grounded in `handoffs/screenshots/baseline/04-magnus-report.png` and `handoffs/screenshots/step11-coach-open.png`, which predate the 2026-07-19 comic Coach and notation work.
Any visual finding marked as needing re-verification should be re-checked against a current build.

The live database was backed up before launch and verified byte-identical afterward at SHA-256 `e9947babbf767d66d5164d28b86af9c843f6973231b0351bb82e84d5921b027b`.

## What is already strong and must not be regressed

The grounding architecture is the product's real moat.
`CoachVerifier` replaying every cited line through `ChessGame`, with a single fresh-verification hook to the engine, is something no mainstream chess app does.

The typed fact pipeline is clean.
`ReportInput` to `Fact` structs to `FactAuditor` to `ReportText` templates means every user-visible chess claim traces to a stored evaluation, and `ThemeDetector` never composes prose.

Win probability rather than raw centipawns is the correct classification currency, and the FEN-guard discipline that refuses stale evaluations unless `live.fen == currentFEN` is correct paranoia worth preserving.

The analysis board is complete for study: free variation play off any ply, persisted variations rendered inline in the scoresheet, MultiPV lines adoptable as branches, and DB-free line playback via `LinePreviewController`.

## Priority 1 - analysis correctness

Everything the app teaches is downstream of these numbers.
None of the later priorities are worth doing before these land.

### P1.1 Fixed depth instead of movetime

`App/Sources/Chessanto/Analysis/EngineService.swift:21-27` sets `fast = 100ms`, `standard = 350ms`, `deep = 2000ms`.

Standard is 350 milliseconds per position.
The classification thresholds distinguish a 9-point win-probability drop from an 11-point one, and at 350ms the evaluation noise between consecutive plies in a sharp middlegame exceeds that.
The app will manufacture inaccuracies and mistakes that do not exist.

Movetime is also not reproducible.
Re-analyzing the same game on a busy machine yields different classifications, different key moments, and therefore different practice cards, so `TrainingCardReconciler` churns the spaced-repetition queue on every re-analysis.

Change to fixed depth targets with a movetime ceiling as a safety valve.
Suggested starting point is fast at depth 14, standard at depth 18, deep at depth 22, against Lichess server analysis at roughly depth 20.
Surface the depth in the UI so `Analyzed · Standard` becomes `Analyzed · depth 18`.

### P1.2 Book move exemption

`ReportBuilder.buildOpeningFact` already computes `match.deepestBookPly` from the bundled ECO book.
`MoveClassifier.classify` never receives it, so theory moves are graded.

Add a `.book` classification for plies at or before the deepest book ply.
Exclude book plies from accuracy aggregation and from key-moment candidacy.

### P1.3 Forced moves and already-decided positions

Two related holes in `Packages/AnalysisKit/Sources/AnalysisKit/MoveClassifier.swift`.

A forced recapture, or a position with exactly one legal move, is graded on its win-probability drop like any other move.

`WinProbability.fromMate` returns a hard 0 or 100.
Once the opponent has a forced mate, every subsequent move registers a 100-point drop and classifies as a blunder.
A game lost on move 22 produces a report full of blunders on moves 23 through 40 that changed nothing.

Add a neutral classification for forced moves.
Suppress mistake and blunder credit when the mover's pre-move win probability is already below roughly 5 percent, or when the position is already mate-decided.
Exclude both from accuracy.

### P1.4 Accuracy aggregation

`Packages/AnalysisKit/Sources/AnalysisKit/Accuracy.swift:12` takes a plain arithmetic mean of per-move accuracies.

`Accuracy.perMove` is the Lichess per-move formula, but Lichess deliberately does not aggregate it arithmetically.
It uses a volatility-weighted window mean combined with a harmonic mean, precisely because the arithmetic mean over-rewards long quiet games and under-rewards short sharp ones.

The number shown here is therefore not comparable to the number the same user sees on Lichess or chess.com, and users will compare.
Either implement the weighted and harmonic combination, or rename the metric to something the app owns.

### P1.5 Punishment false positives

`ThemeDetector.punishment` fires whenever the post-move rank-1 principal variation's first move is a capture.
A normal recapture in an even trade triggers it.

`netMaterialGainForOpponent` only modulates the wording.
With a gain of zero the user still sees `This also left the pawn on d5 hanging: exd5.` for an ordinary pawn trade.

That false fact then propagates into `TrainingCardFactory.themes` as "Material left en prise", into `PlayerInsightBuilder` motifs as "Loose pieces", into the `buildTakeaways` rule that fires on two or more punishments, and into the Player Brief's "Current finding".
A systematic false positive becomes the user's self-image.

Gate the fact's existence on real material gain, ideally a static exchange evaluation, not just the clause wording.

### P1.6 Implement or remove `brilliant`

`MoveClassification.brilliant` has a color, a compact `!!` mark, a glossary entry, and a `CoachStageText` headline.
Nothing ever assigns it.
The source comment at `MoveClassification.swift:4` still says it is reserved for M5 theme detection.

Either implement sacrifice detection (material given up, position still winning, not a forced recapture) or remove it from the chip set.
See P4.4 for why implementing it matters more than it looks.

### P1.7 Key moments should be the user's own side first

`KeyMomentSelector.selectPlies` has no side filter, so the 8-slot register mixes both players.
`TrainingCardFactory` filters to the user's side afterward at `TrainingDomain.swift:132`, which is why the register can show eight moments while Practice offers three cards with no explanation.

Select the user's side first, then offer opponent moments in a collapsed secondary section.

## Priority 2 - flow

The product's most valuable surfaces are locked behind work the product never offers to do.

### P2.1 Batch analysis

Player Brief, the accuracy trend, motif evidence, and the review queue all require many analyzed games.
Analysis is manual, one game at a time, via a button in the right pane of `GameReplayView.analysisControls`.
There is no batch action, no analyze-on-import, and no queue.

Add batch analysis and an analyze-on-import option, offered directly after a chess.com fetch.

### P2.2 Onboarding must end in an analyzed game

`OnboardingView` runs Welcome, then chess.com username, then teaching level, then Ollama setup.
Page four asks a brand-new user to understand local model hosting and RAM tiers.

The user then lands on an empty window reading "No games in the register" with a single "Import PGN…" button, despite having just confirmed a chess.com username that leads nowhere.
They must find "Add game" at the bottom of the sidebar, open a menu, and pick "Fetch from chess.com…".

Target flow: confirm username, fetch the last ten games, analyze the most recent, open its Review.
Bundle a sample annotated game so a zero-import user still has something to look at.

### P2.3 Land on Review, not Moves

`GameReplayView` defaults `rightPaneTab` to `.moves`.
For a game-review app, the review should be the destination.

When unanalyzed, the Report tab currently reads "Analyze this game (see the Analyze button above the board)", which points at a button instead of being one.

### P2.4 Unlock Player Brief for PGN-only users

`PlayerBriefView.content` hard-gates the entire surface behind `library.isChessComAccountConfirmed`.
A PGN-only user, explicitly supported per the README, can never see their own progress.

Replace the gate with a "which player are you" picker over the names present in the imported PGNs.

### P2.5 Coach entry points

Three ways in with two invisible behaviors: the pane-header toggle follows the board, "Ask Coach" in the board controls pins to the current ply, and the move-row context menu pins to that ply.
Nothing in the UI shows which mode is active except a small "Asking about the current position" line.

### P2.6 Keyboard and window

Only left and right arrows plus Escape are bound, and `.focusable()` on the detail pane means the arrows stop working the moment the sidebar is clicked.
Missing: up and down to jump between key moments, `f` to flip, space to pause a line preview, and a shortcut to analyze.

Minimum window is 1200 by 680 and the Coach column only docks above 1100 points of content width, so on a 13-inch MacBook Air the Coach is always an overlay covering the moves list.

Light mode is hard-pinned at `ChessantoApp.swift:16` plus `.preferredColorScheme(.light)`.
This was a deliberate 2026-07-18 user decision, so it is listed as a question rather than a defect, but it is worth revisiting for evening use and for accessibility.

## Priority 3 - the board

This is the surface users physically touch, and it is where a beginner will conclude the app is broken.

### P3.1 Drag and drop

`BoardView` is tap-source then tap-destination only, via `onSquareTapped`.
A user will try to drag a piece, nothing will happen, and they will assume the board does not work.
This is the most urgent single UI fix in the app.

### P3.2 Promotion

`GameReplayViewModel.playMove(from:to:promotion:)` defaults to `.queen` with no picker anywhere, so underpromotion is impossible on the exploration board.

More seriously, `PracticeSessionViewModel.select` builds a four-character UCI string such as `e7e8` and grades it against a card whose `bestMoveUCI` is five characters such as `e7e8q`.
The cached-line match at `TrainingDomain.swift:320` can therefore never hit, and `ChessGame.replayLine` is likely to reject the move outright.

A promotion practice card is probably ungradeable.
Reproduce this directly before fixing, per the repository's bug-fix rule.

### P3.3 Missing board affordances

No piece animation, so pieces teleport between squares and the user cannot see what moved when stepping through a game.
No move or capture sounds.
No right-click arrows or circles, which is the primary tool for thinking about a position.
Coordinate glyphs are drawn in-square at 16 percent of square size, which is small for a learner still internalizing the coordinate system.

## Priority 4 - teaching depth

This is where the product either becomes a coach or stays an offline analysis board.

### P4.1 Make the teaching level do real work

`RatingRegister` at `CoachPayloadBuilder.swift:58-78` resolves to one of three strings and injects a single sentence into the LLM system prompt.
That is its entire effect.

A 400 and a 2000 currently receive the same classification thresholds, the same eight key moments, the same six-ply principal variations, the same practice cards, and the same grading strictness.

A beginner register should mean: two or three moments rather than eight, only moments with a concrete nameable consequence such as material lost or mate missed, one-move better lines, material-denominated explanations, and looser practice grading.
None of that requires new analysis.
It is filtering and rendering over facts already computed.

### P4.2 Add the detectors that explain real games

The entire explanatory vocabulary is four fact types: eval swing, better move, punishment capture, and missed or allowed mate.

Missing and high value, all reachable by board replay over positions already stored:

- A piece was already hanging before this move and was not saved.
- The opponent had a threat and the played move failed to address it. This is the single most common cause of a loss below 600 and is completely absent.
- Forks, pins, skewers, discovered attacks, back rank, and trapped pieces.
- Whether the played move was a capture or a check, whether it moved an already-developed piece again, whether the same piece moved twice before castling, and whether the queen came out before move five.

`[%clk]` comments are already parsed from chess.com PGNs per the M1 and M2 records and are never used.
Time per move correlated with error rate is one of the highest-value insights available to a club player.

### P4.3 Takeaways almost always say nothing

`ReportBuilder.buildTakeaways` has four rules: two or more punishments for one player, a missed mate, an allowed mate, and a book deviation followed by a bad evaluation.
When none fires the fallback is "No single recurring pattern stood out - see the key moments above for specifics", which is the app admitting it has nothing to teach.

That will be the common outcome, because the rules that fire are the rare ones.
The most instructive thing in a game below 600 is almost never a missed mate in four.

### P4.4 Positive reinforcement

The only place the app notices the user did something right is `firstAttemptSuccesses` on the practice completion card.
`.best` is a small star among forty other moves.

The unimplemented `brilliant` matters most here.
The `!!` moment is a primary reason players keep analyzing their games elsewhere, and the color, glyph, glossary entry, and coach headline are all already written.

### P4.5 Practice trains recognition, not calculation

`PracticeSessionViewModel.select` submits on the first legal move and grades it.
The learner never sees the opponent's reply and never plays the follow-up, which is where the difficulty actually lies.

Make cards multi-ply: play the best move, let the engine reply, continue until the point is made.

The hint ladder is theme name then origin square.
Hint one only exists if a theme fired, otherwise it is the generic "Look for the forcing idea."
Neither hint teaches a method, and the missing first hint is "What is your opponent threatening?"

Wrong-answer feedback reads "That move misses the point of the position. Reset and try to find Qe7" and never says what the point was.

### P4.6 Spaced repetition

`DeterministicReviewScheduler` sets an incorrect answer to `dueAt = now`, so the card reappears in the same session seconds after the answer was shown.
That trains recognition, not recall.

Intervals are 1, 3, 7, then 14 days and then mastered.
There is no ease factor, no lapse count, and no interleaving across games.
Cards are per-position rather than per-pattern, so mastering one position transfers nothing.

There is also no way to drill a theme across games, even though the Player Brief diagnoses exactly that ("Loose pieces, 4 of 6 games") and offers only the due queue as an action.

### P4.7 Beginner vocabulary

Win probability is the wrong currency below 600.
"Drops winning chances from 45% to 35%" means nothing to a player who does not know what a winning chance is.
Material is the currency they understand, and `PunishmentFact.netMaterialGainForOpponent` already holds the number.

`ThemeDetector.betterMove` takes `prefix(6)` and `ReportText.betterMoveSentence` renders the whole line, producing six-ply variations nobody at that level can hold.

"Engine loss: 140 centipawns" appears in `PracticeContentView.swift:140`.

The eval graph hover readout says "Ply 27" where a learner counts moves.

`ChessGlossary` has five entries, two of which share an identical gloss, and nothing in the UI links a term to its explanation.

### P4.8 Decide what the LLM Coach is for

From `handoffs/screenshots/step11-coach-open.png`, asked "How should White continue here?", the Coach answered with three tautologies ("e4 is a classic opening move for White, and it's a good choice to continue the game"), repeated the identical answer verbatim for the identical question, and ended with "Let me check the evaluation to see which of these options is the best" without checking.

The verifier passed it because the moves are legal and no evaluation was claimed.
This is the structural limit of the current design: it proves nothing false was said, and does nothing to ensure something useful was said.

`CoachModelCatalog` defaults to `qwen3:4b` under 16GB, which is far too weak for chess reasoning, so this is the default experience for most users.

Recommended direction, in order of preference:

1. Make the Coach a structured explainer over the app's own facts and use the LLM for phrasing only. The facts are better than a 4B model's reasoning.
2. Enforce concreteness in the verifier. `CoachPrompt.chatSystemPrompt` already instructs the model to call the `evaluate` tool before answering an open-ended question. Make that a hard gate so an answer citing no verified line is a violation and regenerates.
3. Raise the model floor and state plainly that below 8B the Coach is disabled.

## Priority 5 - smaller UI details

Re-verify each against a current build before acting, since the grounding screenshots predate the 2026-07-19 work.

Classification chips wrapped mid-word in the shipped screenshot as "Excellen t", "Bes t", and "Inacc uracy".
The `LazyVGrid` with `.adaptive(minimum: 58)` in `GameReportView.classificationRow` is the intended fix, but 58 points is likely still too narrow for "Inaccuracy" at `.dsSecondary` semibold, and `ClassificationChip` sets no `lineLimit` or `fixedSize`.

Six classification marks are shown with no legend anywhere: star, thumbs-up, checkmark, `?!`, `?`, `??`, `!!`, and a purple `xmark` for missed win.

`accuracySummary` renders "White 93.8 · Black 90.8" with no percent sign and no indication which player is the user, even though `BoardIdentityStrip` already resolves the username.

`LinesPanelView` truncates every principal variation to one line with `.truncationMode(.tail)` in a 260 to 340 point column, and clicking a line immediately adopts it as a variation, which is a destructive-feeling action from what reads as an information row.

Eval graph key moments are 6-point dots with no independent hit target, so a blunder marker cannot be clicked directly.

The eval bar is scaled by win probability while its label shows centipawns, and nothing explains the mismatch.

Sidebar rows fall back to raw "1-0" when no chess.com username is set, which a learner reads as a score rather than a result.

`PlayerBriefView.reviewAction` shows a disabled "Practice positions" button with no tooltip when no cards exist.

## Open questions for the user

1. Is the light-only appearance decision from 2026-07-18 still fixed, or is dark mode now in scope?
2. Should the forensic register ("Game register", "Key-moment register", "Current finding") stay as the app's voice for advanced users while the beginner register gets plainer language, or should the whole voice change?
3. Is the LLM Coach worth keeping as free-form chat, or should it become a structured explainer over the existing facts?
4. Should key moments default to the user's side only, with opponent moments behind a toggle?
