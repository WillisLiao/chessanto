# Next session - UI/UX clarity phase 2: playable variations and Coach text density

This is a scoping stub, not a verified execution plan.
It is deliberately not fully designed, because phase 1 restructures the exact surfaces this phase builds on and any detailed design written now would drift before it is picked up.
A planning session should expand this the way `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-1.md` was expanded: read the post-phase-1 source in full, reproduce every claim live, then fix the design decisions before writing code.

## Precondition

Phase 1 must be complete, because both items below depend on it.
Playable variations need the inline full-size practice board that phase 1 lands.
The Coach density work is easier to judge once the Report's key-moment block has phase 1's new structure.

## Item A - playable variations

The user's request, verbatim intent: the moves named in an explanation, both the suggested better line and the actual bad continuation that was played, should be able to play out on the board when the user chooses to see them, instead of only appearing as SAN text in a paragraph.

### What the planning session already verified, so the next session need not redo it

- `RankedLine.principalVariationUCI` already persists a full principal variation, not just a first move.
  Training card id 6 in the QA snapshot carries a 15-move rank-one PV while its explanation renders only 6 SANs.
  Confirmed by reading `trainingCard.rankedLinesJSON` directly out of the database.
- Therefore **no schema migration and no change to `RankedLine`'s shape are needed** for the better line.
  The bootstrap flagged this as an open risk; it is closed.
- The actual played continuation is not persisted on the training card, but it does not need to be.
  The card carries `gameId` and `sourcePly`, and the game's PGN is already in the `game` table, so the played move and everything after it are recoverable by replay with no new storage.
- In the Report, the full `KeyMoment` is in memory, so `betterMove.lineSANs` and `punishment.refutingSAN` are directly available there.

### The real design problem

Board state must be able to step through moves that are not part of the actual game tree and then return cleanly to the practice or report state it came from.
This is the one place a new seam is genuinely warranted.
Note that `GameReplayViewModel` already has a variation-tree concept with persistence, and that reusing it here would be wrong: a preview line the learner is watching is not a variation the learner authored and must not be written to the `variation` table.
Use `codebase-design` to design a preview mode that is explicitly distinct from the authored-variation tree.

### Open questions for the planning session

- Whether the preview is a step-through with controls, or an autoplay, or both.
- How the preview interacts with the hint and reveal state already on the practice board.
- Whether the Report and practice share one preview component or each get their own.

## Item B - Coach text density

The user's request: the Coach's prose in the Report key moments is too dense and packed for the space it is shown in, and needs simplifying while keeping the material facts intact, meaning the actual move played, the eval swing, and the better alternative.

### What the planning session observed live

Real Coach narration rendered in the Report for game 9 with model `qwen2.5-coder:3b`, for example:
`The player's mistake was to play Nxe5 instead of Qd5. This move allows the opponent to capture the pawn on f2 with their knight,` and continuing past the visible area.
The rule-based fallback text in the same block is itself dense, for example the four-clause `4... Nxe4 drops your winning chances from 41% to 24%. Better was Nb8 (Nb8 Bd3 d6 c4 g6 h3), keeping the evaluation around +1.0. This also left the knight on c6 hanging: dxc6 winning the knight.`

This matters for scoping: **both** the Coach path and the rule-based path are dense.
A prompt-only fix would leave the fallback exactly as bad, and the fallback is what renders whenever Ollama is off or the verifier rejects.

### The levers that exist

- `CoachPrompt.momentUserMessage` already asks for 2 to 4 sentences, so the prompt lever is a tightening, not a new constraint.
- `CoachPrompt.groundingRules` requires an evaluation in parentheses after every cited line, which is a real and deliberate contributor to density that cannot simply be dropped, because `CoachVerifier` is what makes the guarantee meaningful.
- `GameReportView.narrationView` is the rendering lever, where truncation with an expand affordance is possible.
- `ReportText.momentLines` is the rule-based lever.

### The hard constraint

`CoachVerifier`'s grounding guarantee must not weaken.
If shortening the prompt makes the verifier reject more responses and fall back more often, that is a worse outcome, not a better one, and the plan must say so explicitly and decide whether the tradeoff is acceptable rather than accept it silently.

Any prompt change must be re-verified with `swift run --package-path Packages/CoachKit coach-grounding` and with a real live Report render, not merely eyeballed for length.
The planning session should measure the fallback rate before and after over repeated runs, because a single run proves nothing about a rate.

## Suggested skills

`diagnosing-bugs`, `codebase-design` for the preview seam, `tdd`, and `ui-ux-pro-max` together with `frontend-design` for the presentation decisions.
