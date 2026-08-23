# Move-quality repair completed

Status: completed on 2026-08-24.

Branch: `move-quality-p4.2`.

This document replaces the bootstrap instructions for the move-quality session.

## Scope completed

`MoveQualityFact` is an optional typed fact on each selected `KeyMoment`.

The fact reports captures, captured piece kind, check, checkmate, redevelopment, moved-before-castling, and early-queen movement.

Checkmate sets both `isCheckmate` and `isCheck` to true.

`ThemeDetector.moveQuality(input:ply:)` validates the complete history through `ChessGame.replayLine`.

The validation requires well-formed FEN records, legal and exact UCI replay, expected mover color from both FEN and input parity, tracked source identity, and matching stored boards.

Any missing, malformed, illegal, wrong-colored, or inconsistent historical record closes the whole fact.

FEN validation requires exactly six fields, a nonnegative integer halfmove clock, and a positive integer fullmove number.

Replay comparison checks all six FEN fields, with only the documented persisted en-passant normalization and the narrow ChessCore en-passant halfmove correction.

The semantic halfmove clock for a real en-passant capture remains `0`; the correction accepts only ChessCore's observed replay value of `1` against that expected `0`.

The tracker carries piece kind, color, move count, and original-queen identity.

Only a pawn diagonal capture onto an empty square can remove an en-passant victim.

Castling updates the rook identity and its move count.

Promotion changes the tracked kind and resets its pedagogical move count.

No hand-written movement geometry is used.

The opening phase is defined by pre-move FEN fullmove number less than or equal to 10.

Early queen movement requires the original queen to leave `d1` or `d8` before pre-move fullmove 5.

Nonstandard queens, returned queens, and move-5-or-later queen departures do not fire early-queen.

`KeyMomentSelector` was left unchanged.

## Output integration completed

`ReportText` renders deterministic neutral `Move quality:` observations.

The report renderer emits only one redevelopment clause when redevelopment and moved-before-castling overlap.

The report renderer makes no causal claim about evaluation changes.

`CoachFactsPayload` has an optional typed `moveQuality` field with a backward-compatible decoding default of nil.

`CoachPayloadBuilder` carries the fact into the structured moment payload.

`CoachPrompt` instructs the model to describe move-quality data neutrally and avoid duplicate redevelopment observations.

AnalysisKit and CoachKit report and payload goldens were updated.

## Test evidence

Initial RED evidence was 149 AnalysisKit tests with 11 issues and 76 CoachKit tests with 3 issues.

The corrected Qh5 and castling fixtures are legal and the final Qh5 post-FEN rank is `4R1K1`.

The corrected Black queen fixture starts with a White quiet move before the Black queen move.

The focused move-quality regression set has 20 passing tests.

The counter-validation RED run had 10 selected tests and 4 issues on the prior implementation.

The counter-validation GREEN run has 10 selected tests and 0 issues.

`swift test --package-path Packages/AnalysisKit` passes exactly 153 tests in 6 suites.

`swift test --package-path Packages/CoachKit` passes exactly 76 tests in 8 suites.

`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` ends with `** BUILD SUCCEEDED **`.

`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` passes exactly 179 tests in 34 suites and ends with `** TEST SUCCEEDED **`.

## Real fixture hand check

The real Magnus Carlsen versus artin10862 fixture has 56 stored positions and 55 played UCIs, all of which produce audited facts.

Capture fires are at plies 8, 9, 15, 18, 21, 22, 23, 24, 25, 31, 32, 43, 44, and 45.

Check fires are at plies 43, 45, 49, 51, and 55, with the ply-55 check valid.

Ply 17 is the only redevelopment and moved-before-castling fire.

There are no checkmate or early-queen fires in this fixture.

Ply 9 is a move-5 queen capture and correctly does not fire early-queen.

Ply 21 is past the fullmove-10 opening cutoff and correctly does not fire redevelopment.

## Explicit limitation

The repository contains no `%clk` parsing or per-move clock data.

Time-per-move remains unimplemented.

## Next work

Continue the remaining P4.2 detectors in `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`.

Do not reopen this completed move-quality scope unless a new regression is found.
