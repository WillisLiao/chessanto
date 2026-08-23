# 2026-08-24 - Takeaways that actually say something (P4.3)

## Context & Problem

The app's report-level "Takeaways" section previously had only five narrow rules: recurring punishments (2+ hanging pieces per player), missed forced mates, allowed forced mates, opening deviations leading to a disadvantageous evaluation, and a fallback.
Because missed mates and multiple hanging pieces are rare in typical games, almost all real games ended up triggering the fallback: "No single recurring pattern stood out - see the key moments above for specifics."
This fallback effectively signaled to the player that the report had nothing meaningful to say about their game, right when high-level takeaway coaching matters most.

With the recent landing of `ThemeDetector.ignoredThreat` (P4.2), `KeyMoment` can carry audited `IgnoredThreatFact` instances alongside `PunishmentFact`.
Furthermore, `ReportBuilder.build` already computes complete move classification counts (`whiteClassificationCounts` and `blackClassificationCounts`), which provide an accurate, grounded record of player decisions across the game.

## Implementation & Design Decisions

### 1. Recurring Ignored Threats Rule
We added a recurring ignored-threat rule mirroring the existing recurring-punishment rule's shape:
- Scans `keyMoments` for moments where `$0.evalSwing.moverIsWhite == isWhite && $0.ignoredThreat != nil`.
- If a player has 2 or more ignored threats, emits:
  `"\(ignoredMoments.count) of \(player)'s mistakes ignored an active threat from the opponent (\(moveNumbers.joined(separator: ", ")))."`
- **Design decision regarding separate vs combined rules**: We chose to keep recurring ignored threats separate from recurring punishments rather than merging them into a single generic "tactics" bucket. In chess pedagogy, proactively creating a new tactical weakness (hanging a piece / punishment) and reactively failing to notice what an opponent is already attacking (ignored threat) represent distinct cognitive blindspots. Keeping them distinct preserves traceability to specific audited Fact types and provides clear, differentiated feedback.

### 2. General Error-Frequency Rule
We added a general error-frequency rule that summarizes player consistency on games where no rare tactical event dominated:
- For each player with scored moves (`isPlayerDecision` is true), we count errors among `.inaccuracy`, `.mistake`, `.blunder`, and `.missedWin`.
- If a player made one or more errors, we format an exact error breakdown with proper singular and plural phrasing (e.g. `1 inaccuracy, 1 blunder` or `3 inaccuracies, 1 mistake`).
- Emits:
  `"\(player) made \(totalErrors) \(errorNoun) across \(scoredCount) \(moveNoun) (\(breakdown))."`
- Handled singular/plural nouns for error/errors and scored move/scored moves cleanly.
- Error frequency takeaways for both players are sorted by `errorCount` descending so the player with the larger mistake volume is highlighted first; ties default to White first.

### 3. Takeaway Prioritization & Selection
`buildTakeaways` aggregates candidate takeaways and caps the output at 3 items using an explicit pedagogical priority hierarchy:
1. **Priority 1 (Game-Deciding Tactical Crises)**: Missed forced mates and allowed forced mates.
2. **Priority 2 (Recurring Tactical Blindspots - 2+ occurrences)**: Recurring punishments and recurring ignored threats.
3. **Priority 3 (Opening Phase Strategic Breakdown)**: Early book deviations followed by an engine evaluation favoring the opponent.
4. **Priority 4 (General Error Frequency)**: Overall mistake volume and accuracy breakdown across scored moves.
5. **Priority 5 (Fallback)**: "A clean game: no mistakes or blunders at this analysis depth." when no mistakes exist, or "No single recurring pattern stood out..." if no higher rule fired.

This hierarchy ensures severe, game-ending tactical opportunities outrank broad statistical summaries, while ordinary games with minor mistakes consistently surface grounded error frequencies instead of the empty fallback.

## Real Fixture Validation (Magnus Carlsen vs artin10862)

The full report pipeline was verified against the committed real-game fixture (`real-fixture-game-report-input.json`):

**Before:**
```
Takeaways:
- No single recurring pattern stood out - see the key moments above for specifics.
```

**After:**
```
Takeaways:
- artin10862 made 2 errors across 24 scored moves (1 inaccuracy, 1 blunder).
- MagnusCarlsen made 1 error across 26 scored moves (1 inaccuracy).
```

Both the advanced and beginner golden fixture files (`real-fixture-game-golden-report.txt` and `real-fixture-game-golden-report-beginner.txt`) were updated to reflect this verified improvement.

## Verification & Test Results

1. `swift test` in `Packages/AnalysisKit`: 126 tests across 6 suites (all passed, up from 123).
2. `xcodebuild build` on macOS target: `** BUILD SUCCEEDED **`.
3. `xcodebuild test` on macOS target: 174 tests across 34 suites (all passed, `** TEST SUCCEEDED **`).
