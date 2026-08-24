# Concrete Takeaways (P4.3) [Completed Historical Record]

Historical note: Concrete takeaways were implemented and verified on 2026-08-24 (see `devlogs/2026-08-24-takeaways.md` and `handoffs/HANDOFF.md`).
This document is preserved as the original session plan.

You are working in a dedicated git worktree on branch `takeaways-p4.3`, checked out from `main`. This is a real, separate checkout - commit and push this branch when you are done, do not attempt to merge to `main` yourself, and do not touch the primary checkout at `/Users/willis/Documents/chessanto` (other sessions may be using it).

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state - especially the most recent entries, since the ignored-threat detector (P4.2) landed very recently and this session should use it.
2. `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`, the "P4.3 Takeaways almost always say nothing" section, for the original framing.
3. `Packages/AnalysisKit/Sources/AnalysisKit/ReportBuilder.swift`, in full - `buildTakeaways` (currently around lines 109-166) is what you are extending. Read the whole file for context on how `KeyMoment`, `Fact` types, and the rest of report-building work.
4. `Packages/AnalysisKit/Sources/AnalysisKit/ThemeDetector.swift`, in full, especially `punishment` and `ignoredThreat` (the most recently added detector) - both are the pattern for asking the board directly rather than inferring, and `ignoredThreat`'s doc comment explains the reasoning behind its own design.
5. `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift` and `KeyMoment`'s definition, to see every Fact type currently available to build a takeaway from: `EvalSwingFact`, `BetterMoveFact`, `PunishmentFact`, `IgnoredThreatFact`, `MissedMateFact`, `AllowedMateFact`.
6. `Packages/AnalysisKit/Sources/AnalysisKit/RatingRegister.swift` and how beginner-register prose differs elsewhere in `ReportText.swift` (qualitative language, no percentages, no eval-label numerals) - if takeaways should also vary by register, match that existing discipline rather than inventing a new one.
7. `Packages/AnalysisKit/Tests/AnalysisKitTests/ReportBuilderTests.swift` and `Packages/AnalysisKit/Tests/AnalysisKitTests/RealFixtureGoldenTests.swift`, for this codebase's established test patterns and the golden-fixture mechanism you will need to re-verify against.

## The problem

`ReportBuilder.buildTakeaways` has, today, five rules: a recurring-punishment theme (fires only when one player has 2+ punished moments), a missed forced mate, an allowed forced mate, an opening-deviation note, and a fallback ("A clean game" or "No single recurring pattern stood out - see the key moments above for specifics") when nothing else fires.

The backlog document that scoped this work says plainly: the rules that fire are the rare ones, and "the most instructive thing in a game below 600 is almost never a missed mate in four." The fallback will be the common outcome in most real games, which is the app admitting it has nothing to teach at exactly the moment a takeaway would matter most.

Since this document was written, `ThemeDetector.ignoredThreat` (P4.2) has landed - a `KeyMoment` can now carry an `IgnoredThreatFact` alongside `PunishmentFact`. That is new, real signal this rule set does not yet use at all.

## Scope for this session

Extend `buildTakeaways` so a real game - not just a game with a missed mate in four - produces something concrete and true more often. Specifically:

1. **Add a recurring ignored-threat rule**, mirroring the existing recurring-punishment rule's shape (2+ occurrences for one player, naming the count and the move numbers) but for `IgnoredThreatFact`. Decide whether this should be a separate takeaway or combined with the punishment rule into one "recurring missed tactics" theme that counts both fact types together - read both `PunishmentFact` and `IgnoredThreatFact`'s actual field shapes before deciding, and write down your reasoning either way.
2. **Add a general error-frequency rule** that fires on ordinary games with no dramatic single moment but a real pattern of smaller mistakes - e.g. naming how many inaccuracies/mistakes/blunders a player made and what fraction of their scored moves that represents, using data already computed in `whiteClassificationCounts`/`blackClassificationCounts` (already built earlier in `ReportBuilder.build`, confirm exactly how to reach it from inside `buildTakeaways` or whether it needs to be passed in). This is the rule most likely to actually fire on a typical club or beginner game, since it needs no rare tactical event at all - only counting classifications that are already computed.
3. **Re-rank or re-select which takeaways are shown when several would fire.** The function currently caps at 3 and appends in a fixed rule order regardless of which is most instructive. Decide a sensible priority (e.g. a genuinely rare/severe fact like a missed mate should still outrank a generic "you made 6 inaccuracies" observation when both are true) and implement it - state your reasoning for the ordering you choose.
4. **Only fall back to "no single recurring pattern stood out" when it is genuinely still true** after the above - if your new rules substantially reduce how often that fallback fires on real games, say so explicitly in your report with the real fixture's before/after takeaways as evidence.

Do not implement anything from P4.2's remaining scope (forks, pins, discovered attacks, back-rank weaknesses, trapped pieces, move-quality flags), P4.5 (multi-ply practice), P4.6 (spaced repetition - a separate parallel session owns this), or P4.8 (the LLM Coach). Do not touch `MoveClassifier`, `KeyMomentSelector`, or `ThemeDetector` - this session only changes `buildTakeaways` and, if genuinely needed, adds a small new pure helper function alongside it in the same file.

## Required rigor - this project's established discipline for chess-domain claims

Every sentence a takeaway produces is a claim about a specific game. This codebase's whole architecture (typed Facts, `FactAuditor`, fixed-template `ReportText`) exists to keep every visible chess claim traceable to something actually computed and verified - do not free-compose a claim that is not directly backed by a Fact or a classification count already computed and already correct.

Two real bugs were found and fixed in the last two sessions of work on this codebase specifically by running new logic over the one committed real-game fixture and reading every output by hand rather than trusting green tests alone (`BrilliancyDetector`'s k=2/k=4 false positive, caught this way; `ThemeDetector.ignoredThreat`'s design was verified this way and found zero false positives). Do the same here: after implementing, run `buildTakeaways` over the real fixture (`Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/real-fixture-game-report-input.json` or wherever it is loaded from in `RealFixtureGoldenTests.swift`) and read the actual takeaway sentences produced. If a sentence reads as false, misleading, or grammatically broken for a real game, fix the rule, do not just make the test pass.

TDD (red-green-refactor), this project's standing convention. Write the failing test before the implementation for each new rule.

Never use the em dash character ("—"); use a plain dash ("-"). One full sentence per physical line in any long Markdown you write or substantially edit. Do not modify `CHANGELOG.md` or generated files. Do not add an agent name as a co-author in commit messages.

## Test plan (minimum - add more as your design requires)

- A fixture with 2+ ignored threats for one player and none for the other - the new rule fires, names the right player and count, the other player gets no such takeaway.
- A fixture with a mix of inaccuracies/mistakes/blunders and no rare tactical event at all - the new general error-frequency rule fires with an accurate count, and the old fallback text does not appear.
- A fixture with both a rare event (missed mate) and a lot of ordinary mistakes - confirm your chosen priority/ranking surfaces the right ones within the cap of 3.
- A genuinely clean game (no errors at all) - the existing "A clean game" fallback still fires correctly and is not accidentally broken by your changes.
- Run the full existing test suite for `ReportBuilder`/`RealFixtureGoldenTests` and confirm nothing that currently passes regresses; if the real fixture's golden takeaways text changes as an intended, verified improvement, update the golden fixture file and say so explicitly in your report with a before/after comparison, the same way past sessions have documented golden-fixture changes.

## Validation commands

1. `swift test` from `Packages/AnalysisKit/` - must pass. Baseline before this session: 123 tests across 6 suites.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
3. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 174 tests across 34 suites.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Rest of P4.2 (forks/pins/discovered attacks/move-quality flags), P4.5 (multi-ply practice), P4.6 (spaced repetition), P4.8 (the LLM Coach's purpose), P2.5 (Coach entry points). Do not touch `MoveClassifier`, `KeyMomentSelector`, `ThemeDetector`, `RatingRegister`, or any App-layer file - this is an AnalysisKit-only session. Do not add a new Fact type - use what `PunishmentFact`, `IgnoredThreatFact`, and the already-computed classification counts already give you.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections, adding a new entry rather than editing others' entries - other parallel sessions are touching this same file and it will be merged by hand afterward, so keep your addition self-contained and easy to splice in.
Write a dated devlog at **`devlogs/2026-08-24-takeaways.md`** (this exact filename, not the bare date - two other sessions are writing their own devlogs today and a shared filename causes a git conflict during integration).
Commit on this branch (`takeaways-p4.3`) and push it to `origin` - do not merge to `main` yourself, a separate integration step will handle that.
Report back plainly: the new rules you added and why, the priority/ranking decision and its reasoning, the real fixture's before/after takeaway output, and validation command results.
