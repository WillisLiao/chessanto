# Next session - the ignored-threat detector (P4.2, scoped to one detector)

Bootstrap document for unstarted work.
Written 2026-08-24, continuing the production-grade push recorded in `devlogs/2026-08-21.md` and `devlogs/2026-08-22.md`.

## Read first, in this order

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `devlogs/2026-08-21.md` and `devlogs/2026-08-22.md`, for how the two most recent sessions worked: how scope was chosen, how a design was settled before implementation, and specifically the false-positive bug the second session found and fixed in `BrilliancyDetector` - that story is the model for how this session must treat its own detector.
3. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, section "P4.2 Add the detectors that explain real games", for the original framing of this work.
4. `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift`, in full. This is the pattern every detector in this codebase follows, and `punishment`'s doc comment (lines ~59-89) is required reading: it explains, from a real incident, why this codebase asks the board directly rather than inferring from a principal variation's shape or a fixed-length snapshot, and why an earlier cruder version of that detector produced false "hanging piece" claims that then propagated into practice themes and the Player Brief.
5. `Packages/AnalysisKit/Sources/AnalysisKit/BrilliancyDetector.swift`, in full, plus its git history (`git log -p -- Packages/AnalysisKit/Sources/AnalysisKit/BrilliancyDetector.swift`). This is the most recent detector built in this codebase and the most recent example of a false positive being found and fixed by running the detector over the real fixture corpus and reading every fire by hand rather than trusting that tests passing meant the logic was correct.
6. `Packages/AnalysisKit/Sources/AnalysisKit/FactAuditor.swift`, `Packages/AnalysisKit/Sources/AnalysisKit/ReportBuilder.swift`, and `Packages/AnalysisKit/Sources/AnalysisKit/GameReport.swift`, to understand how a new Fact type would flow into a `KeyMoment` and get audited, since this detector - unlike `BrilliancyDetector`, which only changes a classification label - is expected to produce a genuine new Fact that appears in report prose.
7. `Packages/ChessCore/Sources/ChessCore/ChessGame.swift`, for the exact replay/material/legal-move helpers already available (`replayLine`, `material`, `legalMoveCount`, `hasLegalMove`) - reuse these, do not reinvent board logic.

## The problem

`handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` names this as the single highest-value missing detector:

> The opponent had a threat and the played move failed to address it. This is the single most common cause of a loss below 600 and is completely absent.

Today the app's entire explanatory vocabulary for *why* a move was bad is four fact types: eval swing, better move, punishment (a capture that wins material), and missed/allowed mate. None of them explain the single most common way a beginner loses a game: the opponent had already set up something concrete (usually "I can win a piece next move" or "I can deliver mate next move"), and the player's move did nothing about it.

## Scope for this session

Implement exactly one new thing: a detector that identifies when the mover's move ignored a concrete threat the opponent already had, and a Fact/sentence that names what the threat was and what happened when it was carried out.

Do not attempt forks, pins, skewers, discovered attacks, back-rank weaknesses, trapped pieces, or the move-quality flags (developed-piece-moved-twice, queen-out-early, etc.) also listed under P4.2 in the backlog document. Those are separate, later sessions. This session is one detector, done carefully, verified against real games, and shipped.

## What "a threat" operationally means here - design this before writing code

This codebase has a hard rule, demonstrated twice now (`punishment`'s original false-positive incident, and `BrilliancyDetector`'s k=2/k=4 false positive found and fixed in the previous session): a wrong claim about the board is worse than no claim at all. `ThemeDetector`'s existing pattern is to ask the board directly - replay real moves through `ChessGame` - rather than infer from a principal variation's shape, length, or a fixed early snapshot. Follow that discipline here.

You do not have a null-move or "what if the mover passed" analysis available anywhere in this codebase - `ReportInput` only stores real engine lines from real positions the game actually reached, always with the side to move being whoever's turn it legitimately is. Do not invent a workaround that requires analysis this codebase does not have (e.g. do not call the engine yourself or introduce a new analysis pass - this stays a rule-based detector over data already stored, exactly like every existing `ThemeDetector` function).

The operational path that stays inside what is actually stored: look at what the opponent's move immediately after the mover's move (`input.plies[p + 1]`, if it exists) actually did on the board, and ask whether that same idea - the same capture, the same mating attack - was *already available to the opponent one move earlier*, at the position before the mover's move (`input.plies[p - 1].fen`), such that the mover's move at ply `p` should have been spent addressing it and instead did something unrelated.

Concretely: at the position before move `p` (`input.plies[p - 1]`), does the *opponent's own subsequent move* (`input.plies[p + 1].playedUCI`, one full move later) win material or deliver mate when judged against the position **as it stood before the mover's move**, not because the mover's move enabled it, but because it was already sitting there? You will need to reason carefully about how to test "already sitting there" using only board replay - one approach is to check whether the opponent's follow-up move (or an equivalent capture on the same square/piece) was already a legal, materially-winning or mating move in the pre-move position, using `ChessGame`'s legal-move and material helpers, and confirm the mover's actual move neither captured the threatening piece, blocked the line, nor defended the target square. Work this out precisely and write down your reasoning in the code's doc comments the way `ThemeDetector.punishment` does, before you write the implementation. If you find the "already sitting there" test is not reliably answerable from stored data without a second engine call, say so explicitly in your session report rather than shipping a detector that guesses - a narrower, more conservative version that only fires on the clearest cases is strongly preferred over a broader one with false positives.

Be as suspicious of your own first design as the previous session was of `BrilliancyDetector`'s first design. Before you accept your algorithm as correct, run it over the real committed game fixture(s) under `Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/` and any other real games available to you, and **read every single fire by hand** - the actual position, the actual moves - and judge whether a competent player would agree "yes, that was a threat and it was ignored." If you find even one false positive, do not ship it as "working as designed" - fix the detector the way the last session fixed `BrilliancyDetector`, by finding the real reason the false positive happened (usually: the operational definition was measuring something adjacent to the real concept, not the real concept itself) and correcting the definition, not by adding a special case on top.

## Design decisions you must make and write down (with your reasoning, in code comments and in your session report)

1. The exact Fact type's shape - name, fields, whether it needs a "what was threatened" description (a piece and square, or a mate-in-N), and how it composes into `ReportText` prose. Follow the existing `Fact` pattern in `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift` (or wherever the existing Fact structs live - find the actual file) and `ReportText`'s existing sentence-template style (see `punishmentSentence`, `missedMateSentence` for the tone and structure to match).
2. Whether this Fact needs a `FactAuditor` case (it almost certainly does, since every other Fact that appears in a `KeyMoment` is audited - confirm by reading `FactAuditor.swift` and `ReportBuilder.build`'s `FactAuditor.audit` call).
3. Whether an ignored threat should become its own `MoveClassification`-adjacent signal, feed into `KeyMomentSelector`'s selection (candidate kinds are currently `[.inaccuracy, .mistake, .blunder, .missedWin]`, defined in `KeyMomentSelector.swift`), or simply attach as an additional fact on whatever `KeyMoment` the existing eval-swing-based selection already produces for that ply - the backlog document implies the latter (it should explain moments that are already selected, the way `punishment` and `betterMove` already do), but confirm this reading against how `momentLines` in `ReportText.swift` composes multiple facts onto one moment before deciding.
4. How this interacts with the beginner register work from `devlogs/2026-08-21.md` (`RatingRegister`, `Packages/AnalysisKit/Sources/AnalysisKit/RatingRegister.swift`) - a beginner is exactly the audience most helped by "you missed that they were about to win your knight," so this Fact's sentence should almost certainly render for beginners without modification, but check whether it needs the same "no percentages, no eval-label numerals" discipline `ReportText`'s beginner branches already follow, and match it if so.
5. Whether `prefersNameableConsequences` in `KeyMomentSelector` (added in the 2026-08-21 session specifically to prefer moments with a concrete, nameable consequence for beginners) should be extended to also treat an ignored-threat Fact as a "nameable consequence" alongside punishment/missedMate/allowedMate - this is very likely correct and in scope, since it is exactly the kind of fact that framework was built for, but confirm the exact call site (`KeyMomentSelector.swift`) before changing it.

## Required rigor

- TDD (red-green-refactor), this project's standing convention. Write the failing test before the implementation for each piece of behavior.
- Follow this project's TDD/diagnosis conventions: reproduce the target behavior against a real fixture before trusting any synthetic one.
- Every new public Swift symbol needs a doc comment explaining *why*, in this codebase's existing voice (see any function in `ThemeDetector.swift` for the tone: plain, specific, explains the reasoning that led to the design, not just what the code does).
- Never use the em dash character ("—"). Use a plain dash ("-") instead, in code comments, commit messages, and any Markdown you write.
- When writing or substantially editing long Markdown documents (this file's style is the model), put each full sentence on its own physical line.
- Do not modify `CHANGELOG.md` or any generated file.
- Do not add an agent name as a co-author in any commit message.

## Test plan (minimum - add more as your design requires)

- A clear positive fixture: a position where the opponent has just created a concrete, one-move-away material or mating threat, the mover's move does not address it, and the opponent duly executes it next move. Build this as a minimal hand-constructed FEN/PV fixture in the style of `ThemeDetectorTests.swift` or `BrilliancyDetectorTests.swift` - read whichever of those files is more directly analogous to what you build.
- A fixture where the mover's move *does* address the threat (captures the threatening piece, blocks it, defends the target) - must not fire.
- A fixture where no threat existed at all (an ordinary quiet position) - must not fire.
- A fixture where the opponent's next move is unrelated to any pre-existing threat (they simply found a new idea after the mover's move enabled it) - must not fire, since the point of this detector is specifically "already there and ignored," not "any bad thing that happened afterward" (that is what `punishment` and the eval-swing already cover).
- Whatever edge cases your specific operational definition turns up as you build it - checkmate ending the line early, the opponent's follow-up move not existing (end of game), no rank-1 data at the relevant ply, etc. Handle each as "no claim" (return nil/false), never a guess, matching every existing detector's discipline.
- Run the full detector over `Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/`'s real fixture(s) and report exactly what fired, with your by-hand judgment of each, the same way the previous session's report did for `BrilliancyDetector`. If a golden-fixture text file changes as a result, that change must be justified by your own hand-verification, not merely by tests passing.

## Validation commands, in order

1. `swift test` from `Packages/AnalysisKit/` - must pass. Baseline before this session: 105 tests across 6 suites.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 170 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure. If a diagnostics panel or editor shows stale-looking errors (e.g. "No such module X" across many unrelated files at once) that contradict a command you actually ran and saw pass, trust the command you ran, not the stale panel - but only after you've actually run it yourself, not before.

## Non-goals

Forks, pins, skewers, discovered attacks, back-rank weaknesses, trapped pieces (rest of P4.2). Move-quality flags: capture-or-check, redeveloping a piece, moving the same piece twice before castling, early queen development (rest of P4.2). `[%clk]` time-per-move analysis (also mentioned in P4.2, unrelated to threats). P4.3 (takeaways), P4.5 (multi-ply practice cards), P4.6 (spaced repetition), P4.8 (the LLM Coach's purpose). Any change to `BrilliancyDetector`, `RatingRegister`'s thresholds, or anything from the two prior sessions' work beyond the narrow, confirmed extension named in decision 5 above.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections following the exact pattern already there for the two most recent entries (2026-08-21, 2026-08-22) - what changed, why, the design reasoning, verification results, what's deliberately not done.
Write a dated devlog under `devlogs/` following the same two files' structure and level of detail, including your own account of any false positive you found and how you fixed it (or, if you found none, say plainly that you checked and found none, with what you checked).
Commit your work with a descriptive message in this project's existing style (see `git log` on this repository for the voice: specific, explains reasoning and tradeoffs, states test counts).
Push to `origin/main` once your own verification (section above) is green - this project pushes each session's checkpoint rather than leaving it local.
Report back plainly: what you built, the exact design decisions from the numbered list above and why you made each, what you found when you hand-checked real fixture fires, all verification command results, and anything you could not verify or chose to leave undone.
