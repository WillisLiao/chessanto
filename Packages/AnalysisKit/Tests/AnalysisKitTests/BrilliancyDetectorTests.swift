import ChessCore
import Testing

@testable import AnalysisKit

private func line(rank: Int, cp: Int?, mate: Int?, pv: [String], depth: Int = 20) -> RankedLine {
    RankedLine(rank: rank, scoreCentipawns: cp, mateIn: mate, principalVariationUCI: pv, depth: depth)
}

/// A genuine queen sacrifice forcing a smothered mate: White plays Qd5-g8+
/// (the engine's own rank-1 choice), Black's only sensible reply Rxg8
/// accepts the sacrifice, and White mates with Nf7#. Verified by hand: the
/// queen's diagonal to g8 is clear, the rook's recapture is a legal rank
/// move, and Nf7 checks a king boxed in by its own rook (g8) and pawns
/// (g7, h7) with nothing able to capture the knight - real checkmate.
private func queenSacMateInput() -> ReportInput {
    let preFEN = "5r1k/6pp/8/3Q2N1/8/8/8/6K1 w - - 0 1"
    let postFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 1 1"
    return ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: nil, mate: 2, pv: ["d5g8", "f8g8", "g5f7"]),
                    line(rank: 2, cp: 50, mate: nil, pv: ["g5f7"]),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: ["f8g8", "g5f7"])], playedUCI: "d5g8"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
}

@Test func brilliantFiresOnAcceptedQueenSacrificeThatMates() {
    #expect(BrilliancyDetector.isBrilliant(input: queenSacMateInput(), ply: 1))
}

@Test func brilliantDoesNotFireOnAnOrdinaryTrade() {
    // Bxd5 Nxd5: an even trade of minor pieces (deficit 0), still the
    // engine's rank-1 choice.
    let preFEN = "4k3/8/1n6/3n4/8/8/6B1/4K3 w - - 0 1"
    let postFEN = "4k3/8/1n6/3B4/8/8/8/4K3 b - - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: 200, mate: nil, pv: ["g2d5", "b6d5"]),
                    line(rank: 2, cp: -50, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: 400, mate: nil, pv: [])], playedUCI: "g2d5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantDoesNotFireOnAnUnsoundSacrifice() {
    // Same shape as the positive fixture, but the post-move evaluation is
    // actually bad for the mover.
    let preFEN = "5r1k/6pp/8/3Q2N1/8/8/8/6K1 w - - 0 1"
    let postFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 1 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: nil, mate: 2, pv: ["d5g8", "f8g8", "g5f7"]),
                    line(rank: 2, cp: 50, mate: nil, pv: ["g5f7"]),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: -500, mate: nil, pv: [])], playedUCI: "d5g8"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantDoesNotFireOnAForcedRecaptureThatLosesMaterial() {
    // Black's knight lands on g8 first (its own move's destination), then
    // White's queen also lands on g8 - a recapture on the same square,
    // even though the win-probability and uniqueness conditions still pass.
    let startFEN = "5r1k/4n1pp/8/3Q2N1/8/8/8/6K1 b - - 0 1"
    let afterBlackSetupFEN = "5rnk/6pp/8/3Q2N1/8/8/8/6K1 w - - 1 1"
    let afterWhiteRecaptureFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: startFEN, lines: [], playedUCI: nil),
            PlyRecord(
                fen: afterBlackSetupFEN,
                lines: [
                    line(rank: 1, cp: nil, mate: 2, pv: ["d5g8", "f8g8", "g5f7"]),
                    line(rank: 2, cp: 50, mate: nil, pv: ["g5f7"]),
                ],
                playedUCI: "e7g8"
            ),
            PlyRecord(fen: afterWhiteRecaptureFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: [])], playedUCI: "d5g8"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 2))
}

@Test func brilliantDoesNotFireOnAQuietBestMoveWithNoSacrifice() {
    // Engine's top choice, winning, unique margin, but no material given
    // up at all (deficit 0).
    let preFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let postFEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: 50, mate: nil, pv: ["e2e4", "e7e5", "g1f3"]),
                    line(rank: 2, cp: -300, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: 800, mate: nil, pv: [])], playedUCI: "e2e4"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))

    // And through MoveClassifier.classify (no brilliantPlies supplied),
    // this ply must classify as .best, not .brilliant.
    let evals = [
        PlyEvaluation(scoreCentipawns: 50, mateIn: nil, bestMoveUCI: "e2e4"),
        PlyEvaluation(scoreCentipawns: 800, mateIn: nil, bestMoveUCI: nil),
    ]
    let result = MoveClassifier.classify(positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true])
    #expect(result == [.best])
}

@Test func brilliantDoesNotFireOnAnExchangeSacrifice() {
    // Rxa5 bxa5: White trades a rook (5) for a knight (3), a settled
    // deficit of exactly 2 - below the pinned threshold of 3.
    let preFEN = "4k3/8/1p6/n7/8/8/8/R3K3 w - - 0 1"
    let postFEN = "4k3/8/1p6/R7/8/8/8/4K3 b - - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: 50, mate: nil, pv: ["a1a5", "b6a5"]),
                    line(rank: 2, cp: -300, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: 700, mate: nil, pv: [])], playedUCI: "a1a5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantDoesNotFireWhenTheMoveWasNotTheEnginesChoice() {
    let input = queenSacMateInput()
    let notEnginesChoice = ReportInput(
        plies: [
            input.plies[0],
            PlyRecord(fen: input.plies[1].fen, lines: input.plies[1].lines, playedUCI: "g5f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: notEnginesChoice, ply: 1))
}

@Test func brilliantDoesNotFireWhenAlternativesAlsoWin() {
    // Same fixture shape, but rank-2 is nearly as good as rank-1 (margin < 10).
    let preFEN = "5r1k/6pp/8/3Q2N1/8/8/8/6K1 w - - 0 1"
    let postFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 1 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: nil, mate: 2, pv: ["d5g8", "f8g8", "g5f7"]),
                    line(rank: 2, cp: 1200, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: [])], playedUCI: "d5g8"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantDoesNotFireWithoutASecondEngineLine() {
    let preFEN = "5r1k/6pp/8/3Q2N1/8/8/8/6K1 w - - 0 1"
    let postFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 1 1"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [line(rank: 1, cp: nil, mate: 2, pv: ["d5g8", "f8g8", "g5f7"])], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: [])], playedUCI: "d5g8"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantDoesNotFireWhenTheSacrificeIsDeclinedInTheEnginesLine() {
    // Knight sac offered but the engine's own PV shows Black never taking
    // it - the king just shuffles - so the deficit stays 0 at every even k.
    let preFEN = "4k3/8/3p4/8/r6Q/5N2/8/4K3 w - - 0 1"
    let postFEN = "4k3/8/3p4/4N3/r6Q/8/8/4K3 b - - 1 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: 900, mate: nil, pv: ["f3e5", "e8f8", "e1d1", "f8g8"]),
                    line(rank: 2, cp: 100, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: 800, mate: nil, pv: [])], playedUCI: "f3e5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(!BrilliancyDetector.isBrilliant(input: input, ply: 1))
}

@Test func brilliantSurvivesAnIntermediateCheckBeforeAcceptance() {
    // Nf3-e5 hangs the knight to d6, but Black checks first with Ra4-e4+
    // before finally capturing on move 4 - the deficit only appears at
    // k=4, not k=2, pinning that the detector checks both.
    let preFEN = "4k3/8/3p4/8/r6Q/5N2/8/4K3 w - - 0 1"
    let postFEN = "4k3/8/3p4/4N3/r6Q/8/8/4K3 b - - 1 1"
    let input = ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [
                    line(rank: 1, cp: 900, mate: nil, pv: ["f3e5", "a4e4", "e1d1", "d6e5"]),
                    line(rank: 2, cp: 100, mate: nil, pv: []),
                ],
                playedUCI: nil
            ),
            PlyRecord(fen: postFEN, lines: [line(rank: 1, cp: 1000, mate: nil, pv: [])], playedUCI: "f3e5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(BrilliancyDetector.isBrilliant(input: input, ply: 1))
}
