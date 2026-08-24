# 2026-08-25 - Chess960 app integration

Branch: `feature/chess960-app-integration` (worktree `../chessanto-chess960-app-integration`).
Status: implementation complete, verification INCOMPLETE - the session was
wrapped up before the verification bar could run. See "Verification status"
at the bottom. Do not treat this work as done until that section is cleared.

## Dependency handling

`feature/chess960-core` existed locally and committed (`3f192ef`), so the
worktree was created from `main` per the session instructions and the core
branch was then merged into `feature/chess960-app-integration`
(`git merge feature/chess960-core`, clean, no conflicts). Everything below
builds against the real core API.

Play vs Engine (`feature/play-vs-engine-core`) is NOT merged to main, so the
optional "random 960 position" starting option was skipped per the handoff
("don't block on it - import support alone is the real requirement").

## What was found (the report pipeline audit)

The good news first: most of the pipeline is already position-agnostic, and
needs no changes.

- Import: `GameLibrary.importPGN` stores the PGN verbatim after a generic
  tag scan; nothing in it assumes standard chess. A 960-tagged PGN flows
  through file/paste/drag-drop unchanged.
- Board setup display: `GameReplayViewModel` loads via
  `ChessGame(pgn:)` (which honors the FEN header, core-tested against real
  Lichess exports) and renders each ply through
  `BoardPositionMapper.position(fromFEN:)`, which parses only the board
  field and ignores castling notation entirely. The randomized arrangement
  therefore displays correctly at ply 0 with no app change.
- Opening book: the core branch already added a guard at the top of
  `OpeningBook.lookup(fens:)` requiring the standard-start EPD, so 960 games
  get nil everywhere the book is consulted (report opening fact, sidebar
  names, `.book` classification). `GameReportView` renders its Opening
  section only `if let opening = report.opening`, which is the existing
  graceful path used by from-FEN games.
- `ReportBuilder`, `ThemeDetector`, key-moment selection, accuracy:
  all FEN-driven through `ReportInput`; no standard-start assumptions found.

The real bug found - and fixed - is in the engine layer, one step upstream
of the report pipeline:

**Stockfish must run with `UCI_Chess960=true` when searching positions from
Chess960 games, and nothing set it.**

Evidence from the vendored Stockfish 17 source (chesskit-engine 0.7.0
checkout):

- `uci.cpp UCIEngine::move(m, chess960)`: with the flag off, castling moves
  are emitted as king-from-square to g/c-file (destination rewritten); with
  it on, as king-to-rook. `to_move` matches input strings against exactly
  that formatting, so a PV UCI produced under one flag is rejected when
  replayed under the other.
- With the flag off, the rewritten destination collides with plain king
  moves whenever the 960 king starts adjacent to the g/c file (f1/d1/f8/d8,
  true for many of the 960 arrangements). `ChessGame.replayLine` would then
  interpret an engine castle as a plain king move (or vice versa), silently
  corrupting every downstream fact that replays stored PVs -
  `ThemeDetector.punishment`, brilliancy detection, better-move SANs,
  practice lines, coach payloads.
- `position.cpp` line ~529: one castling-legality refinement
  (rook-blocked-check) is applied only when `chess960` is set, so flag-off
  searches can contain subtly illegal castles.
- `engine.cpp Engine::set_position`: `pos.set(fen, options["UCI_Chess960"])`
  latches the flag onto the position object at parse time, so the option
  must be sent BEFORE `position fen`. And `setoption` is ignored while a
  search runs, so it cannot simply precede `setPosition` either. The only
  safe window is between "prior search stopped and drained" and "position
  sent" - i.e., inside `AnalysisEngine.setPosition`.
- Detection subtlety: real Lichess 960 exports use X-FEN (`KQkq`) when rooks
  sit on outer files, and `Chess960.swift` deliberately preserves whatever
  castling style a FEN came with (`isTraditional` check), so app-side FENs
  of 960 games often carry plain `KQkq`. Mode detection therefore cannot key
  on Shredder letters; it has to check geometry (king/rook squares implied
  by traditional letters).

## What was implemented

1. `ChessCore`: new pure helper
   `Chess960.requiresChess960EngineMode(fen:) -> Bool` next to
   `isChess960(startingFEN:)`. True for any Shredder file letter in the
   castling field, or any traditional right whose implied squares (king
   e1/e8, rook h1/a1/h8/a8) don't hold; false for standard positions and
   lapsed `-` rights, leaving standard-game behavior byte-identical.
   Unit tests added for both directions (six cases).
2. `EngineKit`: `AnalysisEngine.setPosition(fen:moves:)` gained
   `chess960: Bool? = nil`. When non-nil and different from the last value
   actually applied (cached in `appliedChess960`), it sends
   `setoption UCI_Chess960` inside setPosition's existing safe window
   (after stop/drain/settle, before the position command). Default nil
   means existing callers are untouched.
3. `App/EngineService`: both search seams -
   `showPosition`'s debounced task and `searchOneShot` (which serves batch
   analysis, coach evaluate, and training grading) - now pass
   `Chess960.requiresChess960EngineMode(fen: fen)`. No upstream signatures
   changed; mode travels with the position itself, so interleaved live/
   batch/companion analysis can never race a stale mode.
4. `engine-smoke`: new section 6 pinning the contract with a deterministic
   probe matrix. Probe position
   `3k4/8/2Q5/1N3N2/8/8/8/R3K3 w A - 0 1` has exactly one mate in 1, the
   queenside castle (Rd1# with every escape covered), so applying the move
   yields bestmove `(none)` and ignoring it leaves real moves. Four probes:
   `e1c1` valid under flag off, `e1a1` under flag on, each rejected under
   the other. Plus two real depth-12 searches of the Lichess fixture start
   (`RNNBBKQR`) in both X-FEN and Shredder spellings with the flag on,
   asserting sane opening evals. Run with:
   `swift run --package-path Packages/EngineKit engine-smoke`.

Note on the non-goal boundary: the handoff says missing core API should be
noted rather than reimplemented in the app layer. The mode-detection helper
is arguably core API that the finished core session didn't ship; I extended
`Packages/ChessCore` on this branch instead of putting FEN parsing in the
app layer, and am flagging it here so the core owner can review/rename/move
it at merge time.

## Not done (next session picks up here)

- The App-target E2E test required by the verification bar was not written
  yet. Planned shape (pattern matches
  `GameReplayViewModelRegisterTests.analyzedViewModel`): inline the real
  Lichess fixture PGN (`Lu5CMX4w`, yoseph2013-penguingim1, 174 plies,
  O-O-O at ply 17 / O-O at ply 34 - copyable from
  `Packages/ChessCore/Tests/ChessCoreTests/Chess960Tests.swift` line ~308),
  import it through `GameLibrary.importPGN`, load in
  `GameReplayViewModel`, assert ply-0 FEN equals the FEN header and the
  displayed board pieces match the `RNNBBKQR` arrangement, save synthetic
  rank-1 analysis rows per ply, assert `report != nil`,
  `report?.opening == nil` (no book misfire), classifications present, and
  no crash. Remember `xcodegen generate` before building after adding the
  test file.
- The full verification bar did not run:

```
$ swift test --package-path Packages/AnalysisKit      # not run
$ swift test --package-path Packages/Persistence      # not run
$ xcodegen generate                                    # not needed yet, no files added
$ xcodebuild build                                     # not run
$ xcodebuild test                                      # not run
```

  `swift test --package-path Packages/ChessCore` was started to smoke-check
  the new helper and timed out at the shell's 300s limit with no output
  (likely a cold debug build of ChessKit + ChessCore in a fresh worktree;
  the merged core session measured the suite itself at ~1s once built).
  Nothing is known to fail; nothing beyond compile-success of the edited
  sources is verified. Rerun the whole bar from scratch and quote real
  output here before merging anything.

## Verification status

NOT VERIFIED. Implementation is believed correct based on source-level
reading of the vendored Stockfish and the merged core tests, but the
verification bar (including the new engine-smoke section) has not produced
a single quoted output yet. Treat every claim above as untested until rerun.
