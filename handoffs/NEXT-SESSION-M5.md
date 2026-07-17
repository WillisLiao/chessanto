# Next session: M5 - rule-based coaching report

This is a self-contained execution plan for a fresh session with no prior context.
It was prepared by a 2026-07-17 planning session that read all the relevant source (AnalysisKit, Persistence, the replay view model and view, and chesskit-swift's checked-out internals) and verified the risky claims below with a real scratch-package run against ChessCore plus a real download of the opening dataset - the facts are verified, not guessed.
Follow it step by step; the design decisions are already made, do not re-derive or re-litigate them.
Read `PLAN.md`'s "Analysis pipeline" steps 6-7, the "Opening book" section, and the M5 milestone for product context, but where this file is more specific, this file wins.

The accept criterion is unusual and hard: **the report for a spot-checked game reads correctly with zero false statements, and every claim traces to an engine line or board fact.**
The design below makes that enforceable in code (typed Facts, closed templates, an auditor that drops anything it cannot re-verify), not by careful prose writing.
Do not add any report sentence that is not produced by a template over typed Fact fields.

## Where things stand

M1-M4 are done and pushed to `main` at https://github.com/WillisLiao/chessanto.
What M5 builds on:

- **Per-ply engine data is already stored.**
  `analysis` rows per `(gameId, plyIndex, multiPVRank, depth)`: `fen`, `depth`, white-perspective `scoreCentipawns`/`mateIn`, `principalVariation` (space-joined UCI), ranks 1-3 (fewer when the position has fewer legal moves - never force-unwrap ranks 2/3).
  A ply is analyzed iff a rank-1 row exists; a game iff every ply 0..N has one.
- **Classification and accuracy already work** (`AnalysisKit.MoveClassifier`/`Accuracy`/`WinProbability`, derived in `GameReplayViewModel.deriveClassifications` and shown as move-list badges + an accuracy summary).
  M5 reuses these; it does not re-derive different math.
- **There is no `Facts` type anywhere yet.**
  `CoachKit` is an empty placeholder; PLAN.md's coach-verification design depends on structured Facts, and M5 is where they get introduced (in AnalysisKit - M6's CoachKit will consume the same types).
- **The eco.json in AnalysisKit is a 10-entry placeholder** (`Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco.json`, already declared as a `.copy` resource in the manifest since M1, referenced by no code). M5 replaces it with the real dataset (see decisions).
- **Two open bugs from the 2026-07-17 M4 devlog section:**
  1. One real chess.com game fails PGN parse (`chesskit-swift` `invalidMove("Rb5")`), degrading via the existing load-error alert. Not M5's to fix; the report path must simply guard on a parsed game (it already will: the report derives from `GameReplayViewModel`, which sets `loadError` and produces no plies for that game).
  2. The Analyze button silently no-ops when clicked before `EngineService.isStarted` flips true (there is no "engine still starting" toolbar state). This one M5 **does** fix (step 5), because the report flow starts with "analyze the game" and a silently dead button poisons that flow.

## Verified facts (each was checked against source or a live run this session)

1. **Terminal-mate sentinel: `|mateIn| == 99` means "game over", not "mate in 99".**
   For a game ending in `#`, the final ply's record is synthesized: `scoreCentipawns = nil`, `mateIn = ±99`, `principalVariation = ""`, `depth = 0` (`EngineService.analyze`).
   Every mate-related detector must exclude it, and PV-based detectors get an empty PV there anyway.
2. **`ChessGame.sanLine(fromUCI:startingFEN:)` DOES emit `+` and `#`.**
   Verified by scratch run: `["h5f7"]` from the Scholar's-mate FEN renders `["Qxf7#"]`, and a Qh5-check line renders `["Qh5+", "g6"]`.
   The doc comment on `sanLine` claiming SANs "never include +/#" is stale (the SAN comes from `board.move(...)`'s processed `Move`, which sets `checkState`) - fix the comment while in there.
   Still: derive check/mate *facts* from the replayed `Move.checkState`, never by string-matching SAN suffixes.
3. **`Board.legalMoves(forPieceAt:)` works for either color regardless of side to move** (verified: black Ng8 returns `f6`,`h6` in a white-to-move position), and legality accounts for own-king safety.
   But it computes `attacks & ~ownPieces`, so "is my piece defended" is NOT answerable this way - which is why M5's templates make no "undefended"/"defended" claims (see decisions).
4. **The replay primitive works from raw FENs**: `Board(position: Position(fen:)!)` + `board.move(pieceAt:to:)` returns a `Move` carrying `.capture(Piece)` results, `checkState`, and correct SAN (verified: `Nxe5` returned `result=capture(Black Pawn on e5)`).
   `Move`'s public surface also has `piece`, `start`, `end`, `promotedPiece` - everything a `ReplayedMove` facade needs.
5. **Material counting from a FEN works via `Position.pieces`** (verified 39/39 on a real position, values 1/3/3/5/9).
6. **chesskit-generated FENs omit the en-passant square even when an e.p. capture is legal.**
   Verified on both the `playMove` path and the PGN-parse path: after `1. e4 c5 2. e5 d5` the FEN reads `... w KQkq - 0 3` although `exd6` is legal.
   Two consequences:
   - EPD keys for the opening book MUST be produced by replaying book lines through chesskit itself, so both sides of every lookup share the same convention. Do NOT use lichess's precomputed `dist/` EPD column (their convention includes the e.p. square "only if legal" and would mismatch).
   - Pre-existing quirk worth logging (not M5's to fix): stored analysis FENs lack e.p. rights, so Stockfish cannot consider an e.p. capture at such a ply. No false report statements can result (claims trace to the same stored lines), but note it in the devlog as a known chesskit gap.
7. **ECO tags exist in chess.com PGNs but not necessarily in PGN imports.**
   The real-game fixture in `RealGameFixtureTests.swift` has `[ECO "B07"]`, and both games in `Packages/ChessComKit/Tests/ChessComKitTests/Resources/sample-archive.json` carry `ECO`/`ECOUrl`.
   They surface through `ChessGame.tags` (chesskit puts unknown tags in `Tags.other`, and the facade merges them).
   Decision below: the report does not use the tag for claims at all.
8. **The opening dataset is verified**: https://github.com/lichess-org/chess-openings, files `a.tsv`..`e.tsv`, header `eco\tname\tpgn`, 3,803 entries, ~380 KB raw, CC0-1.0 (public domain), deepest line 36 plies, 298 entries contain `+`-suffixed SANs.
   `ChessGame.playMove(san:at:)` replays those `+`-suffixed SANs fine (verified with the `Qh5+` line).
   Raw URLs: `https://raw.githubusercontent.com/lichess-org/chess-openings/master/{a,b,c,d,e}.tsv`.
   Lichess's own stated convention: classify a game by the deepest position that matches a named entry - the same rule fixed below.
9. **`GameReplayViewModel` keeps only rank-1 rows** (`cachedEvaluationsByPly`); the report needs all ranks, so the VM must retain the full per-ply record lists (step 5).
   Alignment convention (unchanged from M2): index 0 of `moveIndices`/`fens` is the starting position, `playedUCIs[p]` is the move that produced position `p` (`nil` at 0), `classifications[p - 1]` classifies move `p`.
10. **`deriveClassifications` infers the mover from ply parity** (`p % 2 == 1` means White).
    Fine for standard games, wrong for FEN-start games; the report builder should read the mover from the FEN's side-to-move field instead, and the auditor should cross-check the two.
11. **"You" detection is possible but optional**: `GameRecord.white/black` hold player names and `userProfile.chessComUsername` is persisted; a case-insensitive match decides whether templates may say "you" (see decisions).
12. **Report UI slot**: `GameReplayView`'s right pane is a `VStack(accuracySummary, MoveListView)` inside an `HSplitView`; the report becomes a second tab of that pane.
13. **Engine facts still apply** (from `NEXT-SESSION-M2.md`): white-perspective values in the DB, single engine instance, stdout hijacked (debug via stderr), Debug-build Stockfish is 5-10x slower.
    M5 needs no new engine work at all - the report is computed purely from stored rows + ChessCore replays.

## Fixed design decisions (use them everywhere)

### The Facts model and the zero-false-statement enforcement

- All new report logic lives in **AnalysisKit** and imports **ChessCore only** (the manifest already declares ChessCore/EngineKit/Persistence deps; keep the code free of the latter two, like M2 did).
  The app maps `AnalysisRecord`s into a plain `ReportInput` value (per ply: `fen`, ranked lines as `(rank, cp, mate, pvUCI: [String], depth)`, `playedUCI`, plus player names/result), so AnalysisKit stays DB-free.
- **Layer 1 - typed Facts.** A closed set of structs (below), each carrying provenance: the ply it's about, the rank and PV-prefix length of any cited line, and only typed fields (squares, piece kinds, SANs produced by ChessCore replay, evals copied from records).
- **Layer 2 - closed templates.** `ReportText` renders each Fact kind with fixed template functions whose every chess-meaningful token interpolates a Fact field.
  No free-composed chess prose anywhere in M5 (that is M6's LLM, behind CoachVerifier).
- **Layer 3 - the FactAuditor.** Before rendering, every Fact is re-verified against the input: cited SANs re-derived from `(fen, uci)` must match exactly; cited lines must be prefixes of the stored PV they reference; evals/percentages must equal the referenced record's value under the fixed formulas; material deltas are recomputed by replay; a cited mate line must actually end in checkmate on replay with length `2N - 1`.
  A Fact that fails audit is dropped from the report (log to stderr in debug); tests assert zero drops on the fixture.
  The auditor ships in AnalysisKit - it is the seed of M6's CoachVerifier.
- **Layer 4 - golden test.** The full pipeline runs over the real fixture game with canned analysis rows (committed JSON from a real Standard-quality run, step 4) and is asserted against a golden report text file.
  Template wording changes must consciously update the golden.

### Detector set for M5 (crisp only; fuzzy ones deferred)

In scope, each with a board-checkable definition:

- `EvalSwingFact` (every key moment): mover's win probability before/after, from rank-1 records via the existing `WinProbability` functions.
- `BetterMoveFact`: rank-1 best move of the pre-move position (first PV move, SAN via replay) plus up to 6 plies of its PV and the pre-move eval.
  The eval claim is honest by construction: the stored eval of position `p-1` *is* the eval assuming that line, so "keeping the evaluation around {label}" is safe.
- `PunishmentFact`: fires when the rank-1 PV of the *post-move* position starts with a capture.
  Fields: refuting SAN, captured piece kind and square, `capturesJustMovedPiece` (PV capture square == played move's destination), and the net material delta at the end of the replayed PV relative to the post-move position.
  Wording rule: "winning the {piece}" only when delta >= value(captured piece); "winning material" when 0 < delta < value; no material clause otherwise (it may be a trade or sacrifice sequence).
- `MissedMateFact`: pre-move record has mate for the mover (`mateIn` sign matches mover, `|mateIn| != 99`) and the post-move record no longer does.
  Two-tier rendering: always "missed a forced mate in {N}"; cite the line only if the replayed PV verifiably ends in checkmate (auditor rule above), else omit the line, never guess.
- `AllowedMateFact`: converse (post-move record shows mate for the opponent, pre-move didn't). Same two-tier line citation.
- `OpeningFact`: name, ECO, deepest in-book ply, and the deviation move (see opening book below).

Explicitly deferred (fuzzy or unverified data, revisit in M6+): fork/pin/skewer geometry, back-rank weakness, time-trouble blunders (clock comments' availability via `Move.comment` is unverified), bad-trade detection, and Brilliant (its enum case stays reserved and never assigned).
No "undefended"/"hanging and undefended" phrasing - defense is not queryable through `legalMoves` (verified fact 3); "left it where it could be taken" + the PV capture is what the templates say instead.

### Key-moment selection (fixed rule)

- Candidates: mainline moves classified `inaccuracy`, `mistake`, `blunder`, or `missedWin`.
- Always include every `blunder` and `missedWin`; rank all candidates by mover win-probability drop; fill to at least 3 (when available) and cap at 8, keeping the largest drops.
- Present chronologically.
- Zero candidates is a legitimate outcome: the key-moments section says so plainly ("No significant mistakes at this analysis depth") - never pad with noise.

### Opening book

- Replace the placeholder eco.json with the full converted dataset: new `scripts/fetch-eco.sh` downloads the 5 TSVs and converts to a single JSON array of `{eco, name, pgn}` (commit the ~500 KB output - it is small and build-time-network-free; the script exists for regeneration).
- `OpeningBook` (AnalysisKit): loads via `Bundle.module`, tokenizes each `pgn` (strip `N.` tokens), replays through `ChessGame.playMove(san:at:)` from the start position, and indexes **the line's final position** by EPD (first 4 FEN fields of the chesskit-generated FEN - consistency guaranteed by verified fact 6).
  Collisions (transpositions): prefer the entry with the longer line, then lexicographically smaller name, deterministically.
  Build the index once per app run, off the main thread, at first report request; ~3.8k short lines should take well under a second - measure, and only if it is actually slow, precompute EPDs into the JSON via the script instead.
- Game matching: scan plies 1..min(N, 40); the opening is the entry at the **deepest** matching ply `d`; the deviation move is ply `d+1` (when the game continues past `d`).
  The resulting claims are exactly auditable: "position after move X is a book position named Y" and "no later position is in the book".
- The PGN `ECO` tag is deliberately **not** used for claims: PGN imports may lack it, and chess.com's naming may disagree with the bundled book - one code path, one source of truth.
  (In step 2's test, log our name next to the fixture's `B07` tag as a sanity signal; do not assert equality.)
- Games with no book match at all (e.g. custom-FEN starts): omit the opening section entirely.

### Perspective, wording, and "you"

- Win-probability percentages in templates are **mover-relative** ("dropped Black's winning chances from 62% to 20%"); pawn-unit eval labels are **white-perspective**, matching the app-wide eval-bar convention (`+1.2`, `-M3`).
  Extract the label formatting shared with `GameReplayViewModel.makeEvalDisplay` into one helper rather than duplicating it.
- Templates address a player as "you" only when `userProfile.chessComUsername` case-insensitively equals that player's name; otherwise neutral "White"/"Black".
  This is a rendering choice, not a chess claim, so it needs no audit.
- Round percentages to whole numbers; evals to one decimal - consistent everywhere.

### Takeaways (rule-based aggregation, cap 3)

- Recurring theme: "{count} of {player}'s mistakes left a piece to be captured on the next move" - from `PunishmentFact` aggregation, only when count >= 2, with the move numbers listed.
- Mate awareness: restate a `MissedMateFact`/`AllowedMateFact` if present.
- Opening: only when the deviation is followed within 4 plies by an eval below 45% win probability for the deviating player (all from records): "{player} left book on move {n} with {san}; the engine already preferred {opponent} soon after ({label})."
- Fallback for clean games: a plain accuracy statement ("A clean game: no mistakes or blunders at this analysis depth.").

## What to build, in order

Each step ends with a verification; do not continue past a failing verification.

### Step 0 - Preflight

1. `scripts/fetch-nnue.sh` (no-op if nets present), then `xcodegen generate`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto build` succeeds.
3. `swift test` green in ChessCore, AnalysisKit, Persistence (EngineKit/ChessComKit untouched by M5; run them anyway if cheap).

### Step 1 - ChessCore: replay primitives

- `public struct ReplayedMove`: `san`, `uci`, `movedPieceKind`, `movedPieceColor`, `capturedPieceKind: Kind?`, `isCheck`, `isCheckmate`, `endSquare`, `resultingFEN` (mirror the shapes already used by the facade; wrap chesskit types, do not leak them).
- `public static func replayLine(fromUCI:startingFEN:) -> [ReplayedMove]` - generalize the existing `sanLine` body (EngineLANParser parse -> `board.move` -> promotion completion), stop at the first unplayable move; reimplement `sanLine` on top of it and fix its stale `+`/`#` doc note (verified fact 2).
- `public func moveDetail(at index: MoveIndex) -> ReplayedMove?` for played mainline moves (from `game.moves[index.raw]` - it already carries result/checkState/san/lan).
- `public static func material(fen: String) -> (white: Int, black: Int)` with values 1/3/3/5/9.
- `public static func epd(fromFEN:) -> String` (first 4 space-separated fields).

Tests: the two probe cases from this session as regression tests (`Qxf7#` mate flag + suffix; `Qh5+` check flag), a capture (`capturedPieceKind`), a promotion line, `material` on the start position (39/39), and `replayLine` over the M2 smoke PV `e2e4 e7e5 g1f3 b8c6 f1b5 g8f6`.

### Step 2 - Opening book

- `scripts/fetch-eco.sh` (curl the 5 TSVs, convert TSV -> JSON array, write `Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco.json`); run it and commit the real eco.json.
- `OpeningBook` per the decisions above, plus `lookup(fens: [String]) -> OpeningMatch?` returning `(eco, name, deepestBookPly)`.
- Tests: index builds without dropping entries (a dropped/unreplayable line is a converter bug - assert count == entries parsed); `1. e4` names King's Pawn-family; the full real-game fixture PGN (copy the inline string from `RealGameFixtureTests.swift`, noting its origin) gets a non-nil match with a plausible deviation ply, logging our name next to its `B07` tag; a transposition case; a from-FEN game returns nil.
- Time the index build in the test output; if it exceeds ~1s on this machine, switch to precomputed EPDs in the JSON (decision above) before proceeding.

### Step 3 - Facts, detectors, key moments

- `ReportInput` (plain value, decodable for test fixtures), the Fact structs, `ThemeDetector`, `KeyMomentSelector` - exactly per the decisions.
- Mover derivation from the FEN side-to-move field, cross-checked against parity in debug.
- Tests are the heart: crafted FEN/PV fixtures per detector (a genuine hung piece where the PV capture stays ahead; a defended "capture" where material returns to even and the material clause must NOT fire; missed mate firing and not firing, including the `|mateIn| == 99` sentinel exclusion; allowed mate; `capturesJustMovedPiece` true/false), key-moment selection boundaries (always-include blunders, cap 8, minimum 3, chronological order, empty case).

### Step 4 - Builder, templates, auditor, golden

- `ReportBuilder` assembles `GameReport` (header: accuracies + per-player classification counts + opening; key moments with attached Facts; takeaways), `ReportText` renders it, `FactAuditor` gates it (drop-on-fail).
- Canned fixture: analyze the fixture game at Standard through the real app (step 6 does this anyway - generate the fixture then), dump with `sqlite3 -json` (`plyIndex, multiPVRank, depth, scoreCentipawns, mateIn, principalVariation, fen`), commit under `Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/` (the test target needs a `resources:` entry added to the manifest) together with a golden report text file.
- Tests: golden match; auditor drops nothing on the fixture; deliberately corrupted Facts (wrong SAN, non-prefix line, wrong eval, non-mating "mate line") are each caught and dropped.

### Step 5 - App wiring and UI

- Fix M4 bug #2 first: a fourth toolbar branch in `GameReplayView.analysisToolbar` - when `!engineService.isStarted && unavailableReason == nil`, show a disabled "Starting engine..." control (with an accessibility label so E2E can assert it).
- `GameReplayViewModel`: retain full per-ply record lists in `loadCachedAnalysis`, build `ReportInput` + `GameReport` when `isAnalyzed` (invalidate on re-analyze), expose report state.
- Right pane becomes a two-tab pane (segmented `Picker`: "Moves" / "Report" - a native control, AX-drivable; keep `MoveListView` untouched).
- `GameReportView`: header (players/result/accuracies, reusing the existing accuracy line), classification-count rows styled via the existing `ClassificationBadge` colors, opening line, key-moment list where each moment is a real `Button` (M3 accessibility lesson) that jumps the board (`viewModel.jump(to: moveIndices[ply])`), takeaways section.
  States: not analyzed -> plain message pointing at the Analyze toolbar button; analyzing -> progress; parse-failed games never reach the report.
  Optional if time remains: a "play out the best line" button per key moment calling the existing `adoptLine(sanMoves:)`.
- `xcodegen generate` after adding files; build + app tests green.

### Step 6 - Acceptance pass (the zero-false-statement audit)

1. Release build.
   Analyze the fixture game (`MagnusCarlsen vs artin10862`) at Standard; generate step 4's canned fixture from this run.
2. Open the Report tab via the AX-element method and dump its text (`entire contents of window`).
   **Read every sentence and verify it independently**: jump the board to each cited ply, check cited lines against `sqlite3` PV rows, replay cited refutations/mates with the step-1 primitives (scratch package if convenient), recompute each percentage from the stored cp via the winP formula.
   Zero false statements, no exceptions - a wrong claim means a detector or template bug; fix it and re-audit.
3. Repeat the read-through on a second, freshly imported chess.com game (different opening, ideally containing a real blunder) - one game proves the pipeline, two keep it honest.
4. Verify key-moment click jumps the board, the not-analyzed state, and the new "Starting engine..." state (click Analyze immediately after a fresh launch - it must show as starting, not silently no-op).
5. All package + app tests green.

### Step 7 - Wrap up

Update `handoffs/HANDOFF.md` (M5 done, decisions, gaps), append to `devlogs/<date>.md` (include the e.p. FEN quirk from verified fact 6 as a logged known gap), write `handoffs/NEXT-SESSION-M6.md` (local LLM coach: Ollama detection, model picker, Verified Coach stack consuming M5's Facts and extending FactAuditor into CoachVerifier - see PLAN.md M6), commit and push code + docs together.

## Working style notes (carried forward; they keep paying off)

- Verify third-party APIs against `.build/checkouts/` source before coding against them; every session so far caught a wrong assumption this way (this one caught the stale `+`/`#` note and the e.p. FEN omission).
- Real E2E through the built app via `osascript`/System Events **AX-element** references only - raw pixel clicks (`cliclick`, `click at {x,y}`) are blocked in this sandbox, and Screen Recording/screenshots are unavailable.
  SwiftUI `ScrollView`/`LazyVStack` interiors are opaque to System Events; verify what's reachable and use strong indirect evidence (DB rows, summary labels) for the rest.
- Any new interactive UI must be real `Button`s / native controls (the M3 lesson: `.onTapGesture` is invisible to both automation and VoiceOver).
- After adding/removing files under `App/`, rerun `xcodegen generate` (the `.xcodeproj` is gitignored); package-internal files need no regen.
- The sandboxed DB for E2E checks: `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.
- Debug on stderr, never stdout (the engine hijacks stdout); use Release builds for anything timing-sensitive.
- Fetch real chess.com games for fixtures/spot-checks rather than fabricating PGNs.
- Commit and push milestone work together with updated handoffs and a dated devlog entry.
