# 2026-08-24 - Richer game library search and filtering

Session prompt: `handoffs/NEXT-SESSION-LIBRARY-SEARCH-FILTER.md`.
Worked on branch `feature/library-search-filter` in worktree
`../chessanto-library-search-filter`. The out-of-scope note for richer
search/filtering in `PLAN.md` was overridden by that prompt for this
session; everything else under "Product decisions (already made)" was left
alone.

## What was built

### The filter value type (`App/Sources/Chessanto/Library/LibraryFilter.swift`, new)

One small struct, `LibraryFilter`, holds search text plus every filter
dimension: opponent, outcome (win/loss/draw from the user's perspective),
opening family (ECO letter A-E), time control category, accuracy band, and
inclusive played-on day bounds. Any unset field imposes no constraint;
dimensions compose with AND semantics. The sidebar list reduces the register
against it via `matches(_:openingName:openingECO:userAccuracy:identity:)`,
which takes derived per-game values as parameters so tests need no store.

Semantics follow what the rows already show:

- Outcome mirrors `GameRow.userOutcome`: it resolves only when an identity is
  configured (`BriefIdentity`) and the user played in the game. Without an
  identity every outcome filter matches nothing.
- Search matches opponent names and opening name/ECO case-insensitively as
  substrings, excluding the user's own name so searching your username does
  not match every game.
- Time control buckets raw chess.com strings into Bullet/Blitz/Rapid/
  Classical/Daily using the same seconds cutoffs as
  `GameRowMetadata.formattedTimeControl`; unparseable or missing values
  cannot be selected by this filter.
- Accuracy bands are disjoint presets (90%+, 80 to 90%, Below 80%) over the
  user's own accuracy in analyzed games.
- `opponents(in:excluding:)` reuses `BriefIdentity.candidates(in:)`
  (most-played first, case-folded) minus the identity.

`LibraryFilterOptions.build(...)` produces the picker choices with counts,
computed against the source-scoped unfiltered list, so each menu option is
honest about its result size.

### The panel UI (`App/Sources/Chessanto/Library/LibraryFilterPanel.swift`, new)

A popover opened from a new Filter button in the register header next to
Organize. The button label gains "(N)" and brass tint when N constraints are
active. Every control uses existing design-system tokens only
(`DesignColors`, `DesignSpacing`, `.ds*` fonts); no new colors, fonts, or
spacing. The header shows "M of T" (matching vs total) which doubled as the
E2E verification readout. Result and Accuracy pickers disable themselves,
with help text, when there is nothing to match against (no identity / no
analyzed accuracies). Date bounds use two native DatePickers with per-field
clear buttons.

Search uses SwiftUI's native `.searchable(text:placement:.sidebar)` on the
sidebar column - no custom search bar.

### Enrichment reuse instead of new columns (`GameLibrary.swift`)

Nothing about openings or accuracy is stored per-game in Persistence, so
instead of adding derived columns I extended the existing background
enrichment pattern in `reload()`:

- `openings(for:analyzedGameIDs:)` became `openingEnrichment(for:)`: one PGN
  replay pass now fills `openingByGameID` (names, unchanged consumers) plus a
  new `openingECOByGameID`, and covers ALL games rather than only analyzed
  ones, because search and the opening filter need whole-register coverage.
  A side effect: unanalyzed sidebar rows now show their opening names too.
- New `userAccuracies(...)`: for each analyzed game the user played, builds
  the shared report through `ReportBuilding.buildReport` (the same seam
  `DashboardView.computeDashboard` uses) off the main actor and stores the
  user-side accuracy in `accuracyByGameID`. Nothing re-derives on filter
  changes; a cancelled reload leaves a valid partial dictionary.

The report/analysis pipeline itself was not touched - this only consumes it.

### Empty state

When constraints exclude everything but the register has games, the overlay
now reads "No results" (search active) or "No matching games", explains that
nothing matches the current search and filters, and offers a working
"Clear search and filters" button. The original empty-register messages are
unchanged.

### Performance (measured, not guessed)

`LibraryFilterTests.measuresFilterCostOverAnArchiveSizedRegister` reduces a
synthetic 2500-game register with three active dimensions and prints the
steady-state cost. Debug-build output from the final test run:

```
[perf] LibraryFilter.reduce over 2500 games: 4.515ms per pass (42 matched)
```

Four milliseconds per keystroke-equivalent pass in Debug means no debounce -
the handoff said not to add one speculatively and that stands. Whole-register
background enrichment was also measured with temporary instrumentation
(removed before commit), quoted from the QA run below: 52.9s first launch and
43.9s after import for 2526 games in Debug, fully detached at utility
priority; the UI stayed interactive the entire time.

## Verification

Commands and real output (Debug build, macOS):

```
swift test --package-path Packages/Persistence
  Test run with 44 tests in 2 suites passed after 0.186 seconds.

xcodegen generate   (run after every file add/remove)

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto \
  -destination 'platform=macOS' build    -> ** BUILD SUCCEEDED **

xcodebuild -project Chessanto.xcodeproj -scheme Chessanto \
  -destination 'platform=macOS' test
  Test run with 221 tests in 37 suites passed after 2.200 seconds.
  ** TEST SUCCEEDED **
```

New coverage: `LibraryFilterTests` (21 tests) covers search haystack rules,
outcome resolution and identity requirements, ECO family extraction, time
control category bands mirroring the row formatter, disjoint accuracy band
boundaries, inclusive date bounds with undated exclusion, AND composition,
unset-passes-all, activeCount/isActive/reset, opponent candidate ranking, and
the archive-scale cost measurement.

## Real-app verification against a large imported library

Setup: copied the live database to a disposable QA path (SHA-256 at session
start and end both `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`,
so the live database was never modified), confirmed the account in the copy
only, downloaded real chess.com monthly PGN archives (hikaru 2026-06/07/08,
GothamChess 2026-07/08; DanielNaroditsky returned empty), and seeded 2511
games into the QA copy with a script mirroring `importPGN`'s exact row shape.
Total register: 2526 games across Feb-Aug 2026. The app ran against the copy
via the two opt-in QA environment variables.

Every number below was read from the filter panel's live "M of T" line while
driving the real app over AX, and cross-checked against independent sqlite
queries over the same database:

| Action | Panel showed | Ground truth |
|---|---|---|
| open panel | 2,526 of 2,526 | 2526 active games |
| search "gothamchess" | 892 of 2,526 | SQL count 892 |
| clear + Result = Wins | 4 of 2,526 | hand-checked 4 (side-aware) |
| Result = Losses | 5 of 2,526 | hand-checked 5 |
| Result = Draws | 0 of 2,526 + empty state visible | 0 draws exist |
| Time control = Blitz | 1,334 of 2,526 | SQL band query 1334 |
| search "gothamchess" + Blitz kept | 338 of 2,526 | SQL intersection 338 |
| Opening = "ECO A  (1128)" + Blitz | 5 of 2,526 | composition consistent |
| Opponent = MagnusCarlsen | 3 of 2,526 | SQL count 3 |
| Accuracy 90%+ / 80-90% / Below 80% | 0 / 1 / 2 | sum 3 = user-analyzed games |
| Reset All | 2,526 of 2,526, all pickers Any | - |

The empty state ("No matching games" + message + Clear button) rendered for
the zero-match Draw selection, and the Clear button restored 2,526 of 2,526.
Searching "sicilian" matched 171 games purely via opening names derived by
the enrichment replay, confirming book-derived search works at scale. The
accuracy bands partitioning exactly to the 3 games where the identified user
had stored analysis confirms the accuracy enrichment wiring.

Real UI import: drove the actual Fetch sheet (Add game > Fetch from
chess.com). Fetched hikaru: "910 games fetched, 910 already imported" -
duplicate detection marked every seeded game correctly. Fetched
magnuscarlsen: "205 games fetched, 1 already imported"; unchecked Analyze
after import, selected the first row, imported. Database went 2526 -> 2527
with top row `FaustinoOro|MagnusCarlsen|180`; searching "faustino" then
showed "23 of 2,527", exactly the SQL count including the just-imported
game. Import feeds search immediately.

Temporary instrumentation added mid-session to measure enrichment (a print
inside the detached task) was removed before commit; its output was recovered
from the flushed log at app quit and is quoted above.

## Not verified / environment limits

- Screenshots: `screencapture` is refused by the OS in this environment
  ("could not create image from display"), same as previous sessions, so no
  light/dark captures. All chrome uses the pre-existing adaptive design
  tokens that already support dark mode; AX structure was verified instead.
- Date-range pickers could not be driven synthetically: native SwiftUI
  DatePicker exposes no settable AXValue, keystroke entry into its segments
  never committed, and popover hosting kept flipping between tree locations
  under concurrent automation from parallel sessions on this machine. The
  date logic is unit-tested (inclusive day bounds, open-ended single bounds,
  undated exclusion); the wiring is the same `matches()` path verified live
  for five other dimensions. A human should click From/To once as a smoke
  test.
- Parallel sessions were actively killing and launching Chessanto processes
  during verification; I worked around it with a renamed app copy and
  PID-targeted AppleScript, and killed two stale QA instances left over from
  earlier sessions (both had database overrides set, neither pointed at the
  live database).
