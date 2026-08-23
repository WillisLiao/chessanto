# Next session - move-quality flags, and time-per-move if it's real (P4.2 slice)

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with three other sessions (fork detection, multi-ply practice cards, LLM Coach purpose - separate worktrees/branches, do not read or wait on any of them, your work is independent).

You are working in a dedicated git worktree on branch `move-quality-p4.2`, checked out from `main`. Commit and push this branch when you are done; do not merge to `main` yourself; do not touch the primary checkout at `/Users/willis/Documents/chessanto` or any other worktree directory.

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.2 Add the detectors that explain real games" section - specifically the move-quality bullet ("Whether the played move was a capture or check, whether it moved an already-developed piece again, whether the same piece moved twice before castling, and whether the queen came out before move five") and the `[%clk]` bullet.
3. `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift`, in full, and `Packages/AnalysisKit/Sources/AnalysisKit/ReportInput.swift`, in full - `PlyRecord`'s exact stored shape is what you have to work with.
4. `Packages/ChessComKit/Sources/ChessComKit/` in full - specifically wherever PGN comments (including any `[%clk ...]` annotation) are parsed today, to establish the actual current state of clock parsing before doing anything else.

## First: re-verify the premise, because it may be wrong

The backlog document claims `[%clk]` comments are "already parsed from chess.com PGNs per the M1 and M2 records and are never used" - implying the data exists and only needs surfacing. **A scan of the current codebase found no `%clk` parsing anywhere in `Packages/ChessComKit` or `Packages/AnalysisKit`, and no per-move time field on `PlyRecord` or anywhere in `ReportInput`.** Either the claim was true once and the code was since removed or never actually landed, or it exists somewhere not yet found.

Confirm this directly before writing anything: search the whole repository (not just the two packages above) for `%clk`, `clock`, `timeSpent`, and similar terms. If you find real, working `%clk` parsing that produces per-move time data already available somewhere, use it and build the time-per-move analysis described below. **If you confirm no such parsing exists**, treat this as a stretch goal only after the move-quality flags (below) are done, verified, and committed - implementing PGN `[%clk]` comment parsing from scratch is a bigger, riskier addition than this session's core scope, since it means correctly parsing a PGN annotation format this codebase has never handled, from real chess.com PGN exports, and getting wrong per-move time deltas would produce a new class of false claim. If you do attempt it, follow the same TDD-with-real-fixture-verification discipline as everything else in this document, and say explicitly in your report which case applied - the claim was right, or it was wrong and you confirmed that.

## The core scope: move-quality flags

These are structural facts about a move, derivable purely from replaying UCI move sequences already present in `ReportInput.plies[*].playedUCI` and `ChessGame.replayLine` - no engine evaluation needed, no new attack-geometry primitive needed (unlike the parallel fork-detection session), which is exactly why this is scoped as its own, more mechanical task.

Add detection for each of the following, as new fields on a new Fact type or types (follow this codebase's existing `Fact` pattern in `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift` - read it first to match the naming and shape convention exactly):

1. **Was the played move a capture or a check?** `ReplayedMove` (in `ChessGore.swift`... confirm the actual file, likely `ChessGame.swift`) already exposes `capturedPieceKind` and (confirm by reading) whether a move delivers check - if an `isCheck`/`isCheckmate` field already exists on `ReplayedMove` (a prior session's diff mentioned `isCheck` existing), this is close to free; wire it through rather than re-deriving it.
2. **Did the move move an already-developed piece again**, in the opening phase specifically (define "opening phase" concretely - e.g. within some ply count, or before the deepest book ply plus a small margin, or before both sides have completed a minimum development threshold; state your definition and reasoning)? This requires tracking, per side, which pieces have already left their starting square - derivable by replaying every move from the start of the game and recording each piece's origin/current square, not by anything exotic.
3. **Did the same piece move twice before that side castled?** A specific case of #2, worth calling out on its own since "moving the same piece three times in the opening while your king sits in the center" is a distinctly nameable beginner pattern separate from general redevelopment.
4. **Did the queen come out before move five** (for whichever side moved it)? A simple, precisely definable check: replay the mainline and find the ply, if any, where each side's queen first leaves its starting square, and flag if that ply's move number is under 5.

Design exactly how these compose into a Fact (or Facts) attached to a `KeyMoment`, and exactly how/whether they should influence `KeyMomentSelector`'s selection or only add explanatory color to moments already selected by eval-swing - the backlog document's framing ("explain real games") suggests the latter (these are context on an already-bad move, not independently disqualifying), but confirm this reading makes sense given how `ReportText` composes multiple facts onto one moment (`momentLines` in `ReportText.swift`) before committing to a design. State your reasoning.

These are lower-risk than a tactical motif detector (no attack geometry, no material-swing judgment calls) but still real claims about a game - apply the same "ask the board directly, don't guess" discipline as every other detector in this file, and the same real-fixture hand-verification step before considering the work done.

## Required rigor

- TDD. Write the failing test before each piece of implementation.
- After implementing, run everything over the real fixture (`Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/real-fixture-game-report-input.json`, via `RealFixtureGoldenTests.swift`'s existing mechanism) and read the actual output by hand before trusting it - this codebase's established practice, twice now proven to catch real bugs (`BrilliancyDetector`'s k=2/k=4 false positive; confirm zero surprises here too).
- Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in long Markdown. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Test plan (minimum)

- A capture move and a check-delivering move each correctly flagged.
- A piece moved once in the opening, then moved again - flagged as redevelopment; a piece moved only once - not flagged.
- A specific "same piece moved twice before castling, king still in center" scenario - flagged; the same piece moving twice *after* castling - not flagged (state whether this distinction matters to your design and why).
- Queen moved on move 3 - flagged; queen moved on move 8 - not flagged; queen never moved - not flagged, no crash.
- The real-fixture-corpus check, with your reasoning about what fired and whether it's correct, reported explicitly.
- If you implement `%clk` parsing: a real chess.com PGN snippet with `[%clk h:mm:ss]` comments, parsed correctly into per-move time deltas, plus a test for a PGN with no clock comments at all (must not crash, must produce no time data, not zero or garbage).

## Validation commands

1. `swift test` from `Packages/AnalysisKit/` - must pass. Baseline before this session: 126 tests across 6 suites.
2. `swift test` from `Packages/ChessComKit/` - must pass, only if you touched clock parsing there. Report the baseline count first.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
4. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 179 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Fork/pin/skewer/discovered-attack/back-rank/trapped-piece detection (a separate parallel session owns tactical motifs). Multi-ply practice cards, the Coach's purpose. Do not touch `MoveClassifier`'s classification thresholds. If you determine `%clk` parsing is out of reach for this session after confirming the premise was wrong, that is a completely acceptable outcome - say so plainly, do not force it in.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries.
Write a dated devlog at **`devlogs/2026-08-24-move-quality.md`** (this exact filename - three other sessions are writing their own devlogs today).
Commit on this branch (`move-quality-p4.2`) and push it to `origin` - do not merge to `main` yourself.
Report back plainly: what you found when you re-verified the `%clk` premise, which move-quality flags you implemented and how they're exposed, what you found hand-checking real fixture output, and validation results.
