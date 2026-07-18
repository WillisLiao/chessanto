# Next session: UI/UX audit and redesign plan (planning only, no code)

This is a briefing for a planning session, not an execution plan.
Chessanto's v1 (M1-M8) shipped and is functionally complete per `PLAN.md`, but the UI/UX is rough.
Your job this session is to audit the whole app and produce a redesign plan.
**Do not implement anything.**
The output of this session is a plan document another session (running Sonnet) will execute later.

## Why this session exists

The app works correctly end to end (import, analyze, explore, coach, chat, dashboard - see
`handoffs/HANDOFF.md` for the full feature history) but it visually and structurally reads as
default SwiftUI chrome (`Form`, plain `List`, a segmented `Picker` for tab-switching) rather than
something considered.
The user wants it to feel like chess.com: polished, purposeful, modern - not a stock Mac utility.

## Known problems (don't stop here - find more)

- The Coach settings area (`CoachSettingsView`, `CoachSetupView`) feels cluttered.
- Chat (`ChatView`) is unintuitive - there is no way to choose *which move/position* you're
  asking about before or during a chat turn. Right now it silently follows whatever ply is
  currently displayed on the board (see `GameReplayViewModel.chatContext()` /
  `chatPositionLabel`); a user has no explicit way to pin or change that from inside the chat UI
  itself.
- `GameReplayView`'s right pane is Moves / Report / Chat behind a segmented `Picker`
  (`RightPaneTab` enum). This is structurally wrong: chat should be something you open and close
  on top of the analysis (a slide-over / overlay panel), while the board, eval bar, and move list
  should always stay visible and never get replaced by switching tabs.
- Audit everything else too: `OnboardingView`'s four pages, the game list sidebar (`ContentView`
  / `GameRow`), the board itself (`BoardView`, `BoardTheme`), `GeneralSettingsView`,
  `DashboardView`, every alert and empty state (`ContentUnavailableView` usages), the toolbar
  (note it already overflows into a "more toolbar items" popup at normal window widths - a real,
  observed problem, not hypothetical).

## How to actually see the app (binding for this session)

Do not design from reading SwiftUI source and imagining how it renders. Look at the real thing.

1. **Build and run it.** `xcodegen generate`, then `xcodebuild -scheme Chessanto -configuration
   Debug build`, or open `Chessanto.xcodeproj` in Xcode. `scripts/fetch-nnue.sh` first if the
   NNUE nets aren't present.
2. **Read state without stealing focus**: `swift scripts/axprobe.swift Chessanto [filter]` dumps
   role/identifier/description/value/enabled/size for the whole AX tree - safe to run anytime,
   the app does not need to be frontmost.
3. **Click/press without stealing focus**: `swift scripts/axclick.swift Chessanto <match>`
   presses a button/menu item via `AXUIElementPerformAction` - also frontmost-agnostic.
4. **Real screenshots now work** (fixed this session - Screen Recording permission is granted
   for the terminal host app). Before every screenshot:
   ```sh
   osascript -e 'tell application "Chessanto" to activate'
   sleep 1
   screencapture -x /tmp/whatever.png
   ```
   Then read the PNG back with the Read tool to actually look at it. **Always `activate` right
   before capturing** - a stray AppleScript click or a background command can silently steal
   focus back to the terminal, and you'll screenshot the terminal instead of the app with no
   error to warn you (this happened live last session).
5. **Text entry** (if you need to drive a text field - e.g. onboarding's username page) does
   *not* work via `AXUIElementSetAttributeValue` (looks like it works - `axprobe` will even echo
   the new value back - but it does not drive SwiftUI's real `@State` binding; confirmed
   empirically last session, see `scripts/axsettext.swift`'s doc comment and today's - well,
   last session's - devlog). What actually works: a real `CGEvent` click via
   `swift scripts/axclickat.swift Chessanto <match> AXTextField` to hand the field real keyboard
   focus, immediately followed by `osascript -e 'tell application "System Events" to keystroke
   "..."'`. Always confirm the app is frontmost before any `keystroke` call - it is a blind,
   global keyboard event that goes wherever focus actually is, and it has landed in the wrong
   place before (also last session, also in the devlog).
6. Sheets (onboarding, Settings, the dashboard, the chess.com fetch view) **do not render at all**
   while the app is backgrounded - confirmed by polling a non-activated process for several
   seconds with zero `AXSheet` elements ever appearing. Activate the app first for anything
   sheet-based.

Screenshot every screen and every state (empty, loading, error, populated) before proposing
anything about it.

## What to read first

- `PLAN.md` - the original product scope and architecture.
- `handoffs/HANDOFF.md` - the full "what exists and why" history, milestone by milestone.
- Today's devlog (`devlogs/2026-07-18.md`, the "M8 execution" section and the E2E-tooling lesson
  at the end) for the screenshot/AX-tooling details above in their original context.

## Load before proposing anything

The `frontend-design` skill, for aesthetic direction - color, typography, spacing, and what
makes a native app feel intentional rather than templated.

## What this session should produce

A written plan, saved as `handoffs/NEXT-SESSION-UIUX-EXECUTE.md` (or similar - follow this
project's `handoffs/NEXT-SESSION-*.md` convention, see any of the M2-M8 files for the expected
shape: verified facts, fixed design decisions, staged steps each with a verification gate).
It should cover at minimum:

1. **Information architecture**: concretely how chat and analysis coexist without tabs - what
   triggers the chat panel open/closed, where it lives spatially, how the board/eval/moves stay
   visible underneath or alongside it, and how a user picks which move/position a chat turn is
   about.
2. **Visual direction**: a concrete answer, not vibes - actual colors, typography choices,
   spacing/density rules, what changes about the board/sidebar/panels to move away from default
   `Form`/`List` styling toward something chess.com-like.
3. **Every other unintuitive spot found during the audit**, each with a proposed fix.
4. **A prioritized, staged list of changes** a future Sonnet session can execute against, each
   stage small enough to verify independently (this project's established pattern - see any
   `NEXT-SESSION-M*.md` for the shape: fixed decisions up front, then numbered steps with gates).

**Get the user's sign-off on the plan before any code is written** - this session's job ends at
the plan, not the implementation.
