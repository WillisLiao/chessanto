# 2026-08-24 - Move-quality repair (P4.2 slice)

## Status

The move-quality repair is complete on branch `move-quality-p4.2`.

The implementation and regression tests are committed and pushed after the validation listed below.

The `%clk` premise was rechecked across the repository and remains false.

No clock parsing was added.

## `%clk` premise

`ChessComKit` stores the chess.com PGN text as an unparsed string.

`ChessCore` passes PGN text to `chesskit-swift` without exposing per-move clock annotations.

`AnalysisKit` has no clock or time-spent field on `PlyRecord` or `ReportInput`.

The app's `ContinuousClock` use is only for engine timeout control.

The stretch goal remains explicitly unimplemented because no source data exists to surface safely.

## Implementation

`MoveQualityFact` remains an optional, typed fact on `KeyMoment`.

`ThemeDetector.moveQuality(input:ply:)` now closes the entire historical fact when any required replay record is missing, malformed, illegal, wrong-colored, or inconsistent with its stored board.

Every prior and current UCI is replayed through `ChessGame.replayLine`.

The replayed move must match the stored UCI, the FEN side to move, `ReportInput.moverIsWhite(atPly:)`, the tracked source identity, and the stored pre-move and post-move board.

Position identity compares the first four FEN fields.

The repository's stored post-double-pawn-push rows intentionally use `-` for the transient en-passant target, so that one known normalization is accepted while the placement, side, and castling fields remain strict.

The tracker is a typed identity map carrying piece kind, color, pedagogical move count, and original-queen identity.

Only a pawn diagonal capture onto an empty destination can remove an en-passant victim.

Castling moves the rook identity and increments its move count.

Promotion changes the tracked kind and resets the promoted piece's pedagogical move count.

Checkmate also sets `isCheck` to true in the locally composed fact.

Redevelopment and moved-before-castling use the pre-move FEN fullmove number and include fullmoves 1 through 10.

Early-queen detection requires the original queen to leave `d1` or `d8` before pre-move fullmove 5.

Nonstandard queens, returned queens, and move-5-or-later departures do not fire the early-queen flag.

No movement legality or attack geometry is hand-written.

`KeyMomentSelector` is unchanged.

`ReportText` renders deterministic, neutral `Move quality:` observations.

The renderer emits only one redevelopment clause when both redevelopment flags are true.

The renderer makes no causal claim about the evaluation change.

`CoachFactsPayload` carries typed optional `moveQuality` data.

Legacy payloads that omit the field decode with `moveQuality == nil`.

The structured Coach prompt tells the model to describe move-quality facts as neutral observations and not to repeat overlapping clauses.

The real report and Coach golden fixtures include the new neutral text and payload field.

## TDD evidence

The initial RED AnalysisKit run had 149 tests and 11 issues.

The initial RED CoachKit run had 76 tests and 3 issues.

The RED failures covered checkmate check state, corrupted history, en-passant identity, castling rook identity, promotion reset, queen-origin rules, report text, payload compatibility, and prompt structure.

The corrected legal Qh5 and castling fixtures were established before the production change.

The Qh5 fixture uses a minimal legal position and ends with rank one `4R1K1`.

The early Black queen fixture starts with a White quiet move so ply parity cannot disguise a wrong mover color.

The final focused move-quality regression set has 20 tests and passes.

## Real fixture hand check

The Magnus Carlsen versus artin10862 fixture contains 55 stored positions and 54 played plies.

All 54 played plies produce valid audited move-quality facts.

Capture fires occur at plies 8, 9, 15, 18, 21, 22, 23, 24, 25, 31, 32, 43, 44, and 45.

Check fires occur at plies 43, 45, 49, 51, and 55.

Ply 17 is the only redevelopment and moved-before-castling fire in this fixture.

No checkmate or early-queen fire occurs in this fixture.

Ply 9 is a move-5 queen capture and correctly does not fire early-queen.

Ply 21 is past the fullmove-10 opening cutoff and correctly does not fire redevelopment.

The standard and beginner report goldens, the Coach payload golden, and the Coach chat golden all pass.

## Validation

`swift test --package-path Packages/AnalysisKit` passes with exactly 149 tests in 6 suites.

`swift test --package-path Packages/CoachKit` passes with exactly 76 tests in 8 suites.

`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` ends with `** BUILD SUCCEEDED **`.

`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` passes with exactly 179 tests in 34 suites and ends with `** TEST SUCCEEDED **`.

The final changed-file scan reports no em dash characters.

The final `git diff --check` and `git diff main...HEAD --check` checks report no whitespace errors.
