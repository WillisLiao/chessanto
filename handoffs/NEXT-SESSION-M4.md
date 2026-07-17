# Next session: M4 - chess.com fetch

This is a bootstrap, not a fully de-risked execution plan like M2's -
read it, then re-derive the details from the current code and `PLAN.md`
rather than treating every line here as fixed.

## Where things stand

M1, M2, and M3 are done and pushed to `main` at
https://github.com/WillisLiao/chessanto.
The app imports/persists/replays PGNs, runs real Stockfish analysis with
move classification and accuracy, and supports full Exploration Mode:
free variation play on the board (click-to-move), a variation tree move
list (delete-subtree, "back to game"), engine lines adoption, and live
eval tracking on any explored position - all persisted incrementally and
reconstructed correctly on relaunch.

Read `handoffs/HANDOFF.md`'s current-state section and `PLAN.md`'s M4
bullet before starting:

> ChessComKit with the archive flow above; username stored in settings.
> Game browser UI for fetched games with multi-select import.
> **Accept:** enter a real username, fetch, import 5 games, analyze one;
> airplane-mode launch still works fully for PGN import and analysis.

## What already exists to build on

- `Packages/ChessComKit/Sources/ChessComKit/ChessComClient.swift`: a
  working, unauthenticated chess.com API client - `profile(username:)`,
  `archiveURLs(username:)`, `games(archiveURL:)`,
  `recentGames(username:monthCount:)`. Sets a descriptive `User-Agent` per
  PLAN.md. This was written ahead of schedule (M1/M2 prep) and is
  currently **unused by the app** - it has one placeholder test
  (`ChessComKitTests`) and needs real coverage (fixture JSON per the
  Testing strategy section of PLAN.md) plus a live smoke check against
  the real API before trusting it end-to-end.
- `Packages/Persistence/Sources/Persistence/GameStore.swift`:
  `importedSourceURLs()` already exists (returns the set of
  `sourceURL`s already imported) - this is exactly the "fetch new games"
  de-dup mechanism PLAN.md asks for; `GameLibrary.alreadyImported(sourceURLs:)`
  in `App/Sources/Chessanto/GameLibrary.swift` already wraps it but isn't
  called from any UI yet.
- `GameLibrary.importPGN(_:source:sourceURL:)` already accepts a
  `GameSource` (`.chessCom` or `.pgnImport`) and a `sourceURL` - the
  import path this milestone needs already exists, it just needs a chess.com
  game's PGN string handed to it with `source: .chessCom, sourceURL: game.url`.
- No settings/preferences storage exists yet anywhere in the app (no
  `UserDefaults` usage, no settings window). The chess.com username needs
  somewhere to live - simplest is `UserDefaults` for now (a dedicated
  `userProfile` table already exists in `Schema.swift` with a
  `chessComUsername` column and `Persistence` has no reader/writer for it
  yet either - decide which one to use and don't build both).

## Suggested approach (re-derive, don't just follow)

1. Give `ChessComClient` real test coverage first: decode fixture JSON
   (a real archive response saved as a test resource) for `ChessComGame`/
   `ChessComPlayer`, and a live check (a small `chesscom-smoke` executable
   mirroring EngineKit's `engine-smoke` pattern, or just a manual
   `swift run`/curl session) against a real public username before
   wiring it into the UI - don't debug API-shape surprises through SwiftUI.
2. Decide and build the settings storage for the chess.com username
   (`UserDefaults` vs. the existing `userProfile` table) - keep it simple,
   this is a single string for v1.
3. Game browser UI: a new view (sheet or separate pane) that, given a
   username, calls `recentGames` (or paginates by archive - check what a
   real account with many games actually returns before deciding), shows
   each game's players/result/date/time-control, marks already-imported
   ones (via `alreadyImported(sourceURLs:)`) as disabled/checked, and
   supports multi-select + an Import button that calls
   `GameLibrary.importPGN` per selected game.
4. Wire a "Fetch from chess.com" entry point next to the existing
   "Import PGN" toolbar button in `ContentView.swift`.
5. Airplane-mode requirement: make sure every chess.com-specific failure
   (no network, bad username, chess.com down) degrades to an error message
   without blocking PGN import or analysis - `ChessComError` already models
   the failure cases, just make sure the UI surfaces them via an alert
   (mirroring the existing `loadError`/`analysisError` alert pattern in
   `GameReplayView.swift`) rather than crashing or hanging.

## Working style notes (carried forward, they keep paying off)

- Do real E2E verification through the built app, not just `swift test`.
  Screen Recording wasn't available in this environment across M2 and M3;
  the `osascript`/System Events accessibility-introspection method
  (`entire contents of window`, then AX-element-reference `click item N
  of buttons of ...`) works, but **raw pixel-coordinate clicks
  (`cliclick`, or System Events' `click at {x,y}`) are blocked in this
  sandbox** - only clicking an actual AX element reference works. This
  means every interactive control needs to be a real `Button` (or
  something else that exposes an `AXButton`/actionable role) - a bare
  `.onTapGesture` is both unautomatable here and a real VoiceOver gap, as
  M3 found the hard way with the board squares. Check new interactive
  UI (the game browser's row selection, import checkboxes) exposes proper
  AX roles before relying on it being clickable in verification.
- After adding/removing files in `App/`, rerun `xcodegen generate` (the
  `.xcodeproj` is gitignored).
- Commit and push milestone work together with updated handoffs and a
  dated devlog entry.

## Known gaps carried over from M3 (not this milestone's job, but don't be surprised)

- No promote/collapse variation controls (only delete, back-to-game).
- No promotion picker (auto-promotes to queen).
- Replaying a variation move identical to the real mainline continuation
  creates a redundant variation branch instead of being recognized as the
  mainline (chesskit `Move` equality quirk) - see the 2026-07-17 devlog.
- `LinesPanelView`'s adopt-line buttons' accessibility exposure is
  unconfirmed - re-verify if you touch that view.
