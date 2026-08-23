# 2026-08-24: Fork Detection (P4.2)

## Overview

This session implemented a conservative fork detector and an attacked-enemy primitive for Chessanto.
The implementation is isolated on branch `fork-detector-p4.2` and is wired through the existing report fact pipeline.
The design intentionally favors false negatives when engine evidence is incomplete or ambiguous.

## ChessCore Primitive

`ChessGame.attackedEnemySquares(from:in:)` parses the supplied FEN and source square, reads the source piece, and delegates move generation to ChessKit's public `Board.legalMoves(forPieceAt:)` API.
The primitive keeps only legal destinations occupied by enemy pieces and returns deterministic square and piece-kind pairs sorted by square.
It works independently of FEN side to move, returns no pawn pushes, preserves blocker behavior, and returns an empty result for invalid FEN, invalid squares, empty sources, or positions with no enemy targets.
No hand-written attack geometry was added.
Focused ChessCore coverage exercises knights, open and blocked sliders, pawn captures, no attacks, invalid input, and side-to-move independence.

## Fork Definition

`ForkFact` records the ply, forking piece kind, fork destination, all qualifying targets, the verified original target won by the forking piece, and the settled net material gain.
Qualifying targets are enemy kings plus non-pawn pieces valued at least three pawn-equivalents.
The detector requires either two qualifying non-king targets or a king plus one qualifying non-king target.
Pawns and pieces below the three-point threshold are excluded from target recording, so a valuable piece plus a pawn and two pawns do not fire.
Targets are ordered by descending material value and then by square for deterministic reports.

The detector replays the played move from the prior FEN and requires the replayed move to land on its UCI destination.
It queries the ChessCore primitive in the resulting position rather than relying on hand-written geometry or stale stored board state.
The post-move rank-1 principal variation must replay completely and contain at least three plies.
The first replayed ply must be an opponent response, the second must be the same forking piece capturing an original qualifying non-king target on its original square, and the third must be an opponent reply.
The forking side's material balance after that reply must improve by at least one pawn-equivalent relative to the post-fork position.
Missing, truncated, illegal, or ambiguous replay data returns nil.
Mate explanations take precedence, so a fork is suppressed when `missedMate` or `allowedMate` fires for the same ply.

## Report Integration

`ForkTarget` and `ForkFact` are Codable, Equatable, Sendable value types following the existing fact conventions.
The optional fork field is carried through `KeyMoment`, `ReportBuilder`, `FactAuditor`, and `KeyMomentSelector` without changing key-moment priorities or classification thresholds.
`ReportText` uses one fixed sentence naming the forking piece and square, every qualifying target, and the verified won target with its settled gain.
Existing `KeyMoment` decoding remains source-compatible because the new field is optional and defaulted.
No CoachKit payload or persistence schema was changed.

## Fixture Inspection

The real fixture scan evaluated all 55 plies through `ThemeDetector.fork(input:ply:)`.
The scan produced zero fork fires.
Because there were no real-fixture fires, there were no questionable fires requiring a fixture-specific root-cause repair or manual response-capture-reply hand check.
Synthetic focused tests cover a knight fork, a royal fork, recapture rejection, strict truncated-line rejection, valuable-piece-plus-pawn rejection, ordinary moves, mate precedence, report auditing, and fixed sentence rendering.

## Validation

`swift test` in `Packages/ChessCore` passed 34 tests in 1 suite.
`swift test` in `Packages/AnalysisKit` passed 138 tests in 6 suites.
`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` completed with `** BUILD SUCCEEDED **`.
`xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` passed 179 tests in 34 suites and completed with `** TEST SUCCEEDED **`.
The ignored `Chessanto.xcodeproj` was regenerated from the tracked `project.yml` because the checkout did not contain the generated project before root validation.
The generated project was not committed.

## Commits and Risks

The ChessCore primitive is committed as `0da2ec7` with message `Expose ChessCore attacked enemy squares primitive`.
The detector and report integration are committed as `1c40699` with message `Add conservative fork detector to reports`.
Both commits are pushed to `origin/fork-detector-p4.2`.
The strict use of legal moves means pinned-piece pseudo-attacks are omitted, as required by the frozen ChessKit legal-move contract.
The strict full-line replay and settled-gain checks may produce false negatives when engine principal variations are truncated or unavailable.
