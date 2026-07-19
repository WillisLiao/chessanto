# UI/UX clarity phase 2 - implementation record

Phase 2 was implemented on 2026-07-19.
This document remains the record of the original investigation and locked persistence boundaries.

The user made two explicit presentation decisions during implementation that supersede the earlier plan:

- Verified better lines autoplay in both Report and Practice, while retaining pause, replay, previous, next, start, end, and Done controls.
- Dense narration is no longer laid out as sentence fragments in the narrow Report column.
  A comic Coach now stands beside the board with a concise speech bubble synchronized to the demonstrated moves.

The underlying safety decisions did not change.
Line playback remains DB-free and does not call `adoptLine`.
The actual played continuation remains Report-only because Practice cards do not carry the loaded mainline game.
No Coach verifier or grounding rule was weakened.

This is a self-contained execution plan for one Claude Sonnet medium session.
Every source claim below was reproduced live during the planning session on 2026-07-19, either by reading the current file directly (quoted with its path) or by querying a read-only copy of the real production database.
Where the original scoping stub made a claim that this session's verification corrected, the correction is recorded explicitly rather than silently carried forward.

This planning session did not rebuild the Release app or drive it with `axprobe`/`capture-window`, unlike the phase 1 planning session.
That was a deliberate scope call, not an oversight: phase 1's planning work was bug diagnosis, where several claims about existing broken behavior turned out to be wrong under live testing (see phase 1's D4).
Phase 2's Item A is new-feature construction with no existing behavior to misdiagnose, and Item B's live evidence (the actual dense Coach and rule-based text) was already captured live in the phase 1 planning session against the same fixture and is still current, because no code on that path has changed since.
The execution session must still do real native E2E per the acceptance section below; this plan only asserts what it directly verified.

## Starting point

The expected tip is `de2a2b7` "UI/UX clarity phase 1: inline practice, plain language, real hit targets".
Confirm `main` is clean and synchronized with `origin/main` before starting.

Baseline test counts as of this tip, from the phase 1 devlog: app suite 70 tests / 17 suites, `ChessCore` 21, `AnalysisKit` 63, `CoachKit` 74, `EngineKit` 1, `ChessComKit` 3, `Persistence` 29.
This phase adds tests; the count must go up and nothing may regress.

This checkout has no physical `AGENTS.md` and no project-level `CLAUDE.md`, same as phase 1.
Do not create either to satisfy an instruction that references it.

## What phase 1 actually built, carried forward from its own handoff note

- `PracticeContentView.swift` (right pane: prompt, hints, feedback, session progress) and `PracticeBoardSection.swift` (board half, `@ObservedObject`-driven from `PracticeSessionViewModel`) are the two halves of inline practice.
- `GameReplayView.RightPaneTab` has `case practice`, entered only via `openPractice(sourcePly:)` / `openPractice(loadCards:)`. `boardColumn` and `movesReportColumn` both branch on `rightPaneTab == .practice`.
- `PracticeSessionViewModel.flipped` is `isManuallyFlipped != (currentCard?.sideToMove == .black)`, with a `toggleFlip()` the flip button calls. Any new board-driving state on this view model should follow the same "derived value, one override toggle" shape rather than adding a second orientation source.
- `ChessGlossary` (`App/Sources/Chessanto/Training/ChessGlossary.swift`) is a pure lookup, `gloss(for: String) -> String?` and `gloss(for: MoveClassification) -> String`, seeded with `en prise`, `hanging`, `forced mate`, `O-O`, `O-O-O`, and the eight `MoveClassification` cases. Still exactly this seed set, reconfirmed by reading the file this session.
- `PracticeSessionViewModel.themeHintTextIgnoringHintCount` established the pattern for reserving layout space: always render the final, real content and gate visibility by opacity, never swap between a placeholder and the real string. Reuse this pattern for anything phase 2 adds that changes length.
- `BoardIdentityStrip`/`BoardIdentityStripView` render name/rating strips above and below the board, bound to screen position not color, reused unmodified by both `boardColumn`'s two branches. Practice's `PracticeBoardSection` already threads `identityStrips` through as a constructor parameter.

## Verified diagnosis

### Item A - playable variations

**A1. The "better line" data is already present in full, unbounded length, on both Practice and Report's in-memory models. No new fetch is needed.**

Confirmed live against a read-only copy of the real production database (`chessanto.sqlite`, copied out of the sandboxed container, never written to; its md5 was unchanged by this session):

```
trainingCard id=6, gameId=9, sourcePly=14
explanation: "7... Qf6 drops your winning chances from 65% to 21%.
  Better was O-O (O-O Nd3 Qe7+ Be2 Nxh1 Nxc5), keeping the evaluation around -1.6.
  This left it where it could be taken: Qxf6."
rankedLinesJSON, rank 1: 15-ply principalVariationUCI
  (e8g8 e5d3 d8e7 f1e2 f2h1 d3c5 e7c5 c1e3 c5b4 b1d2 b4h4 g2g3 h4h2 e1c1 h1g3)
```

The explanation's parenthetical shows only 6 SANs (`O-O Nd3 Qe7+ Be2 Nxh1 Nxc5`) while the persisted rank-1 line is 15 plies deep.
This confirms the original scoping stub's claim exactly, on live current data, not a stale snapshot.

- `TrainingCard.rankedLines: [RankedLine]` (`App/Sources/Chessanto/Training/TrainingDomain.swift:39`) already holds every ranked line in full on the in-memory practice card, decoded from `rankedLinesJSON` at load time. `TrainingCard.bestMoveUCI` only reads `.first` of the top-ranked line's PV; nothing about the model prevents reading the whole array.
- On the Report side, `GameReplayViewModel.reportInput: ReportInput?` (`App/Sources/Chessanto/GameReplayViewModel.swift:60`, `private(set)`, already publicly readable) exposes `ReportInput.plies: [PlyRecord]`, and `PlyRecord.lines: [RankedLine]` carries the same unbounded `principalVariationUCI`. For a `KeyMoment` at `moment.ply`, the pre-move record is `reportInput.plies[moment.ply - 1]` (`ReportInput.plies[p]` is defined as "the position after mainline move p", so the position *before* move `moment.ply` is index `moment.ply - 1`).
- `BetterMoveFact.lineSANs` (`Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift:27`) is explicitly capped: "Up to 6 plies of the engine's PV". This is the fact used to build the prose sentence, and it is deliberately short for prose; it is not a source-of-record limitation, and the preview must not read from it.

**A2. Correction to the stub: "the actual bad continuation that was played" is not `PunishmentFact`.**

The original stub's own text is ambiguous enough that a future session could reasonably reach for `moment.punishment?.refutingSAN` as "the actual continuation" - it is adjacent, single-move, and already rendered as "`refutingSAN` punishes this" in the report text.
Reading `PunishmentFact`'s doc comment (`Facts.swift:34`) settles it: punishment "fires when the rank-1 PV of the post-move position starts with a capture" - it is the engine's own recommended reply to the mistake, not a record of what the opponent actually played.
In a real game the opponent frequently does not find the punishing move at all, which is itself something a learner benefits from seeing ("they didn't even take it").

The real "actual played continuation" is the mainline of the game itself, from `moment.ply` onward, which is not stored as a fact at all - it is derivable on demand from `GameRecord.pgn`, already loaded into `GameReplayViewModel`'s private `chessGame`, via the existing `moveIndices` array and `ChessGame.uciMove(at:)`/`moveDetail(at:)`.
This is Report-only data. `TrainingCard` (Practice's model) carries `gameId` and `sourcePly` but no loaded `ChessGame`, and there is no reason to give it one just for this - see DD-A4.

**A3. The seam: `ChessGame.replayLine(fromUCI:startingFEN:) -> [ReplayedMove]` is the exact primitive needed, and it already exists, pure, with no persistence.**

`Packages/ChessCore/Sources/ChessCore/ChessGame.swift:288`. Given a starting FEN and a UCI move list, it returns one `ReplayedMove` per move (`san`, `uci`, `movedPieceKind/Color`, `capturedPieceKind`, `isCheck`, `isCheckmate`, `endSquare`, `resultingFEN`), stopping cleanly at the first move that fails to parse or play, with zero dependency on `GameStore`, `MoveTree`, or any persisted state.
`CoachVerifier` already uses this exact function to replay cited lines for verification (`CoachVerifier.swift:115`), so its behavior under adversarial/short input is already exercised in production code.

**A4. Confirmed anti-pattern: `GameReplayViewModel.adoptLine(sanMoves:)` always writes to the `variation` table, and must not be reused.**

`App/Sources/Chessanto/GameReplayViewModel.swift:535-544`. `adoptLine` calls `recordVariationMove` for every move played, which calls `store.insertVariationMove(...)` (`GameReplayViewModel.swift:560`) unconditionally unless the move happens to already match an existing mainline/variation node.
This is exactly right for its actual caller - `LinesPanelView`'s "adopt this line" button, where the user is deliberately authoring a new explored branch - and exactly wrong for a preview, where the learner is only watching.
A naive implementation that called `adoptLine` (or wrote a parallel version of `recordVariationMove`) to drive a preview would silently create persisted `variation` rows for every line reveal, cluttering `MoveListView`'s variation tree with rows the learner never asked to create and never sees a delete control for outside the moves list.
This confirms the original stub's instinct was correct, with a concrete mechanism now identified.

### Item B - Coach text density

**B1. `card.explanation` (Practice's `.strong`-outcome feedback text) and the Report's rule-based fallback text are the same underlying string, generated by the same function.**

`TrainingDomain.swift:377`: `explanation = card.explanation ?? "..."` feeds `PracticeContentView.feedbackView`'s `Text(feedback.explanation)` directly whenever the learner answers correctly.
`card.explanation` is populated at analysis time by `TrainingCardFactory.drafts` from `ReportText.momentSummary(_:report:)` (confirmed live in the phase 1 planning session and unchanged this session).
`ReportText.momentSummary` and the Report's own rule-based fallback path both bottom out in `ReportText.momentLines` (`Packages/AnalysisKit/Sources/AnalysisKit/ReportText.swift:81`), which builds one single concatenated string (`"- \(text)"`) by string-appending the eval-swing sentence, the better-move sentence, the punishment sentence, and any mate sentence, with a plain space between each.

This means: a fix to how this text renders benefits Practice's post-answer feedback and the Report's key-moment fallback simultaneously, for free, provided the fix is a *rendering-layer* change and not a change to what `ReportText.momentLines` persists into `card.explanation` (which is baked at analysis time and would require a migration or a re-derive-on-read step to change retroactively - out of scope, and unnecessary, since DD-B1 below is rendering-only).
The Coach LLM narration (`CoachNarration.text`, rendered only in `GameReportView.narrationView` and the Coach chat panel) is a separate, Report-only surface and is not persisted into `trainingCard`.

**B2. Re-confirmed grounding-rule mechanics: `CoachVerifier` checks the numeric claim itself, not the parenthetical formatting.**

Read `Packages/CoachKit/Sources/CoachKit/CoachVerifier.swift:284-324` (`numericClaimViolations`). It scans the *whole response text* for eval-shaped (`+0.5`), mate-shaped (`M3`, `mate in 3`), and percent-shaped (`41%`) substrings via regex and checks each against `context.knownEvalsCentipawns`/`knownMates`/`knownWinProbabilities`, wherever in the text they appear.
It does not require the number to sit inside literal parentheses immediately after a cited move - that convention lives only in `CoachPrompt.groundingRules`'s instruction to the model, as a way to keep responses habitably formatted, not as something the verifier mechanically enforces.

This matters for Item B: a rendering-side change (splitting the narration into visually separate lines, e.g. one per sentence) cannot break grounding, because the verifier already ran once, on the model's raw output string, before any rendering happens - re-formatting the *display* of an already-verified string changes nothing the verifier checks.
The stub's hard constraint - "the grounding guarantee must not weaken" - is honored by construction as long as no change touches `CoachVerifier`, `CoachPrompt`'s actual rules, or the raw `narration.text` string itself, only how it is laid out on screen.
The stub's caution about prompt changes needing re-verification still applies in full if `CoachPrompt`'s wording changes (see DD-B2); it does not apply to the pure rendering fix, which is why that fix is prioritized first and is lower-risk.

**B3. Live text, reconfirmed present at the source rather than re-captured from a fresh GUI run (see the note at the top of this document).**

Coach narration for game 9, model `qwen2.5-coder:3b` (phase 1 planning session, `coachEnabled=1` reconfirmed still set for `WillisLiao` in the live database this session):
`The player's mistake was to play Nxe5 instead of Qd5. This move allows the opponent to capture the pawn on f2 with their knight,` (continuing past the visible area).
Rule-based fallback, same shape as card 6's explanation above: dense, 3-4 clauses concatenated with single spaces and no visual separation.

## In scope for this phase

1. Item A: a step-through preview of the engine's better line, available from Practice (post-answer feedback) and Report (key-moment block).
2. Item A: a step-through preview of the actual game continuation from a key moment, available from Report only (see A2/DD-A4 for why Practice does not get this one).
3. Item B: a rendering-layer fix (sentence-level chunking, not truncation) applied to the Report's key-moment narration (both Coach and rule-based) and to Practice's `.strong`-outcome feedback text, since they share the same underlying string per B1.
4. Item B: a `CoachPrompt` wording tightening, applied and re-verified separately from the rendering fix, only if the rendering fix alone is judged insufficient once seen live (see DD-B2 and Step 6's gate).

## Explicitly out of scope for this phase

- Autoplay of a previewed line. DD-A2 fixes this: step-through only, user-paced.
- Any preview affordance inside the practice *prompt* (pre-answer) state. DD-A5 fixes this: previewing the answer before attempting would defeat the hint-gating phase 1 already built.
- Any change to `card.explanation`'s persisted content, or a migration to re-derive existing rows. The fix is rendering-only (B1).
- Any change to the Coach chat panel (`ChatView`) or its own prose density. Not raised by the user for this phase; the stub scoped this to the Report's key-moment blocks.
- Sidebar select, delete, pin, favorite; the richer player dashboard; chess.com identity confirmation in onboarding. Deferred to phase 3, unchanged from phase 1's handoff.
- Everything else in `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-3.md` not already absorbed by phase 1.

## Fixed design decisions

These are settled. Do not reopen them; implement them.

### DD-A1 - `LinePreviewController`: one small, deep, DB-free module; two independent owners

Add `App/Sources/Chessanto/Board/LinePreviewController.swift`:

```swift
@MainActor
final class LinePreviewController: ObservableObject {
    struct Step {
        let position: BoardPosition
        let lastMove: (from: BoardSquare, to: BoardSquare)?
    }

    let label: String
    private let steps: [Step]
    @Published private(set) var stepIndex: Int = 0

    init(label: String, startingFEN: String, uciMoves: [String]) { ... }

    var current: Step { steps[stepIndex] }
    var stepCount: Int { steps.count }
    var canStepForward: Bool { stepIndex < steps.count - 1 }
    var canStepBackward: Bool { stepIndex > 0 }
    func stepForward() { ... }
    func stepBackward() { ... }
    func jumpToStart() { stepIndex = 0 }
    func jumpToEnd() { stepIndex = steps.count - 1 }
}
```

`init` builds `steps` once, synchronously, by calling `ChessGame.replayLine(fromUCI:startingFEN:)` a single time and mapping the starting FEN plus each `ReplayedMove.resultingFEN` into a `BoardPosition` (reuse `BoardPositionMapper.position(fromFEN:)`, already used by `PracticeSessionViewModel.position`). `steps[0]` is the starting position with `lastMove == nil`; `steps[i]` for `i >= 1` derives `lastMove` by parsing `replayedMoves[i-1].uci`'s first two and second two characters into `BoardSquare`s, the same parsing `PracticeSessionViewModel.arrow(for:)` already does.

This is the whole interface: one initializer and four navigation primitives, no dependency on `GameStore`, `GameReplayViewModel`, or `PracticeSessionViewModel`. It has exactly two real adapters (Practice and Report construct it from different data sources, per A1/A2), which is what justifies it as a real seam rather than a speculative one.

`LinePreviewController` never persists anything and is discarded (`= nil`) by its owner when the learner exits preview - there is no "hand back control" method on the controller itself, because ending a preview is just discarding an optional, not a state transition the module needs to know about.

### DD-A2 - Step-through only, no autoplay

The board steps forward/backward/to start/to end on explicit user action only.
Rationale: the user's verbatim ask was "should be able to play out on the board when the user chooses to see them" - user-paced, not automatic - and every other stepping surface in this app (move list, replay controls) is already manual-step, so autoplay would be new interaction vocabulary for no requested benefit.

### DD-A3 - Preview owners: `PracticeSessionViewModel` and `GameReplayView`, never `GameReplayViewModel`

Practice: `PracticeSessionViewModel` gains `@Published private(set) var linePreview: LinePreviewController?` and two methods:

```swift
func previewBetterLine() {
    guard let card = currentCard, let best = card.rankedLines.sorted(by: { $0.rank < $1.rank }).first,
        !best.principalVariationUCI.isEmpty
    else { return }
    linePreview = LinePreviewController(label: "Better line", startingFEN: card.preMoveFEN, uciMoves: best.principalVariationUCI)
}

func endPreview() { linePreview = nil }
```

`PracticeBoardSection` branches on `viewModel.linePreview`: when set, it renders `BoardView(position: linePreview.current.position, lastMove: linePreview.current.lastMove, flipped: viewModel.flipped, theme: theme)` plus a `LinePreviewControlsView` (DD-A6) beneath the board; when nil, it renders exactly what it renders today. The existing `viewModel.position`/`selectedSquare`/`hintSquares`/`revealArrow` computed properties are untouched - the branch happens once, at the view, not by smuggling preview state into those properties.

Report: `GameReplayView` gains `@State private var linePreview: LinePreviewController?`, sitting alongside its existing `@State private var practiceViewModel`. `boardColumn`'s non-practice branch gains the same `if let linePreview { ... } else { existing EvalBar/BoardView/controls/graph/lines-panel }` shape DD1 (phase 1) already used for `rightPaneTab == .practice`. `GameReportView` gains two new callbacks, following the exact pattern its existing `onAskCoach`/`onPractice` callbacks already use:

```swift
let onPreviewBetterLine: (KeyMoment) -> Void
let onPreviewPlayedContinuation: (KeyMoment) -> Void
```

`GameReplayView` supplies closures that build the `LinePreviewController` from `viewModel.reportInput` (A1) or `viewModel.uciContinuation(fromPly:maxPlies:)` (new, small, pure - DD-A4) and assign it to `linePreview`. `GameReplayViewModel` itself never holds a `LinePreviewController` and never imports the type - it only grows one small new read-only helper method that returns `[String]`, keeping the anti-pattern in A4 structurally impossible rather than merely avoided by convention.

### DD-A4 - `GameReplayViewModel.uciContinuation(fromPly:maxPlies:)`, a small new pure read

```swift
/// UCI moves of the real game's mainline, starting the move after `ply`,
/// up to `maxPlies` of them or the end of the game, whichever is shorter.
/// Never touches the variation tree; read-only over already-loaded state.
func uciContinuation(fromPly ply: Int, maxPlies: Int = 10) -> [String] {
    guard let chessGame, ply < moveIndices.count else { return [] }
    return moveIndices[(ply + 1)...].prefix(maxPlies).compactMap { chessGame.uciMove(at: $0) }
}
```

The cap of 10 plies is a concrete decision, not a placeholder: long enough to show a mistake's consequences actually unfold in the real game, short enough that "play out what happened" stays a short preview rather than an invitation to replay the rest of the game move by move. `LinePreviewController`'s `init` naturally stops early anyway if the game ends before 10 plies (`ChessGame.replayLine` stops at the first move that fails to parse, which includes running out of moves).

### DD-A5 - No preview affordance before the learner has attempted the card

`PracticeContentView.promptControls` (the pre-answer state, Hint/Reveal buttons) gains no preview button. The "better line" preview button only appears in `feedbackView`, alongside the already-answered feedback text.
Rationale: phase 1 built a deliberate two-hint gate (`hintCount`) before revealing even the best move's origin square; a preview button visible during the prompt state would let the learner step through the full answer without spending a hint, defeating that gate. This was not asked for and is a real regression risk if the preview button is added to the wrong view state.

### DD-A6 - Preview presentation: reuse `theme.highlight`, no new arrow color, entry point matches the existing bordered-button idiom

Read `Packages/.../BoardTheme` and `BoardView.swift`'s existing highlight semantics before touching this. `theme.highlight` already means "the squares of the move that produced the position currently on screen" (the real last-move highlight). A preview step showing the position after replaying move N of a line *is* exactly that meaning - the squares of the move that produced this position - so `LinePreviewController.current.lastMove` renders through the board's existing `lastMove` parameter and `theme.highlight` token, not a new color. This does not violate DD3 (phase 1)'s "don't overload an existing token's meaning" rule, because the meaning is not being overloaded here, it is the same meaning applied to a different position source. Do not draw a persistent arrow spanning the whole line; only the current step's highlight, updating as the learner steps.

Entry point: a `Button` styled `.buttonStyle(.bordered)` with `.font(.dsSecondary.weight(.semibold))`, matching `GameReportView`'s existing `Practice` button on the key-moment row exactly (same visual family, no new button style introduced). Label text, not an icon-only control: "Play out the better line" and "Play out what happened", each with a matching `.accessibilityLabel`. Placed as described in DD-B3, next to the fragment it previews (better line) or once per key-moment block (played continuation, since no existing sentence anchors it - see A2).

Step controls (`LinePreviewControlsView`, new file in `App/Sources/Chessanto/Board/`): reuse the exact icon-button cluster idiom `GameReplayView.controls` already uses for step/jump (`backward.end.fill` / `chevron.left` / `chevron.right` / `forward.end.fill`, `.buttonStyle(.borderless)`, `surface1` pill background), so this introduces no new interaction vocabulary. Add a label row above it: `controller.label` (`"Better line"` / `"What was played"`) in `.dsSecondary`/`textSecondary`, plus a step counter (`"\(stepIndex + 1) / \(stepCount)"`) in the same style, using default (non-monospaced-digit) rendering since these are single- and double-digit counts, not a data column. A trailing "Done" button, `.buttonStyle(.bordered)`, calls the owner's exit closure - same idiom as `PracticeContentView`'s "Exit practice" button.

### DD-B1 - Sentence-level chunking at render time, applied uniformly, resolves the "no disclosure" vs "too dense" tension by choosing neither truncation nor a new disclosure affordance

Add `App/Sources/Chessanto/DesignSystem/SentenceFragments.swift`:

```swift
/// Splits already-generated prose into its sentences for line-by-line
/// display, so a dense paragraph reads as short, separated statements in a
/// narrow column instead of one dense block - a pure rendering split, never
/// applied to text before it is grounded/verified (B2), and never altering
/// the underlying string that was verified or persisted.
enum SentenceFragments {
    static func split(_ text: String) -> [String] { ... }
}
```

A plain split on `". "` (and a trailing lone `"."`), trimming each fragment and re-appending its terminal period, is sufficient: every producer of this text (`ReportText.momentLines`'s concatenated clauses, and the Coach LLM's "2-4 sentences" prose) already produces period-delimited English sentences, confirmed by reading both `ReportText.swift` and `CoachPrompt.momentUserMessage`'s instruction to the model.

Apply it at exactly two call sites, both purely at render time:
- `GameReportView.narrationView` (Coach narration) and `GameReportView.momentSummary`'s call site in `keyMomentRow` (rule-based text) - render `ForEach(SentenceFragments.split(text), id: \.self) { Text($0).font(.dsBody) }` in a `VStack(alignment: .leading, spacing: 2)` instead of one `Text(text)`.
- `PracticeContentView.feedbackView`'s `Text(feedback.explanation)` - same treatment, since B1 established this is the same underlying string family.

This resolves the tension the stub named explicitly (expand-affordance was floated but conflicts with the no-disclosure idiom established in phase 1): the resolution is that nothing is ever hidden, so there is no disclosure to build - every sentence is always visible, just laid out as short separated lines instead of one dense paragraph. This is a strictly rendering-side, zero-risk-to-grounding change per B2, and it is the first thing implemented and measured (Step 3) before any `CoachPrompt` change is considered.

### DD-B2 - `CoachPrompt` wording tightening is conditional, not committed, and must be re-verified if taken

Do not change `CoachPrompt.momentUserMessage` or `groundingRules` as part of this phase's first pass.
After DD-B1 ships and is seen live (Step 3's gate), if the Coach's *sentence count* itself (not just its layout) is still judged too dense at 2-4 sentences, tighten `momentUserMessage`'s instruction to "2-3 sentences" as a small, isolated follow-up, and only then re-run `swift run --package-path Packages/CoachKit coach-grounding` plus a repeated-run fallback-rate measurement (the stub's own requirement: "a single run proves nothing about a rate" - run the same moment payload at least 5 times and record how many trigger the rule-based fallback, before and after the wording change). If the fallback rate increases, revert the prompt change and say so explicitly in the devlog; do not silently accept a worse fallback rate. Do not touch `groundingRules`'s parenthetical-eval instruction at all - B2's own finding is that the verifier does not depend on that formatting, but removing the instruction to the *model* risks the model dropping evals from its prose entirely, which would increase ungrounded-numeric-claim rejections for a reason unrelated to density.

### DD-B3 - Where the two preview buttons sit relative to the now-chunked text

`GameReportView.momentSummary`'s single joined string must be split back into its constituent facts to attach a button to the right fragment (currently it is one opaque string by the time it reaches the view - `momentLines` joins before returning). Change `GameReportView.keyMomentRow` to build its display from the typed `KeyMoment` fields directly, one `Text` line per fact, rather than calling the app's local `momentSummary(_:)` string-builder at all:

- Eval-swing line: always present, no button.
- Better-move line (`if let betterMove = moment.betterMove`): the sentence, then the "Play out the better line" button (DD-A6) inline after it, calling `onPreviewBetterLine(moment)`.
- Punishment line (`if let punishment = moment.punishment`): the sentence, unchanged, no button - this is the engine's hypothetical refutation (A2), not something to preview as "what happened", and previewing it would misrepresent it as fact.
- Mate lines: unchanged, no button (out of scope - no user ask covers missed/allowed mate lines).
- One "Play out what happened" button (DD-A6) at the end of the block, always present when `viewModel.uciContinuation(fromPly: moment.ply, maxPlies: 10)` is non-empty, calling `onPreviewPlayedContinuation(moment)`.

This keeps `ReportText.momentLines`/`momentSummary` exactly as they are (still used for the plain-text `render()` export path and the Coach's Layer-1 payload, both of which have no button concept and should not gain one) - only `GameReportView`'s own rendering stops routing through the pre-joined string.

## Build sequence

Follow red-green-refactor. Each step has a verification gate that must pass before the next step starts.
Run `xcodegen generate` after adding any file.

### Step 1 - `LinePreviewController`

Red: add `App/Tests/ChessantoTests/LinePreviewControllerTests.swift`.

- `testStepZeroIsStartingPositionWithNoLastMove`
- `testStepCountIsMovesPlusOne`
- `testStepForwardAdvancesToEachMovesResultingPosition`
- `testStepBackwardReturnsToPriorPosition`
- `testCannotStepPastStartOrEnd` (`canStepForward`/`canStepBackward` false at the bounds; calling the stepping method there is a no-op, not a crash)
- `testJumpToStartAndJumpToEnd`
- `testStepsTruncateAtFirstIllegalOrUnplayableMove` (feed a UCI list where `ChessGame.replayLine` truncates early; `stepCount` reflects the shorter real length, never crashes)

Green: add `App/Sources/Chessanto/Board/LinePreviewController.swift` per DD-A1.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/LinePreviewControllerTests`.

### Step 2 - Practice preview wiring

Red: extend `PracticeSessionViewModelTests` with:

- `testPreviewBetterLineBuildsControllerFromCardsTopRankedLine`
- `testPreviewBetterLineIsNoOpWhenNoRankedLineHasAMove`
- `testEndPreviewClearsLinePreviewWithoutChangingCardPosition`

Green: add `linePreview`/`previewBetterLine()`/`endPreview()` to `PracticeSessionViewModel` per DD-A3; branch `PracticeBoardSection` on it; add the "Play out the better line" button to `PracticeContentView.feedbackView` per DD-A5/A6.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS' -only-testing:ChessantoTests/PracticeSessionViewModelTests`.

### Step 3 - Sentence chunking (Item B, rendering only)

Red: add `App/Tests/ChessantoTests/SentenceFragmentsTests.swift`.

- `testSplitsMultipleSentencesOnPeriodSpace`
- `testSingleSentenceReturnsOneFragment`
- `testHandlesParentheticalPeriodlessLineWithoutOverSplitting` (e.g. a line ending `"(O-O Nd3 Qe7+ Be2 Nxh1 Nxc5)."` must not split inside the parenthetical)
- `testEmptyStringReturnsEmptyArray`

Green: add `SentenceFragments.swift` per DD-B1; wire it into `GameReportView.narrationView`, the rule-based rendering in `keyMomentRow` (as restructured by Step 4), and `PracticeContentView.feedbackView`.

Gate: the same focused test command as Step 1, targeting `SentenceFragmentsTests`. Then a manual read of Report for game 9 (already-analyzed fixture, no new analysis needed) confirming the dense text from B3's live evidence now renders as separated lines. This is the checkpoint DD-B2 depends on before deciding whether a prompt change is still warranted.

### Step 4 - Report key-moment restructure and the two preview buttons

Red: extend `GameReplayViewModelTrainingTests` (or a new suite if it grows unwieldy) with:

- `testUCIContinuationReturnsMainlineMovesAfterPly`
- `testUCIContinuationCapsAtMaxPlies`
- `testUCIContinuationStopsAtGameEndBeforeReachingCap`
- `testUCIContinuationEmptyAtFinalPly`

Green: add `uciContinuation(fromPly:maxPlies:)` per DD-A4; restructure `keyMomentRow` per DD-B3, adding `onPreviewBetterLine`/`onPreviewPlayedContinuation` callbacks to `GameReportView`; wire `GameReplayView`'s new `linePreview` state and `boardColumn` branch per DD-A3; add `LinePreviewControlsView` per DD-A6.

This step has no clean view-model-only red/green for the view restructure itself (same situation phase 1's Step 3 was in) - verify it natively per the E2E section, specifically E2E-1 and E2E-2, not by source reading alone.

Gate: `xcodebuild test -scheme Chessanto -destination 'platform=macOS'`, the full suite, count must exceed the 70/17 baseline.

### Step 5 - Practice's "played continuation" is deliberately absent; confirm the guard, don't build around it

No red/green here - this step is a checklist confirmation, not new code. Confirm `PracticeContentView` has no "Play out what happened" button anywhere (A2/DD-A3 restricts this to Report), and that this is a real scope boundary, not a missed spot: `TrainingCard` has no loaded `ChessGame` and no `gameId`-keyed mainline available without adding a new store round-trip this phase does not need. If a future session wants this in Practice too, it needs its own design pass for how Practice would fetch a game's mainline - do not improvise it here under time pressure.

### Step 6 - Conditional `CoachPrompt` tightening

Only if Step 3's live read (game 9's Report, Coach enabled) still shows the Coach narration itself needs fewer sentences, not just better layout.
Follow DD-B2 exactly: change `momentUserMessage`'s sentence-count instruction only, run `coach-grounding`, and run the same moment payload 5 times before and 5 times after to compare fallback rates. Record both rates in the devlog regardless of which way the decision goes.

Gate: `swift run --package-path Packages/CoachKit coach-grounding` exits 0. If skipped, record explicitly in the devlog why Step 3 was judged sufficient.

### Step 7 - Full verification

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

No schema migration is added in this phase (A1/A2 both confirmed the needed data already exists), so `Packages/Persistence`'s 29 tests should be unchanged; if the count moves, stop and work out why before continuing.

## Native E2E reproduction and acceptance

### Database safety, mandatory

Same protocol as phase 1, with a fresh timestamp and a phase-2-specific label:

```
LIVE="$HOME/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite"
STAMP=$(date +%Y%m%d-%H%M%S)
cp "$LIVE" "$LIVE.before-uiux-phase2-$STAMP"
md5 -q "$LIVE" > /tmp/chessanto-live-md5-before.txt
QA="$HOME/Library/Containers/com.chessanto.app/Data/tmp/uiux-phase2-$STAMP"
mkdir -p "$QA"
cp "$LIVE" "$QA/chessanto.sqlite"
open -n "<Release>/Chessanto.app" \
  --env CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1 \
  --env CHESSANTO_DATABASE_PATH="$QA/chessanto.sqlite"
```

At session end, `md5 -q "$LIVE"` must equal the recorded before value. This session already performed one read-only copy-and-query of the live database for the diagnosis above and confirmed its md5 was unchanged afterward; the execution session must do its own fresh copy, since real time will have passed and the live database will have moved on.

### Fixture

Game 9, `adamzainuri vs WillisLiao`, reconfirmed present in the live database this session with the same shape phase 1 used: analyzed, `WillisLiao` (configured username) played Black, 8 training cards, card id 6 at `sourcePly` 14 with the 15-ply rank-1 PV and the exact explanation text quoted in A1.

### Acceptance scenarios

- **E2E-1, better-line preview from the Report.** Open game 9's Report. Find the key moment at move 14 (card 6's moment). Press "Play out the better line". Assert the board shows the starting (pre-move) position with no highlight, then steps forward through at least 6 plies as `Next` is pressed repeatedly, with the step counter and highlighted squares changing each time, ending exactly where `Next` becomes disabled. Press `Done`; assert the board returns to showing the live report position it showed before entering preview.
- **E2E-2, played-continuation preview from the Report.** From the same key moment, press "Play out what happened" instead. Assert the first step's move matches the game's actual next move (from the move list), not `punishment.refutingSAN` if the two differ for this fixture - check both against the move list to confirm which is which before asserting.
- **E2E-3, better-line preview from Practice.** Open Practice, answer a card correctly (or press "Reveal" if none answers cleanly from the fixture), and in the resulting feedback state press "Play out the better line". Assert no such button exists in the prompt state before answering (DD-A5).
- **E2E-4, no persisted side effect from preview.** Before and after E2E-1 through E2E-3, query the QA copy's `variation` table row count for gameId 9. It must be identical - previewing must never insert a `variation` row (A4/DD-A1).
- **E2E-5, Coach and rule-based text chunking.** With Coach enabled, read the key-moment block for card 6's moment via `axprobe`. Confirm the eval-swing, better-move, and punishment sentences render as visually separated lines (multiple `AXStaticText` elements or a single element with confirmed line breaks, whichever `axprobe` actually reports - check both before asserting) rather than one wrapped paragraph. Repeat for Practice's feedback text after answering the corresponding card correctly.
- **E2E-6, grounding still holds.** Run `swift run --package-path Packages/CoachKit coach-grounding` and confirm it exits 0, both before touching any code (to reconfirm the starting baseline) and after all changes.
- **E2E-7, no data loss.** Confirm the QA copy recorded any attempts made during the session and the live database md5 is unchanged at the end.

Capture a screenshot for each scenario with `scripts/capture-window.swift` and reference the paths in the devlog.

## Documentation, commit, and push

- Update the top of `handoffs/HANDOFF.md` with a `UI/UX clarity phase 2 complete` section, following the shape of the existing `UI/UX clarity phase 1 complete` section.
- Append a dated section to the current date's devlog, recording the live evidence, the two corrections this plan already carries (A2's punishment-vs-actual-continuation correction, B2's verifier-mechanics correction), the fallback-rate measurement if Step 6 ran, and any new correction found during implementation.
- Write `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-3.md` forward with anything learned that phase 3 needs - it already exists as a stub from the original three-phase split; extend it, do not replace it wholesale, unless implementation reveals its own precondition section is now wrong the way this document's precondition section corrected phase 1's.
- Commit and push the docs alongside the code.
- Do not modify `CHANGELOG.md` or any generated file.
- Do not add an agent co-author to the commit.
- One full sentence per physical line in Markdown, and never the em dash character.

## Final checklist

Confirm each line honestly. Do not claim a deferred item.

- [x] The learner can watch and manually control the engine's better line from both Practice feedback and the Report key-moment block.
  Autoplay supersedes the original manual-only constraint by explicit user decision.
- [x] The learner can play the actual game continuation from the Report key-moment block.
  This remains deliberately absent from Practice because a training card does not carry the loaded mainline game.
- [x] No preview affordance is reachable before a Practice card has been answered or revealed.
- [x] Previewing a line never inserts a `variation` row, verified by the unchanged QA row count.
- [x] `LinePreviewController` has no dependency on `GameStore` or `GameReplayViewModel`'s variation tree.
- [x] Dense narration no longer renders as one paragraph in Report or Practice.
  The synchronized comic Coach stage supersedes the original sentence-fragment layout by explicit user decision.
- [x] `card.explanation`'s persisted value is unchanged.
- [x] `CoachVerifier`'s grounding guarantee is unweakened.
  `coach-grounding` passed ten narration runs and its chat section with no violations or leaks.
- [x] The full app suite, every package suite, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh` pass.
- [x] The live database checksum is restored to and verified as `1d218f0371a61f85bc682cc43acb9af5`.
- [x] Phase 3 sidebar organization, Player Brief, and chess.com identity confirmation were completed earlier on 2026-07-19 and remain intact.
- [x] The separate Coach chat panel was not changed because it was explicitly outside this phase's planned scope.

## Suggested skills

- `ui-ux-pro-max` together with `frontend-design` for Steps 2 through 4, per the standing repository rule for substantial UI/UX changes.
- `codebase-design` was already used during this planning session to settle `LinePreviewController`'s shape and ownership (DD-A1/A3); re-invoke only if implementation reveals the interface needs to grow beyond what DD-A1 specifies, and treat that as a signal to stop and reconsider rather than just adding a parameter.
- `tdd` for Steps 1, 2, 3, and 4's view-model parts.
- `diagnosing-bugs` before Step 4's view restructure, since phase 1 already found one case in this exact file (`GameReportView.keyMomentRow`) where a confident source-reading diagnosis was wrong.
- `mattpocock-skills:code-review` before the final commit, with this document as the spec axis.
