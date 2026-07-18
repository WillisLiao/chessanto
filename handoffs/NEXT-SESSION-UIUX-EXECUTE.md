# Next session: UI/UX redesign - execution plan

This is an execution plan for a Sonnet session, produced by the planning/audit session on 2026-07-18.
It follows this project's `NEXT-SESSION-M*.md` convention: verified facts up front, fixed design decisions, then numbered steps each with a verification gate.
Every screen and state was screenshotted live in a Release-adjacent Debug build before anything here was written (see "How this was audited").
v1 (M1-M8) is functionally complete per `PLAN.md`; nothing here changes behavior or data - this is a visual and information-architecture pass only.

## The one-line goal

Make Chessanto read as a considered, modern chess analysis app - the polish and purpose of chess.com, natively - instead of stock SwiftUI chrome (`Form`, plain `List`, a segmented `Picker` standing in for navigation).
The board and the coaching are the product; the chrome should recede and let them lead.

## How this was audited (binding for the executing session too)

Do not design from source alone - look at the running app, as the audit did.
The tooling that works (confirmed live this session):

- Build: `xcodegen generate`, then `xcodebuild -scheme Chessanto -configuration Debug -derivedDataPath <dir> build`.
  NNUE nets are already present in `App/Resources/`.
- Launch without stealing focus back to the terminal mid-capture: `open -a Chessanto`.
- Foreground for screenshots/sheets: `osascript -e 'tell application "Chessanto" to activate'` (this triggers a one-time macOS automation-permission dialog the first time; it has already been granted on this machine).
- Screenshot: `screencapture -x <path.png>`, then read the PNG back.
- Read AX tree: `swift scripts/axprobe.swift Chessanto [filter]`.
- Press buttons/menus without focus: `swift scripts/axclick.swift Chessanto <match>`.
- Real clicks at coordinates (needed to hit toolbar-overflow items, sheet buttons, and to focus text fields): `cliclick c:x,y` (logical points; this machine's logical screen is 1440x900, physical 2880x1800, so multiply a screenshot's displayed coords by the displayed-to-1440 ratio).
- Sheets (onboarding, Settings, dashboard, chess.com fetch) do not render while the app is backgrounded - activate first.
- To see onboarding: `sqlite3 <container db> "UPDATE userProfile SET hasCompletedOnboarding=0;"`, force-relaunch (`pkill -9 Chessanto; open -a Chessanto`), screenshot, then restore the flag to 1.
  The container DB is `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.

Screenshot every screen and every state (empty, populated, loading, error) before and after each step; a picture is worth 1000 tokens.

## Verified facts (checked live against the running app this session)

Each of these is a real, reproduced observation, not a guess.

1. **The toolbar overflows into a ">>" popup even at a 1400px window width.**
   `ContentView`'s three sidebar actions (Progress, Fetch from chess.com, Import PGN) are plain unplaced `ToolbarItem`s.
   At the default and even a large window they all collapse behind ">>", so **Import PGN - the single most basic action - is hidden behind an overflow chevron.**
   Confirmed by opening the overflow: it contains exactly those three items.

2. **The move list is a single tall column, not a notation grid.**
   `GameReplayView.MoveListView` renders one `Button` per ply in a `LazyVStack`: white moves get a "N." prefix, black moves are bare, and **every single move carries a full-width classification capsule** (Best/Excellent/Good/Best/...).
   This is nothing like chess.com/Lichess's two-column (White | Black) move table; it is hard to scan and the per-move capsules are visual noise.

3. **The Report tab's classification-count row is visibly broken in the 260-340px pane.**
   Names wrap mid-word ("MagnusCa / rlsen") and the capsules wrap their own text ("Excellen / t", "Inaccura / cy", "Bes / t 20", "Blund / er").
   `GameReportView.classificationRow` lays badges in an `HStack` with no width management inside a narrow column.

4. **Coach markdown renders literally.**
   Chat replies and narrations contain `**e4**`-style bold; `Text(message.content)` shows the raw asterisks.
   Seen live in the Chat tab ("1. **e4** - This is a classic opening move...").

5. **Chat is a third segment of the same `Picker` that shows Moves/Report, so opening chat replaces the move list and report entirely.**
   `RightPaneTab { moves, report, chat }`.
   There is no way to see the move list while chatting, and the position a turn is about is only ever the current board ply (`GameReplayViewModel.chatContext()` follows `currentGraphPly`); the position chip reflects it but is not a control - you cannot pin or pick a position from inside chat.

6. **The eval graph is a raw black/white sparkline.**
   `EvalGraphView` fills a pure-black rectangle with a white area path, a hairline center line, and a thin accent current-ply bar - no move-index sense, no key-moment markers, no hover.

7. **The eval bar is a stark 24px black/white bar** hugging the board with almost no gap, a single caption-size label, a hairline border.

8. **The dashboard accuracy chart looks empty with realistic data.**
   With one user-matched analyzed game it renders a single lone `PointMark` floating at ~75 on an otherwise empty 0-100 chart - reads as broken, not sparse.
   Bare Swift Charts, no styling.

9. **Sidebar rows truncate and show raw data.**
   `GameRow` shows "White vs Black" (truncates constantly: "Hikaru vs gran...", "MagnusCarlse...", "DavidN153 vs...") and a subtitle of `result` + `timeControl` where the time control is the **raw seconds string** ("1-0 180").
   No date, no opening, no win/loss/draw sense, no "analyzed" marker, no sort/search.

10. **Empty states and onboarding all reuse the same generic `checkerboard.rectangle` SF Symbol** and default `ContentUnavailableView` styling.
    Onboarding's welcome page is center-aligned while its other three pages are left-aligned, and there is no page-progress indicator across the four pages.

11. **Minor real paper-cuts:** the Report opening line reads "Left book on move 3. with Nc3." (double period, awkward join); the chess.com fetch footer button reads "Import 0 Games" when nothing is selected (it is disabled, but the label is still wrong); the General settings "chess.com" section header is lowercase next to "Analysis"/"Board".

12. **What already looks good and must be preserved:** the cburnett piece artwork, the three board themes, in-square coordinates, last-move highlight, and flip all render correctly (M8's work).
    The board itself is the strongest thing on screen - the redesign should protect it, not restyle the squares.

13. **Structure that constrains the redesign:** the window is a `NavigationSplitView` (sidebar + detail); the detail is an `HSplitView` (board column `minWidth: 420` | right pane `minWidth: 260, maxWidth: 340`); app min window is 900x600.
    Settings is a `TabView` scene (General + Coach).
    Onboarding, dashboard, and chess.com fetch are `.sheet`s.
    Keyboard: left/right arrows step moves via `.onMoveCommand`.

## Fixed design decisions (use these everywhere - do not re-litigate mid-build)

### A. Information architecture: how chat and analysis coexist (the headline change)

**The right pane stops being a three-way tab switch.**
The board (with eval bar), the move controls, and the eval graph live in the left column and are **always visible - nothing ever covers them.**

- The right pane hosts **Moves** and **Report** only.
  These are the two views *of the game* and belong together; a compact two-item segmented control (or a small header toggle) switches between them.
  Losing sight of the move list to read the report is acceptable; losing it to chat is not.

- **Chat becomes a Coach slide-over panel, not a tab.**
  It is toggled by a single, always-available "Coach" control (a toolbar button in the game view, plus the entry points below).
  When open:
  - At wide widths (the common case - the detail area is roomy), the panel **docks as a third column** on the right: `board | Moves/Report | Coach`.
    The Moves/Report pane stays visible.
  - When there isn't width for three columns, the panel **slides over the Moves/Report pane** from the right edge with a short animation; the **board, eval bar, and eval graph remain fully visible** in the left column the whole time.
  - It is dismissible (a close affordance in its header and `Esc`).

- **Choosing which position a chat turn is about (the explicit ask in the briefing):**
  The panel header carries a **position control**, not a passive label.
  - Default mode: "Asking about the current position" - it follows the board as you scrub (today's behavior, but now clearly stated).
  - **Pin**: a toggle in the header pins the subject to a specific ply ("Asking about 12. Nf3", with a pinned indicator); scrubbing the board no longer changes the chat subject until unpinned.
  - **Entry points that set the subject explicitly:** an "Ask the coach" affordance on a move row (hover/right-click in the move list) and on each Report key moment opens the Coach panel pinned to that ply; a board-level "Ask about this position" button pins the current one.
  - Every message keeps its "at move N" chip (already exists) so history stays legible.

This is the project's signature interaction: the coach is a panel you pull over a never-hidden analysis board and aim at a chosen position - not a screen you switch to and lose your place.

### B. Visual direction (concrete, not vibes)

Native macOS, SwiftUI, light-forward by default with dark supported (the app today only really inhabits dark; the redesign flips the target to light and must still look right in dark - board palettes are fixed by design, chrome must adapt).
No third-party font files; everything below is achievable with system faces and SwiftUI.

**Appearance: light / white-forward is the default (user decision, 2026-07-18).**
Chessanto defaults to a clean, white-forward light look - like chess.com's own site, which defaults to light with green.
Dark mode is still fully supported and must look right, but the **light appearance is the design target** - build and judge it in light first, then verify dark.
Do not let the app inherit whatever the system happens to be set to as its only tested state; exercise both, lead with light.

**Palette - chrome is theme-neutral so the board is the color.**
The board already owns three palettes (walnut/green/blue); the surrounding chrome must not fight them, so the chrome is a light, warm-neutral surface system with **one** confident accent.

- Surfaces (light, primary): `surface-0` app background a soft warm white `#FAF9F6`, `surface-1` `#F2F0EB`, `surface-2` (cards) pure `#FFFFFF`, hairline separators `#E6E1D8`.
  Warm (a hair off pure white) rather than clinical blue-white, to harmonize with the walnut board and read as premium rather than sterile.
- Surfaces (dark, supported): `#1E1C1A` / `#26231F` / `#2E2A25` cards, separators `#3A352F` - warm charcoal, not blue-gray.
- Text: primary `#26231F` (light) / `#F5F1EA` (dark); secondary at ~60% opacity; notation/eval numbers at full strength.
- **Primary accent - brass (user decision, 2026-07-18): no green.**
  A deep gilt `#A6791F` (light) / `#C9A24B` (dark) for selection, primary buttons, the active segment, focus, the accuracy figures, the eval-bar advantage cap, and the "analyzed" marker.
  Grounded in the subject - a fine wooden set and a brass tournament clock, not chess.com's green (the brief's "feel like chess.com" is about polish and purpose, and the user explicitly rejected copying its green).
  Brass is the app's signature; on `light` it must be deep enough (`#A6791F`, not pale gold) to hold contrast against warm white for real interactive controls.
- **Chrome is otherwise near-monochrome warm-neutral** - the board supplies the color, the brass is the one accent, everything else is the warm surface/text tokens above.
  Spend the brass; keep the rest quiet.
- **Move-quality spectrum stays a separate, reserved semantic scale** (never used for chrome): brilliant `#26C1B6` teal, best/excellent `#6F9E4C` green, good `#8C8C8C` neutral, inaccuracy `#E0A93B` amber, mistake `#E0803B` orange, blunder `#D14B4B` red, missed-win `#9B6FD1` purple.
  Refine the existing hexes in `MoveClassificationStyle` toward these for consistent contrast, and **reduce their footprint** (see move-list decision) so they read as accents, not alarms.

**Typography - a real scale, not defaults.**

- Display / titles / section headers: **SF Pro Rounded**, semibold (`.system(..., design: .rounded)`).
  Rounded gives the friendly-modern app voice and separates Chessanto from stock SF; used with restraint (window/sheet titles, section headers, big numbers).
- Body / controls: system **SF Pro Text**, regular/medium.
- Notation, evals, ratings, clocks, coordinates, accuracy numbers: **monospaced** (`.monospacedDigit()` / SF Mono where whole tokens).
  Numbers and moves are data and should read as data - apply this consistently everywhere they appear.
- Scale (points): Title 22 semibold rounded; Sheet/section header 13 semibold rounded with slight tracking; Body 13; Secondary/caption 11; Notation 12 mono.

**Spacing / density / shape.**

- 8pt grid; standard paddings 8/12/16; card corner radius 10; control radius 6-8.
- Group related content into **cards** (`surface-2` with a hairline border) instead of raw `Form`/`List` rows where the utility look is the problem (Report sections, Settings sections, dashboard blocks).
- Section headers are small, tracked, secondary-colored labels - not `Form`'s default heavy section titles.
- Reusable style primitives (define once in the design-tokens file, reuse everywhere): `Card`, `SectionHeader`, `Chip`, `PrimaryButton`, surface/`accent` color tokens, the type scale as `Font` extensions.

**Iconography.**
Keep SF Symbols but choose deliberately and stop reusing `checkerboard.rectangle` for everything.
Empty "select a game" and onboarding-welcome should not share the same glyph.

## What to build, in order

Each step is independently buildable, runnable, and screenshot-verifiable.
Foundational tokens first, then leaf surfaces, then the IA centerpiece last (it depends on the styled pieces existing).
Keep the app runnable at the end of every step (the project's standing rule).

### Step 0 - Preflight
- `xcodegen generate`; Debug build; `swift test` across all packages + `xcodebuild test` green; capture a baseline screenshot of every screen for before/after comparison.
- Back up the container DB to `handoffs/db-backups/` (gitignored) before any onboarding-flag toggling.
- **Gate**: clean build, all existing tests green, baseline screenshots saved.

### Step 1 - Design foundation (App)
- Add a `DesignSystem/` (colors, typography, spacing, shapes) with the tokens and reusable `Card`/`SectionHeader`/`Chip`/button styles from decision B.
- Prove it by restyling one small, low-risk surface end to end (the accuracy summary + one card) in both light and dark.
- No behavior change, no data change.
- **Gate**: builds; the sample surface renders correctly in light and dark; tokens compile and are referenced (not duplicated inline); nothing else visually changed yet.

### Step 2 - Sidebar and game rows (App: `ContentView`/`GameRow`)
- Redesign `GameRow`: readable two-line layout that does not truncate both names to nothing (stack or size names sensibly), a **formatted** time control ("3 min", "Blitz", "Rapid" - derive from the seconds), a win/loss/draw indicator (from the user's perspective when the game is theirs, else the raw result), the date, the opening name if analyzed, and an "analyzed" marker (brass dot or check).
- Style the list toward a considered sidebar (grouping/section, hover, selection using the accent), not a stock `List`.
- Add basic search/filter if cheap; otherwise note it as a follow-up.
- **Gate**: real games render without double-truncation; time control is human-readable; analyzed games are distinguishable at a glance; AX identifiers/labels for rows still resolve.

### Step 3 - Toolbar information architecture (App: `ContentView`/`GameReplayView`/`ChessantoApp`)
- Fix fact 1: the primary actions must never hide behind ">>" at any supported width (900-1400+).
  Options (pick per what actually stops overflowing): give them explicit `placement`; move Import/Fetch to a sidebar-bottom bar or a single "+" menu; keep Progress where it belongs; ensure the game-view analysis controls (quality picker, Analyze/Re-analyze, Starting-engine, flip) don't compete for the same trailing slot.
- Verify the window title isn't crowding the leading space out of the actions.
- **Gate**: at min width (900) and at 1400, no ">>" overflow; every primary action is directly clickable; Import PGN is never buried.

### Step 4 - Board column polish (App: `EvalBarView`, `GameReplayView` controls)
- Restyle the eval bar: rounded, a small deliberate gap from the board, a clearer advantage cap using the brass accent, a monospaced label, smooth animation kept.
  Do **not** touch `BoardView`'s squares/pieces/coordinates - fact 12.
- Restyle the move controls: add first/last (jump to start/end) alongside prev/next, clearer icons, group them into a compact bar; keep the flip button and arrow-key stepping.
- **Gate**: eval bar reads clearly at a glance in both themes; first/last/prev/next/flip all work; arrow keys still step; board rendering unchanged.

### Step 5 - Eval graph (App: `EvalGraphView`)
- Rebuild as a considered evaluation chart: a themed area (not stark black-on-white), a visible baseline, the current-ply marker, small markers at Report key moments (colored by classification), and a hover/scrub readout of the ply and eval.
- Keep scrub-to-jump working and the "series may contain nils" contract.
- **Gate**: graph reads as a designed chart in both themes; scrubbing still jumps to the right ply; key-moment markers line up with the Report's moments.

### Step 6 - Move list as a notation table (App: `GameReplayView.MoveListView`) - also closes an M3 debt
- Rebuild as a **two-column notation table** (move number | White | Black), the standard analysis-board layout.
- Classification stops being a full capsule on every move: show it as a subtle colored dot/underline inline, and reserve a visible chip only for Inaccuracy-and-worse (or on hover) - refine `MoveClassificationStyle` per decision B.
- Selected move highlighted with the accent; click-to-jump preserved.
- Variations: keep the tree, and add **promote / collapse** controls next to the existing delete (this is the still-open M3 debt: only delete exists today) - implement promote/collapse or explicitly defer with a one-line note if the ChessCore API can't support it cheaply.
- Add the "Ask the coach about this move" hover/right-click entry point stub here (wired in Step 11).
- **Gate**: move table scans like chess.com/Lichess; classification is legible but quiet; selection/jump/variation-play/delete all still work; promote/collapse work or are explicitly deferred with reason; AX rows still resolve.

### Step 7 - Report (App: `GameReportView`)
- Fix fact 3 first: the classification-count row must never wrap mid-word or wrap a capsule's text at 260-340px - lay it out so it fits (per-player rows that wrap gracefully to a second line of chips, or a compact grid).
- Card-based sections (Summary, Opening, Key moments, Takeaways, Coach summary) using the design tokens; small tracked section headers.
- Key-moment rows: a real row design with the move (mono), a classification chip, the swing, and the coach/rule-based text - clear hierarchy instead of a wall of colored text; keep them as board-jumping buttons and add the "Ask the coach" entry point (wired in Step 11).
- Fix the opening phrasing ("Left book on move 3 with Nc3." - no double period).
- **Gate**: the count row is intact at the narrowest pane width; report reads as designed cards; key moments still jump the board; coach vs rule-based labeling preserved.

### Step 8 - Settings and onboarding (App: `GeneralSettingsView`, `CoachSettingsView`/`CoachSetupView`, `OnboardingView`)
- Settings: card-styled sections, a **board-theme picker with live colour swatches** (not a bare menu), fix the "chess.com" header casing, tidy the Coach pane so its expanded states (checking/unreachable/model-picker/pull-progress/warnings) don't read as clutter - group them.
- Onboarding: consistent alignment across all four pages, a **page-progress indicator** (four dots), a distinct welcome illustration (stop reusing `checkerboard.rectangle`), and the design tokens throughout.
- **Gate**: Settings and all four onboarding pages render cleanly in light and dark; theme swatches preview real colors; reset-flag E2E still completes onboarding and persists the profile.

### Step 9 - Dashboard (App: `DashboardView`)
- Style the accuracy-trend chart (themed line/area, axis, points) and **handle the one-or-few-points case** so a single game reads as intentional, not broken (e.g. show the point with a value label and a "needs more games" hint rather than a lone dot in space).
- Card-style the mistake-themes and classification blocks; keep the live computation and the coverage line.
- **Gate**: dashboard looks intentional with 1 game and with several; numbers still cross-check against `sqlite3`; both empty states (no username, no analyzed games) render cleanly.

### Step 10 - chess.com fetch (App: `ChessComFetchView`)
- Apply the design tokens; fix the "Import 0 Games" label (hide the count until >0, or read "Import selected"); style the game list rows and the empty/error states.
- **Gate**: fetch flow still fetches, selects, and imports; footer label is never nonsensical; states render cleanly.

### Step 11 - The IA centerpiece: Coach slide-over + position pinning (App: `GameReplayView`, `ChatView`, `GameReplayViewModel`)
- Remove Chat from the `RightPaneTab` `Picker`; reduce the segmented control to Moves/Report (decision A).
- Add the **Coach slide-over panel**: a "Coach" toolbar toggle; dock-as-third-column at wide widths and slide-over-the-right-pane when narrow, always with the board/eval/graph left column visible.
- Header **position control**: default "current position" mode plus a **Pin** toggle that fixes the subject to a ply; wire the "Ask the coach about this move/moment" entry points from Steps 6 and 7 to open the panel pinned to that ply; add a board-level "Ask about this position".
- Adjust `chatContext()` so a pinned ply overrides `currentGraphPly`.
- **Fix fact 4**: render coach markdown (parse `**bold**`/lists into `AttributedString`/`Text`, or strip markup) - no literal asterisks.
- Apply the design tokens to the bubbles, chips, captions, and input bar.
- Persistence, `source` labeling (coach/fallback/precheck), health/offline states, and the FIFO engine serialization all stay exactly as they are - this is presentation + which-ply-context only.
- **Gate (real E2E)**: open the Coach panel and confirm the board, eval bar, eval graph, and (at wide width) the move list stay visible; ask a question about the current position, then Pin a different ply and confirm scrubbing no longer changes the subject and the reply cites the pinned position; use both entry points (a move row and a Report key moment) and confirm they open pinned to the right ply; confirm markdown renders (no `**`); quit/relaunch and confirm chat history persists and jump buttons still work; confirm the coach-disabled and Ollama-offline states still show correct guidance.

### Step 12 - Acceptance pass and wrap-up
- Full walkthrough of every screen in light **and** dark at min (900) and large (1400) widths; screenshot each and compare to the Step 0 baseline.
- All package tests + `xcodebuild test` + `coach-grounding` green (this pass is presentation-only, so behavior tests should be unaffected; if any break, that's a real regression to fix, not to relax).
- Restore the dev DB if any flag/theme was toggled during testing.
- Update `HANDOFF.md` and append the devlog; commit and push docs with the code.

## Known gaps and deliberate exclusions (do not scope-creep)

- **No new features.** This is visual + IA only.
  No new analysis, no new coach behavior, no new persisted data (the pin state is view state, not a DB column, unless a gate proves it must survive relaunch - default to not persisting it).
- **Do not restyle the board squares, pieces, coordinates, or themes** - they are the good part (fact 12).
- **Prose quality of the local LLM is out of scope** (the standing M6/M7 residual risk); rendering its markdown correctly is in scope, improving what it says is not.
- The promotion-picker UI (a separate long-standing M3 gap) is **not** required here; promote/collapse variation controls are in Step 6 only because they're cheap alongside the move-list rebuild - defer with a note if they aren't.
- Light-mode has effectively never been exercised; if it surfaces deeper issues than styling can fix in a step, log them rather than expanding scope mid-step.

## Decisions confirmed at sign-off (2026-07-18)

All settled with the user this session - the plan is signed off and ready to execute:

1. **Appearance:** light / white-forward default; dark supported and verified second.
2. **Accent:** brass/gilt (`#A6791F` light / `#C9A24B` dark), no green; near-monochrome warm-neutral chrome otherwise, board supplies the color.
3. **Coach panel:** dock-as-third-column when the window is wide, slide-over-the-right-pane when narrow; the board/eval/graph left column is never covered.

No code was written this session (the plan's job ends here); a Sonnet session executes the steps above.
</content>
</invoke>
