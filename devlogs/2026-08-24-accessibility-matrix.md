# 2026-08-24 - Accessibility UI-test matrix

Session prompt: `handoffs/NEXT-SESSION-ACCESSIBILITY-MATRIX.md`.
Branch: `feature/accessibility-matrix` (worktree `../chessanto-accessibility-matrix`, cut from `main`).
Scope: the macOS app only; the iPhone companion was not touched.

This session overrides PLAN.md's "a dedicated accessibility UI-test matrix"
out-of-scope decision, as instructed. No other product decision was revisited.

## Method

Every dimension below was audited by reading the view source and then
verified against the running app where the environment allowed. Live
verification used the built Debug app pointed at a disposable copy of the
library database under the documented QA override
(`CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1`,
`CHESSANTO_DATABASE_PATH=~/Library/Containers/com.chessanto.app/Data/tmp/ax-matrix-20260824/chessanto.sqlite`),
inspected with `scripts/axprobe.swift` (raw AX API). The live database was
backed up by hash before any launch and verified byte-identical afterward:
SHA-256 prefix `3ab332c1722e43c2`, `PRAGMA integrity_check` ok, 15 games.

Contrast ratios were computed with a WCAG relative-luminance script against
every surface token in both modes, not estimated by eye.

## The matrix

Screen x dimension. F = finding (fixed this session unless noted), OK =
audited and passing, NA = not applicable.

| Screen / component | VoiceOver | Keyboard | Dynamic Type | Contrast | Reduced motion |
|---|---|---|---|---|---|
| Board (64 squares) | F: labels were bare algebraic; pieces floated as separate image elements - fixed | F: no keyboard-only piece movement - added | OK (square-relative geometry is type-independent) | OK (fixed board palette, decorative coordinates) | OK (arrival slide already skipped it) |
| Board announcements | F: nothing said what changed on a move - added | - | - | - | - |
| Move list (scoresheet) | OK (labels carry spoken SAN + classification + pin state) | F: variation delete button unlabeled - fixed | F: fixed 28/40pt number columns - scaled | OK after classification palette fix | NA |
| Report (Game audit, key moments) | OK (key-moment rows have full labels incl. pinned state) | OK (all actions are real buttons) | OK (scaled fonts) | OK after palette fix | NA |
| Eval bar | OK (label + help text) | NA (display-only) | NA | OK | F: fill animation ignored Reduce Motion - fixed |
| Eval graph | F: drag-scrub strip had no AX identity - added label/value summary | OK (arrow keys scrub plies via Game menu) | NA (chart graphic) | OK | NA |
| Lines panel | OK (rows + adopt buttons labeled) | OK (adopt is a real button) | F: fixed 16pt row heights clipped large text - ScaledMetric | OK | NA |
| Coach panel (ChatView) | OK (mode banners, jump buttons now have explicit labels) | OK (text field, send, escape closes) | OK | OK | F: slide-over transition animated under Reduce Motion - gated |
| Coach stage (comic bubble) | OK (speech buttons labeled; portrait hidden) | OK | OK (message lineLimit(3) is the designed condensed stage) | OK | NA |
| Practice (prompt/feedback/board section) | OK (reply status labeled, hints hidden until earned) | OK (board keyboard nav applies here too) | OK | OK | NA |
| Library sidebar + game rows | F: selection state not exposed on rows/source buttons - added `.isSelected` traits | OK | OK | OK | NA |
| Recently Deleted | OK | OK | OK | OK | NA |
| chess.com fetch sheet | F: per-game select checkboxes were anonymous buttons - labeled with value; fetch button labeled while loading | OK | OK | OK | NA |
| Onboarding | F: teaching-level picker unnamed once its visible label was hidden - named; ad-hoc fixed-size fonts converted to text styles | OK | F: fixed 640x450 frame - now minimums; fixed-width title column now a floor | OK | NA |
| Settings (General/Coach/Companion) | OK (theme swatches labeled, pickers/toggles native) | OK | F: Companion pane fixed 610x650 frame - now minimums | OK | NA |
| Player Brief | OK (chart has summary label; tables combined per row) | OK | F: focus title and metric value used fixed point sizes - converted | OK | NA |
| Dashboard (Progress) | F: trend chart had no AX summary - added | OK | F: fixed 620x470 frame - now minimums; prominent button style swapped | OK | NA |
| Batch analysis bar | OK (native progress semantics) | OK | OK | OK | NA |
| Promotion picker | OK (four choices + cancel scrim all labeled) | OK (Escape cancels; choices are real buttons) | OK | OK | F: hover ring animation - gated |

## Key findings and fixes

### 1. Board VoiceOver semantics (the hard case)

Before: each square button announced only its algebraic address ("e4"), and
the piece images were separate AX elements announcing "white pawn" with no
location and no association to their squares. A VoiceOver user could not
answer "what is on e4" or "what just moved".

After, verified live with axprobe against the running app:

- Pieces are folded into their squares' labels; piece images are removed
  from the AX tree entirely (`piece-` identifier count in the tree: 0):

```
[AXButton] id=square-e7 title= desc=Black pawn e7 value= enabled=true size=53x52
[AXButton] id=square-e2 title= desc=White pawn e2 value= enabled=true size=53x52
[AXButton] id=square-d1 title= desc=White queen d1 value= enabled=true size=53x53
```

- Visual state moved into accessibility values. After an AX-driven
  click-select of the e2 pawn:

```
[AXButton] id=square-e4 title= desc=e4 value=legal destination enabled=true size=53x52
[AXButton] id=square-e3 title= desc=e3 value=legal destination enabled=true size=53x52
[AXButton] id=square-e2 title= desc=White pawn e2 value=selected enabled=true size=53x52
```

- After playing e2-e4 through two AX presses (click-to-move is fully AX
  operable end to end):

```
[AXButton] id=square-e4 title= desc=White pawn e4 value=last move enabled=true size=49x48
[AXButton] id=square-e2 title= desc=e2 value=last move enabled=true size=49x48
```

- Every move posts an `AccessibilityNotification.Announcement`
  ("White pawn e2 to e4") so a VoiceOver user learns what changed without
  re-walking the board. The strings come from the new pure
  `BoardAccessibility` module (`App/Sources/Chessanto/Board/BoardAccessibility.swift`),
  covered by unit tests including flip-aware cursor geometry.

### 2. Keyboard-only piece movement

The board supported click-to-move and drag-and-drop only. Added arrow-key
navigation: the container is `.focusable()`, arrows walk the focused square
via `.onMoveCommand` (flip-aware screen directions), Space/Return press the
focused square through the button's own native action, and a brass ring
shows the cursor. The cursor IS keyboard focus (`@FocusState` bound to all
64 buttons) - my first implementation kept a separate internal cursor, and
the live test caught the split-brain failure: under Full Keyboard Access a
focused square button consumes Space itself while arrows moved only the
internal cursor. Cursor and focus were unified into one thing.

Verification status, honestly stated:

- Verified live: click-to-move plays moves through AX element presses;
  selection/legal-destination/last-move states read correctly (output above).
- Not verifiable in this environment: real key-event delivery. Synthesized
  AX-focus setting and CGEvent key posts never reached SwiftUI's focus
  system here (the same limitation the M8 prep devlog recorded for
  `scripts/axfocus.swift`), and four concurrent Chessanto instances from
  parallel sessions made frontmost-focus attribution unreliable. Two new QA
  scripts shipped anyway for future sessions: `scripts/axkey.swift`
  (synthesized key events) and `scripts/axfocused.swift` (reads the window's
  focused element). Manual check that remains: Tab into the board, arrows to
  a piece, Space, arrows to a destination, Space.

### 3. Contrast (measured, both modes)

Computed WCAG ratios for every foreground token on every surface. Passing
unchanged: textPrimary (11.07-15.64), textSecondary (5.10-6.45),
accentText (6.12-8.76), error light (5.78-6.57), eval-bar labels (21.0).
Real failures found and fixed:

- Classification colors as small text failed AA across the board in light
  mode: best green 2.77, good gray 2.95, inaccuracy 1.86, mistake 2.52,
  blunder 3.83, missed win 3.30, brilliant 1.97 (worst-surface ratios).
  `MoveClassification.color` is now adaptive with measured variants, all at
  4.5:1 or better against the worst surface of their mode (light worst
  surface #F3F0E9: green 4.62, gray 4.68, amber 4.85, orange 4.97, red
  4.72, purple 5.03, teal 4.89; dark worst surface #2D2A26: green 5.14,
  gray 5.20, amber 6.74, orange 4.98, red 4.59, purple 5.14, teal 6.38).
- Dark-mode primary button: white label on the brighter dark brass
  #D4B566 measured 1.98:1. `PrimaryButtonStyle` now flips its label color
  with the background (dark ink on dark-mode brass, 8.76:1). The three
  `.borderedProminent` usages (which hardcode white labels on the brass
  tint: 3.91 light / 2.44 dark) were switched to the app's own primary
  style.
- Dark-mode error token #E55A4F sat below AA on surface1/surface2 (4.45 /
  4.02); brightened to #EB675C (4.99 / 4.51 / 5.48).
- Light-mode `accent` as text (Chip default, coach warnings) is
  AA-large-only (3.43-3.91); actual text usages already route through
  `accentText` (passes), and accent's remaining uses are graphics and fills
  above the 3:1 non-text bar, so the token itself stays.
- Board coordinate labels measure 3.94 - they are decorative, marked
  `accessibilityHidden`, and carry no information the square button does
  not already announce; left as is deliberately.

### 4. Dynamic Type

The design-system fonts were fixed point sizes and never scaled.
`DesignTypography` now builds every font on system text styles
(title2/subheadline/body), which track the macOS text-size setting, keeping
default-size rendering within a point or two of the old values. Ad-hoc
fixed sizes elsewhere (onboarding headings, brief focus title, metric
values, chat/report badges) were converted too. Layout fixes so scaled text
cannot clip: lines-panel row heights via `@ScaledMetric`; move-number
columns via `@ScaledMetric`; onboarding/dashboard/companion panes switched
from fixed frames to minimum frames; the onboarding title column width
became a floor. The dashboard chart gained a VoiceOver summary like the
brief's ("Accuracy across N games, from X percent to Y percent").

### 5. Reduced Motion

The board arrival slide already respected it. Gated the rest:
eval-bar fill/tick animations, the coach slide-over transition, and the
promotion-picker hover ring. Move announcements are speech, not motion, and
post regardless.

## Verification gates (quoted)

```
xcodegen generate            (regenerated after adding BoardAccessibility.swift)
xcodebuild ... build         -> ** BUILD SUCCEEDED **
xcodebuild ... test          -> Test run with 208 tests in 37 suites passed after 2.365 seconds.
                                ** TEST SUCCEEDED **
```

New tests: `App/Tests/ChessantoTests/BoardAccessibilityTests.swift` (8
tests: square labels, value composition, move announcement text,
unflipped/flipped neighbor walks, edge stops, initial cursor).

Live database safety: SHA-256 prefix before first launch and after final
kill identical (`3ab332c1722e43c2...`), integrity_check ok. One anomaly
worth recording: during live QA, Chessanto instances died silently twice
and one instance appeared that I had not launched; empty logs, no crash
reports, and the live database stayed byte-identical throughout. Four
Chessanto processes existed at peak - parallel sessions are launching and
driving "Chessanto" by name, which explains lost windows, stolen
frontmost status, and unreliable key-event delivery during verification.
Nothing in this branch touches process or window management.

## Conflicts with parallel sessions

None hit. All edits are inside views and the design system listed in the
matrix; no Play-vs-Engine, Chess960, or search/filter surfaces were
touched. If another session's branch also edits `DesignTypography.swift`,
`MoveClassificationStyle.swift`, or `BoardView.swift`, expect textual
conflicts - resolve in favor of whichever carries the newer feature work
and re-apply these accessibility properties on top.

## Left open (deliberate)

- One manual keyboard check in a quiet session (see item 2 above).
- The eval graph remains pointer-scrub-only as a control; equivalent
  keyboard paths exist (arrow-key ply stepping, clickable key-moment dots)
  and the strip now exposes a VoiceOver summary.
