# Fork Detection [Completed Historical Record]

Historical note: Fork detection was implemented and integrated on 2026-08-24 (see `devlogs/2026-08-24-fork-detector.md` and `handoffs/HANDOFF.md`).
This document is preserved as the original session plan.

You are working in a dedicated git worktree on branch `fork-detector-p4.2`, checked out from `main`. Commit and push this branch when you are done; do not merge to `main` yourself; do not touch the primary checkout at `/Users/willis/Documents/chessanto` or any other worktree directory.

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.2 Add the detectors that explain real games" section.
3. `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift`, in full - especially `ignoredThreat` (the most recently added detector) and its doc comment, and `punishment`'s doc comment. Both describe, from real incidents in this codebase, why board-replay detectors here are built deliberately conservative and what happened the two times they weren't.
4. `Packages/AnalysisKit/Sources/AnalysisKit/BrilliancyDetector.swift` and its git history (`git log -p -- Packages/AnalysisKit/Sources/AnalysisKit/BrilliancyDetector.swift`) - the most recent example in this codebase of a detector that passed its own tests, fired on the real game fixture, and turned out to be a false positive, found only by hand-reading the actual fire. Read this before writing a single line of fork-detection code.
5. `Packages/ChessCore/Sources/ChessCore/ChessGame.swift`, in full.

## What is different about this task from every detector that came before it

Every existing detector in `ThemeDetector.swift` (`punishment`, `ignoredThreat`, `missedMate`, `allowedMate`, `betterMove`) works by replaying a sequence of moves through `ChessGame.replayLine` and reading the result - captures, checkmate, material balance. None of them need to answer "what does this piece attack right now, without anyone moving." A fork is exactly that question: after the mover's move, does the moved piece now attack two or more valuable enemy pieces (or a piece and the king) simultaneously.

**`ChessGame`'s current public API has no function for this.** It exposes `legalMoves(from:at:)` (destination squares for one piece, from the live game's move index, not an arbitrary FEN), `hasLegalMove(fen:endingOn:)` (whether the side to move can reach one specific square), and `material(fen:)` (totals only, no per-square piece list exposed through a public API). The underlying ChessKit library this app is built on does compute attacker information internally (`Board.attackers()`), but it is `private` and not exposed through `ChessGame`.

This means the very first piece of work in this session, before any fork logic, is **exposing a new, narrow, correctly-tested primitive on `ChessGame`** - not writing new chess logic, but making an already-computed internal capability public through this codebase's existing wrapper pattern (look at how `hasLegalMove` or `legalMoveCount` are implemented as thin wrappers over the underlying library, in the same file, for the pattern to follow).

## Step 1 - add the missing primitive (do this first, commit it, verify it in isolation)

Add a function to `ChessGame` with a shape like:

```swift
/// Every enemy piece square `square` currently attacks in the position
/// given by `fen`, from `square`'s own color's perspective - not
/// contingent on whose turn it is to move.
public static func attackedEnemySquares(from square: String, in fen: String) -> [(square: String, kind: PieceKind)]
```

(Adjust the exact signature and name to whatever fits this codebase's existing naming conventions once you've read the file - `square`/`endSquare` as `String` is the pattern `ReplayedMove` already uses elsewhere, follow it.)

Implement it as a thin wrapper over whatever the underlying ChessKit `Position`/`Board` type already computes - do not hand-write attack geometry (sliding piece rays, knight offsets, etc.) yourself if the library already has this logic; that would be re-deriving something this codebase's whole architecture avoids (reinventing chess rules instead of asking the library that already gets them right). If, after reading the ChessKit source available to you (search for it under a `.build` or checked-out dependency path, or via Swift Package Manager's local package cache), you find no accessible internal function to wrap, stop and report this precisely as a blocker rather than hand-writing attack-square generation - that would be exactly the kind of untrusted new chess logic this session's conservatism is about avoiding.

Write dedicated tests for this primitive alone, independent of fork detection, covering: a knight attacking two squares, a sliding piece (bishop/rook/queen) attacking along an open line but not through a blocking piece, a pawn's attack squares (diagonal only, not its forward move), and a piece with no attacks (blocked or off the edge of relevant material).

## Step 2 - the fork detector, scoped narrowly

Add exactly one new detector, `ThemeDetector.fork(input: ReportInput, ply p: Int) -> ForkFact?` (or whatever Fact-naming convention fits - follow `PunishmentFact`/`IgnoredThreatFact`'s existing pattern), that fires only when **all** of the following hold, checked in this order, cheapest first:

1. The played move at ply `p` is a real move (not book, not forced - though the actual gating by register/context happens in `KeyMomentSelector` the way `ignoredThreat` already does; this detector itself, like the others, should just answer "does a fork exist here" for any ply it's asked about).
2. Using the new primitive from Step 1, the moved piece (from `input.plies[p].playedUCI`'s destination square, replayed via `ChessGame.replayLine` to get `resultingFEN` and confirm the piece landed where expected) attacks **two or more** distinct enemy pieces simultaneously, or one enemy piece plus the enemy king (a "royal fork").
3. **Both attacked targets are pieces the opponent cannot simply move both out of danger in one move** - a "fork" that only threatens two pawns, or two pieces that are mutually defending each other such that neither is actually winnable, is not the kind of fork worth reporting. State precisely, in your own design, what board-replay check confirms "at least one of the two targets is actually going to be lost" - the same discipline `punishment` uses (replay the actual best response, check whether material was genuinely won, not just whether two pieces happen to sit on attacked squares). Do not report a fork on attacked-square geometry alone; confirm it costs the opponent something on the board, the same way every other detector in this file already insists on.
4. The two forked pieces (or piece + king) are each individually worth confirming as real targets - a fork of two pawns is not worth reporting; set a minimum combined or minimum-single-target value threshold and justify your choice the way `BrilliancyDetector`'s `minimumSacrifice = 3` was justified (a considered number, written down, not an arbitrary one).
5. The king, if forked, being in check is itself only reportable if the position is not simultaneously already covered by `missedMate`/`allowedMate` for the same ply - avoid the fork detector and the mate detectors both firing redundantly on the same decisive moment; decide how you'll prevent double-reporting (a precedence rule, similar to how `ReportText`'s dedup logic already suppresses a redundant `punishment` sentence when `ignoredThreat` already explains the same square - read that logic in `ReportText.swift` before designing your own).

## Do not implement pins, skewers, discovered attacks, back-rank weaknesses, or trapped pieces this session

Those are separate, later work - each has its own geometric definition and its own false-positive risk profile, and combining them into one session is exactly the kind of scope-stacking that made past sessions' work harder to verify. Fork only.

## Required rigor - the standard this codebase now holds every new detector to

- TDD. Write the failing test before each piece of implementation.
- After implementing, run the fork detector over the real fixture (`Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/real-fixture-game-report-input.json`, loaded via `RealFixtureGoldenTests.swift`'s existing mechanism) across every ply, and **read every single fire by hand** - the actual position, the actual pieces, the actual squares. If you find even one case a competent player would not call a real fork, do not ship it as "matches the spec" - find the real reason (usually: the operational definition measures something adjacent to the concept, not the concept itself) and fix the definition itself, the way the brilliancy detector's k=2/k=4 false positive was fixed by reading the settled position instead of a fixed window, not by adding a special case.
- Never use the long dash character; use a plain dash ("-"). One full sentence per physical line in long Markdown. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Test plan (minimum, in addition to Step 1's primitive tests)

- A clear positive fixture: a knight move that forks two undefended pieces of real value (e.g. rook and bishop) - fires, names both targets correctly.
- A royal fork: a piece forks the king and a valuable piece - fires, and does not also duplicate a `missedMate`/`allowedMate` sentence for the same moment (confirm your precedence rule with a test).
- A move that attacks two enemy pieces but both are adequately defended and recapture is even or favorable for the defender - does not fire (the geometric-attack-only false positive this design exists to prevent).
- A move that attacks one valuable piece and one pawn - does not fire (below the value threshold you set).
- A move with no fork at all (an ordinary developing move) - does not fire.
- The real-fixture-corpus check from "Required rigor" above, with your by-hand read of every fire reported explicitly, positive or negative.

## Validation commands

1. `swift test` from `Packages/ChessCore/` - must pass (covers Step 1's new primitive). Report the baseline count first.
2. `swift test` from `Packages/AnalysisKit/` - must pass. Baseline before this session: 126 tests across 6 suites.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
4. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 179 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Pins, skewers, discovered attacks, back-rank weaknesses, trapped pieces (later work). Wiring the new fact into `KeyMomentSelector`'s `prefersNameableConsequences` or into `ReportText` rendering - if you have time and confidence after the detector itself is solid and verified, this is a reasonable extension following `ignoredThreat`'s exact integration pattern (see `ReportBuilder.swift`, `FactAuditor.swift`, `KeyMomentSelector.swift`'s diffs for that feature), but the detector being correct and conservatively verified is the actual deliverable - do not rush wiring at the expense of verification. If you run out of session time, a correct, tested, unwired detector is a better outcome than a wired-but-unverified one. Do not touch move-quality flags, `%clk` analysis, practice cards, or the Coach - separate parallel sessions.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries.
Write a dated devlog at **`devlogs/2026-08-24-fork-detector.md`** (this exact filename - three other sessions are writing their own devlogs today).
Commit on this branch (`fork-detector-p4.2`) and push it to `origin` - do not merge to `main` yourself.
Report back plainly: whether the ChessCore primitive could be added cleanly or was a blocker, your exact fork definition and value threshold with reasoning, what you found hand-checking real fixture fires, whether you wired the fact into the report pipeline or left it verified-but-unwired, and validation results.
