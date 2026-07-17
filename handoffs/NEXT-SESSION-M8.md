# Next session: M8 - polish and packaging

This is a self-contained execution plan for a fresh session with no prior context.
It was prepared by a 2026-07-18 prep session (the same discipline as M6/M7's prep) that read every file this milestone touches in full, verified the risky claims live (a real 301-second timeout measurement against a frozen Ollama, a raw-AX-API probe of the built Release app, live chess.com API sampling across rating bands, a release-mode ReportBuilder timing run, and the lichess piece-set license file), and resolved every open question from the old bootstrap into fixed decisions.
Follow it step by step; the design decisions are already made, do not re-derive or re-litigate them.
Read `PLAN.md`'s M8 milestone section for product context, but where this file is more specific, this file wins.

The accept criterion (PLAN.md M8): a fresh user can go from first launch to a coached game report in under 5 minutes with no docs; full E2E pass of the flows in `handoffs/HANDOFF.md`.

Two session-level decisions were made with the user during prep and are binding:

1. **The app is licensed GPLv3** (the user chose this explicitly when asked).
   This resolves the Stockfish-GPLv3 question that had been open since M1: the whole app goes GPL, binaries become distributable, and the repo (which currently has NO LICENSE file at all) gets one.
2. **E2E and acceptance testing must use games from every rating band, beginner through pro, not just the GM fixtures** (a direct user request during prep: "training and refining our app based on all elo level matches").
   The user's own chess.com account is `WillisLiao`.
   Verified accounts for every band are pinned in fact 12; the acceptance pass in step 9 exercises all of them.

## Where things stand

M1-M7 are done and pushed to `main` at https://github.com/WillisLiao/chessanto.
The product is functionally complete per PLAN.md's v1 scope; M8 is polish, packaging, and the first-run experience.
PLAN.md's M8 bullets map to today's reality like this:

- "App sandbox enabled with only the entitlements actually needed" - **already done since M1** (fact 1); verify, don't rebuild.
- "Onboarding flow" - does not exist at all (fact 2).
- "Settings window" - exists (`CoachSettingsView` in a real `Settings` scene) but only covers coach settings (fact 3).
- "Analysis quality selector" - exists as a per-window toolbar picker that resets to Standard every time (fact 4); M8 makes it persistent.
- "Light/dark board themes" - nothing exists; the board is hardcoded brown squares with Unicode-glyph placeholder pieces, and three M1-spec board features are also missing or unwired (fact 5).
- "Player improvement dashboard" - does not exist; live compute is confirmed cheap enough (fact 8).
- "Release build script; signing + notarization steps documented in README" - no scripts, no README, no LICENSE (fact 7).

## Verified facts (each checked live or against the real code this prep session)

1. **`App/Resources/Chessanto.entitlements` already contains exactly and only** `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only`, `com.apple.security.network.client`; `project.yml` mirrors them and also carries `NSAllowsLocalNetworking` and hardened runtime.
   M8's sandbox bullet is a verification item, not a build item.

2. **No onboarding exists.**
   `ChessantoApp` -> `ContentView` goes straight to the game list; the only first-run affordance is the "No games yet" empty state.
   `userProfile` (single row, id 1) has exactly `chessComUsername`/`ratingBand`/`coachModel`/`coachEnabled` - there is **no** onboarding-completed flag and **no** analysis-quality or board-theme column, so new persisted settings need a v3 migration (the migrator is append-only by rule; v2 was `chatMessageSource`).
   `GameLibrary.saveChessComUsername` and `ChessComClient.profile(username:)` (404 -> `.notFound`) already exist for username capture/validation.

3. **`CoachSettingsView` (the `Settings` scene, Cmd+,) already covers**: enable toggle, teaching level, Intel warning, no-Ollama guidance + "Check again", installed-model picker with tool-capability badges, hardware-based recommendation (`CoachModelCatalog.recommendation` + `MachineProfile`), free-text pull with progress/retry.
   Reuse these pieces in onboarding; do not duplicate them.

4. **Analysis quality is `@State private var quality: AnalysisQuality = .standard` in `GameReplayView`** - per-window, resets every time, never persisted.
   `AnalysisQuality` (fast/standard/deep = 100/350/2000 ms) lives in `EngineService.swift`.

5. **The board (`BoardView`) has hardcoded square colors, Unicode-glyph pieces, and three dormant M1-spec features**: `lastMove` (highlight logic exists but `GameReplayView` never passes it), `flipped` (parameter exists, no UI sets it), and coordinates (never implemented at all).
   The in-code comment "replaced with proper piece artwork in the M7 polish pass" never happened - M7 shipped chat instead.
   Squares are already real `Button`s with `square-e4`-style AX identifiers; pieces have AX labels ("white knight"); keep all of that intact when reskinning.

6. **cburnett piece artwork is verified available and license-compatible.**
   `https://raw.githubusercontent.com/lichess-org/lila/master/public/piece/cburnett/{w,b}{K,Q,R,B,N,P}.svg` all return HTTP 200 at 400-800 bytes each (12 files, ~7 KB total).
   lila's `COPYING.md` (fetched this session): cburnett = Colin M.L. Burnett, **GPLv2+** - compatible with the GPLv3 app decision.
   Fallback sets if the look is rejected: rhosgfx (CC0), fantasy/spatial/celtic (MIT, Maurizio Monge), chessnut (Apache 2.0).
   Xcode asset catalogs support SVG natively for macOS 10.15+ deployment targets (ours is 14.0).

7. **The repo has no LICENSE, no README, and only two scripts** (`fetch-nnue.sh`, `fetch-eco.sh`; the latter is the committed-output-plus-regeneration-script precedent to follow for piece assets).
   NNUE nets are gitignored and fetched; committed-resource precedent is `eco.json`/`eco-index.json`.
   Dependency licenses for the README table: chesskit-swift MIT, chesskit-engine MIT wrapper vendoring Stockfish 17 GPLv3, GRDB MIT, lichess chess-openings CC0, cburnett pieces GPLv2+.

8. **The dashboard can compute live; measured, not guessed.**
   A release-mode scratch run of `ReportBuilder.build` on the committed 56-ply real fixture: **3.55 ms per game** (plus 24 ms one-time `OpeningBook.shared` load).
   Even 200 analyzed games is under a second, off the main actor.
   Fixed decision: **no rollup table, no new persistence, no `GameReport: Codable`** - recompute on dashboard open.
   Everything needed is already stored: per-ply `AnalysisRecord`s (the same rows `GameReplayViewModel.buildReport()` maps), `GameRecord.whiteRating/blackRating/playedAt/white/black`, and the profile username for user-matching (same case-insensitive match as `userRatingInThisGame`).

9. **`OllamaClient` DOES have a request timeout - 300 s - and it genuinely fires.**
   The M7 handoff's "no request timeout, hangs indefinitely" claim is wrong: `OllamaClient.init` sets `timeoutIntervalForRequest = 300`, and a live probe this session (real `OllamaClient` code compiled standalone, `kill -STOP` on the serving `ollama` process) threw `NSURLErrorDomain -1001 "The request timed out"` at **301.0 s**, after which `kill -CONT` recovered the server cleanly.
   M7's session simply stopped watching at "3+ minutes".
   The real problems, all confirmed in code: (a) 300 s is uselessly long for a chat turn or a health check - a frozen server means the settings pane spins on "Checking Ollama..." for 5 minutes; (b) `URLError.timedOut` is not mapped to any `OllamaClientError` case (only `cannotConnectToHost`/`networkConnectionLost` are), so it propagates raw - `CoachChat`/`CoachNarrator`'s catch-all still falls back, but health-check code paths treat it as generic failure; (c) the `init` clobbers an injected `sessionConfiguration`'s timeout unconditionally, so callers cannot shorten it.

10. **The M5/M7 accessibility gap is RESOLVED - it was the measurement tool, not the app.**
    A raw-AX-API probe (a ~40-line Swift tool using `AXUIElementCopyAttributeValue`, run against the live Release app) shows every "missing" label present in `AXDescription`:
    chat rows expose "You:/Coach: <full message text>", report key moments expose "Key moment, move 9..., cxd5. Drops winning chances from 45% to 35%. Better was Qe7...", and the lines-panel adopt buttons (unconfirmed since M3) expose "+0.3, e4 e5 Nf3 Nc6 d4 exd4".
    The System Events AppleScript bridge (`name of` / `description of` / `accessibility description`) cannot read these SwiftUI-provided `AXDescription`s; that is the whole gap.
    **No app code change is needed.**
    Fixed decision: commit the probe as `scripts/axprobe.swift` and use it (not AppleScript name queries) for all E2E text assertions from now on.

11. **The app can restore with zero windows.**
    Observed live: launching the Release app after it was last quit window-closed gives a running process with an empty `AXWindows` array; only re-`open`ing (Dock-click equivalent) restores the window.
    `CommandGroup(replacing: .newItem)` removed the New Window menu item, so there is no in-app recovery.
    Small M8 fix: add the Import command *without* replacing `.newItem` (or otherwise restore a New Window path).

12. **Mixed-ELO test accounts, all verified live against the chess.com public API this session** (per the user's binding request; ratings are current as of 2026-07-18 and drift, so re-check `/stats` before relying on exact numbers):

    | Band | Account | Verified detail |
    |---|---|---|
    | ~150-500 (the user) | `WillisLiao` | blitz 231 / rapid 307 / daily 906; latest archives 2026/02 + 2026/03 (3+ games, opponents 243-285) |
    | ~600-1000 | `shivam2611` | blitz ~750, active; opponents 648-949 |
    | ~1100-1300 | `shivam2611`'s 2024/12 archive | 5 rapid games at 1160-1217 (e.g. vs `Ali2224343` 1217, `Amirmhdp` 1189) |
    | ~1800-2400 | `2026henryhe` (1819), `21osakat` (1972/1759), `jopebouzy` (2078), `19andi73` (2241) | sampled from `/pub/titled/CM` |
    | ~2500+ | `07kappa` | blitz 2533 / rapid 2385 |
    | GM/pro | existing fixtures | `MagnusCarlsen vs artin10862` (analyzed, in the dev DB), `Hikaru` games |

    `ChessComClient.recentGames` takes `archives.suffix(2)` of the *existing* archive list (not calendar months), so the fetch view works for accounts idle for a few months (WillisLiao's 2026/03 archive is reachable).
    But it can NOT reach `shivam2611`'s 2024/12 rapid archive - import those via the PGN path (curl the archive JSON, extract `pgn` fields, import by file/paste), which also exercises offline import.

13. **The dev DB currently has**: 6 games, game 1 (`MagnusCarlsen vs artin10862`) analyzed with 164 rows + 6 chat messages, game 5 (Hikaru) analyzed with 238 rows, and `userProfile` = (`hikaru`, adaptive, qwen3:0.6b, enabled).
    Onboarding/fresh-user E2E needs a clean slate: quit the app and delete `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite` (or the whole container dir).
    Back it up first (`cp` it aside) so the analyzed fixtures can be restored for later steps.

14. **The `-0.0` eval-label quirk lives in `EvalLabel.format`** (AnalysisKit): `String(format: "%+.1f", cp/100)` renders cp -4..-1 as "-0.0".
    Fix by normalizing the rounded value (if it rounds to zero, format as "0.0" with no sign); `AnalysisKit` has an existing test file to extend.

15. **This machine: Apple M1, 16 GB** (M6's verified sysctl facts still hold); Ollama 0.31.2 serving with `qwen3:0.6b` installed (the dev/harness model).

## Fixed design decisions (use them everywhere)

### v3 migration (one migration, all M8 columns)

`v3_m8Settings`, append-only after v2, `ALTER TABLE userProfile ADD COLUMN`:

- `hasCompletedOnboarding` BOOLEAN NOT NULL DEFAULT 0 (fresh DB = fresh onboarding, exactly the right semantics; the M4 decision to prefer `userProfile` over `UserDefaults` carries over),
- `analysisQuality` TEXT NOT NULL DEFAULT 'standard' (raw value of `AnalysisQuality`),
- `boardTheme` TEXT NOT NULL DEFAULT 'classic'.

`UserProfileRecord` gains the three fields with matching defaults.
Existing users (this dev machine) get `hasCompletedOnboarding = 0` and will see onboarding once after updating; that is acceptable and even useful (it E2E-tests the migration path).

### Onboarding (a one-time flow, separate from Settings)

- A sheet presented from `ContentView` on appear when `hasCompletedOnboarding` is false; `CoachSettingsView` stays exactly where it is as the ongoing settings surface.
- Pages, in order, every control a real native control, every page skippable:
  1. **Welcome**: one screen, what the app does (import, analyze locally, coached report), a "Get started" button.
  2. **chess.com username** (optional): text field + "Check" button validating via `ChessComClient.profile` (404 -> inline "no such account" note, not a blocking alert); saves via the existing `GameLibrary.saveChessComUsername`; "Skip" leaves it empty (PGN-only users are first-class, PLAN.md).
  3. **Rating band**: the four existing `ratingBand` values with one-line descriptions; default adaptive.
  4. **Coach** (the PLAN.md "hardware detection + model picker" page): `MachineProfile` + `CoachModelCatalog.recommendation` drive a recommendation line; states for Intel (default-off warning), Ollama-unreachable (install guidance, coach stays off, "you can enable it later in Settings"), and reachable (enable toggle + model choice + optional pull-with-progress, reusing the settings pane's components - extract shared subviews from `CoachSettingsView` rather than copying).
- Finishing (or skipping out of) the flow sets `hasCompletedOnboarding = true`; onboarding never reappears.
- Import/fetch stays in the main window (the empty-state already points at it); onboarding does not import games itself - it ends on a "Fetch your games or drop in a PGN" pointer so the under-5-minute path flows straight into the existing UI.

### Settings window growth

- `Settings` scene becomes a `TabView`: **General** (new) + **Coach** (`CoachSettingsView` unchanged).
- General tab: analysis quality default (Picker over `AnalysisQuality`), board theme picker, chess.com username field (edit + revalidate; single source of truth is still `userProfile` via `GameLibrary`).
- `GameReplayView`'s toolbar quality picker initializes from the profile and **writes back on change** (last-used-is-default; one setting, two surfaces, no divergence).

### Board themes and real piece artwork

- **Pieces**: cburnett SVGs in a new `App/Resources/Pieces.xcassets` (12 image sets, template rendering off), committed; a new `scripts/fetch-pieces.sh` (fetch-eco.sh precedent: committed output, script exists for regeneration) downloads from the pinned lila URLs.
  `PieceView` renders `Image("cburnett-wK")`-style assets scaled to the square; keep the existing per-piece `accessibilityLabel`.
  Attribution (author, GPLv2+, source URL) goes in the README dependency table.
- **Square themes**: a `BoardTheme` enum (App layer) with three palettes: `classic` (the current brown), `green` (chess.com-like), `blue`; each defines light/dark square colors plus the highlight tints.
  Persisted in `userProfile.boardTheme`; applied via `BoardView` init parameter.
  Board colors are theme-defined constants (a chess board is not system-appearance-inverted); verify legibility of coordinates/highlights in both system appearances.
- **Close the M1 board debts** (fact 5): draw file/rank coordinates (small labels along the edges, colored per-theme), add a board-flip toolbar button feeding `flipped`, and pass the last move from `GameReplayViewModel` (derive from `currentIndex`'s move detail; nil at the start position) so `lastMove` highlighting finally works.

### Player improvement dashboard (v1-simple, PLAN.md wording is the scope cap)

- A "Progress" toolbar button in the sidebar opens a sheet (same presentation pattern as `ChessComFetchView`).
- On open, compute async off the main actor: for every game with complete analysis rows, build `ReportInput` -> `ReportBuilder.build` (fact 8: 3.55 ms/game; reuse the exact mapping `buildReport()` uses - extract it into a shared helper rather than duplicating).
- Content, exactly PLAN.md's two items plus an honesty line:
  1. **Accuracy trend**: the user's per-game accuracy (the side matching `chessComUsername`) over `playedAt`, as a Swift Charts line/point chart (macOS 14 target allows Charts); y-axis 0-100.
  2. **Most frequent mistake themes**: aggregate over the user's key moments across games - counts of punishment ("left a piece en prise"), missed mate, allowed mate, and classification totals (blunders/mistakes/inaccuracies), rendered with the existing `ClassificationBadge`/color vocabulary.
  3. A coverage line: "N of M imported games analyzed (user-matched: K)".
- Empty states: no username set (point at Settings/onboarding), no analyzed user games (point at Analyze).
- Games whose players don't match the username contribute nothing to the user series (no guessing which side the user was).

### Ollama client robustness (the fact-9 fix)

- `OllamaClient.init` stops clobbering injected configurations: the 300 s default applies only when no `sessionConfiguration` is passed.
- Differentiated per-request timeouts via `URLRequest.timeoutInterval`: quick probes (`version`, `installedModels`, `loadedModels`, `capabilities`) **5 s**; `chat` **120 s** (idle timeout between chunks; model load on modest hardware can exceed 60 s, fact 7 of the M6 plan); `pull` stays long (300 s idle; huge downloads resume anyway).
- Map `URLError.timedOut` into a new `OllamaClientError.timedOut` case alongside `notReachable`; `CoachService.checkHealth` treats it as `.unreachable`.
- `CoachChat`/`CoachNarrator` need no behavior change (their catch-alls already produce the connection fallback); the win is bounded latency: a frozen Ollama now degrades a chat turn in ~2 minutes instead of 5+, and a health check in 5 seconds instead of 5 minutes.
- Do not build retry logic or reachability monitoring; the existing on-demand health check plus these timeouts is the whole design.

### GPLv3 packaging (the user's binding decision)

- `LICENSE`: the full GPLv3 text.
- `README.md` at the repo root: what Chessanto is, screenshots later (not this milestone), build instructions (`xcodegen generate`, `scripts/fetch-nnue.sh`, open/build - and that Xcode/xcodegen are prerequisites), the dependency/license table (fact 7 + cburnett), the license statement, and the release/signing section below.
- `scripts/release-build.sh`: `xcodegen generate` + `xcodebuild -scheme Chessanto -configuration Release` producing an unsigned Release .app path printed at the end; **signing/notarization are documented README steps for the user to run with their own Developer ID** (`codesign`/`notarytool`/`stapler` command sequences written out), never run by the script by default, and unsigned local builds must keep working (PLAN.md).
- Session hygiene: never run the user's signing identities; the script's gate is that a clean-ish checkout produces a launchable unsigned Release build.

### Empty/error/progress-state audit (a checklist pass, mostly verification)

Already verified good this session: `ContentView` "No games yet" + "Select a game", fetch-view pre-fetch/no-games/error states, report tab's not-analyzed/analyzing/parse-failed states, chat offline/guidance states, "Starting engine..." toolbar state, import error alerts.
To fix or add: the zero-window restore path (fact 11 - stop replacing `.newItem`), the `-0.0` label (fact 14), dashboard empty states (above), onboarding skip paths, and anything else the walk-through turns up (be picky per the house rule; fix small paper cuts on sight).

### E2E method upgrades (binding for this and future sessions)

- Commit `scripts/axprobe.swift` (fact 10's tool, generalized: dump role/identifier/AXDescription for a named app's window tree, plus a filter argument) and use it for all text-exposure assertions.
- AppleScript System Events remains the driver for clicks/keyboard (it works fine for actions); axprobe replaces it for reading.
- The mixed-ELO game set (fact 12) is the acceptance data; the GM-only habit ends here.

## What to build, in order

Each step ends with a verification gate; do not continue past a failing gate.

### Step 0 - Preflight

1. `scripts/fetch-nnue.sh` (no-op if nets present), `xcodegen generate`, app builds.
2. `swift test` green in Persistence, CoachKit, AnalysisKit, ChessCore; `xcodebuild test` green.
3. `curl -s http://127.0.0.1:11434/api/version` answers; `qwen3:0.6b` still in `/api/tags`.
4. Back up the dev DB (fact 13) before anything touches it.

### Step 1 - v3 migration + profile fields (Persistence)

- The migration and `UserProfileRecord` fields per the fixed decision.
- Tests: migration applies on a v2-shaped store, defaults correct, round-trip of all three new fields.
- **Gate**: `swift test --package-path Packages/Persistence` green; opening the existing dev DB (a copy!) migrates cleanly with data intact.

### Step 2 - OllamaClient timeouts (CoachKit)

- Per the robustness decision: no-clobber init, per-request timeouts, `.timedOut` mapping, `checkHealth` handling.
- Unit tests: error mapping (`URLProtocol` stub throwing `URLError(.timedOut)`), config-injection respected.
- **Gate**: CoachKit tests green; live probe - `kill -STOP` the serving `ollama` process, `version()` fails in ~5 s and a chat turn in ~120 s, `kill -CONT` recovers, `coach-grounding` still exits 0 afterwards.
  (The prep session's standalone probe pattern: compile `OllamaClient.swift`+`OllamaModels.swift`+a main against the frozen server; 301.0 s was the measured baseline.)

### Step 3 - Board: pieces, themes, M1 debts (App)

- `scripts/fetch-pieces.sh` + committed `Pieces.xcassets`, `PieceView` renders assets, `BoardTheme` palettes, coordinates, flip button, `lastMove` wiring, per the fixed decisions; `xcodegen generate`.
- **Gate**: build + run; axprobe shows square/piece AX structure unchanged (identifiers/labels intact); a unit test asserts all 12 asset names resolve to non-nil images; flip/coordinates/last-move-highlight drivable and visible in a Release run; theme switching (via Settings once step 4 lands, via DB write before that) changes square colors live.

### Step 4 - Settings window: General tab (App)

- Tabbed Settings, quality-default + board-theme + username fields, toolbar-picker persistence wiring, per the fixed decisions.
- **Gate**: Release run - change quality default, relaunch, the toolbar picker shows the persisted value; theme picker restyles the board immediately; username edit revalidates and persists (check the DB row).

### Step 5 - Onboarding flow (App)

- The four-page flow per the fixed decisions, driven by `hasCompletedOnboarding`.
- **Gate (fresh-slate E2E)**: wipe the container DB (backup exists from step 0), Release launch -> onboarding appears; AX-drive the full flow with username `WillisLiao` (real validation round-trip), band adaptive, coach enabled with `qwen3:0.6b`; profile row has all values + flag set; relaunch skips onboarding; a second wipe + "skip everything" run also lands in a working app with the flag set.

### Step 6 - Player improvement dashboard (App)

- Per the fixed decisions.
- **Gate**: with the mixed-ELO set imported and analyzed (step 9 data can be front-loaded here), the dashboard renders the user trend + theme counts; cross-check every displayed number against the per-game report tabs and `sqlite3` (the M5 zero-false-statement discipline applies to aggregate claims too); both empty states render on a fresh DB.

### Step 7 - Audit fixes (App/AnalysisKit)

- `-0.0` fix + test, `.newItem` un-replacement, the state-checklist walk, paper cuts found along the way.
- **Gate**: `EvalLabel` tests green including the new case; close-window-quit-relaunch now has an in-app window recovery path; every checklist state visited in a Release run.

### Step 8 - LICENSE, README, release script

- Per the GPLv3 packaging decision.
- **Gate**: `scripts/release-build.sh` from a clean `DerivedData` produces an unsigned Release .app that launches and passes a smoke check (import a PGN, board renders with real pieces); README build steps are followed literally in a scratch clone to catch missing prerequisites; signing steps are proofread against Apple's current `notarytool` flow but NOT executed.

### Step 9 - Acceptance pass (PLAN.md M8 criterion + the mixed-ELO mandate)

1. **The 5-minute fresh-user run, actually timed**: wipe the container, Release launch, stopwatch from first frame: onboarding (username `WillisLiao`) -> fetch view -> import a recent WillisLiao game -> Analyze (Standard) -> open the coached report.
   Under 5 minutes with no docs, timed for real, coach narration included (qwen3:0.6b is fast; note if a bigger model would breach the budget).
2. **Mixed-ELO sweep** (fact 12's table): import via fetch (`WillisLiao`, `shivam2611`, one CM, `07kappa`) and via PGN (the 2024/12 rapid archive games); analyze one game per band; read each report end to end - key moments, register-appropriate prose (beginner register must fire for WillisLiao's games via the adaptive path), zero false statements spot-checked at every band (blunder-heavy low-ELO games stress the key-moment cap; verify the 8-moment cap and "you"-addressing behave).
3. Dashboard over the full mixed set; numbers re-verified.
4. Chat + narration still work end to end on a low-ELO game (not just the GM fixture); illegal-proposal, legal-proposal, and offline behaviors unchanged.
5. Ollama freeze/kill: health check fails fast (~5 s), chat turn degrades in ~120 s, recovery via "Check again".
6. Full `handoffs/HANDOFF.md` flow pass (import/replay/analyze/explore/fetch/report/coach/chat) on the Release build; axprobe for all text assertions.
7. `coach-grounding` exits 0; every package's `swift test` and `xcodebuild test` green.

### Step 10 - Wrap up

Update `handoffs/HANDOFF.md` (M8 done - v1 complete per PLAN.md; future directions live in HANDOFF already), append to `devlogs/<date>.md`, decide with the user what (if anything) comes after v1, commit and push code + docs together.

## Known gaps and deliberate exclusions (do not scope-creep into these)

- M3's promote/collapse variation controls and the promotion-picker UI: still absent, still out of M8's PLAN.md scope; note, don't build.
- chesskit-swift's `invalidMove("Rb5")` parse failure on one imported game: upstream parser edge case, degrades via the existing load-error alert; out of scope.
- Open-question tool-calling with tiny models, and prose quality below frontier models: documented M6/M7 residual risk, explicitly not fixable by M8 prompt tweaks (PLAN.md scopes coaching-quality work out of M8).
- "Starting engine..." state can't be caught live in Release (engine starts too fast); code-inspect only.
- Screenshots/pixel clicks remain blocked in this sandbox; AX-element actions + axprobe reads are the E2E method.

## Working style notes (carried forward; they keep paying off)

- Verify live before coding: this prep session overturned two carried-forward "facts" (the 300 s timeout exists and fires; the AX gap was the AppleScript bridge, not the app) purely by measuring instead of trusting handoff claims.
- Real E2E through the built app via `osascript`/System Events for actions, `scripts/axprobe.swift` for reads.
- Any new interactive UI must be real `Button`s/native controls.
- After adding/removing files under `App/`, rerun `xcodegen generate`.
- Debug on stderr, never stdout (the engine hijacks stdout); Release builds for anything timing-sensitive.
- The sandboxed DB for E2E checks: `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
- Commit and push milestone work together with updated handoffs and a dated devlog entry.
- Never add an agent co-author line to commits; plain dashes, not em dashes, in all docs.
