import ChessCore
import Testing

@testable import AnalysisKit

private func line(rank: Int, cp: Int?, mate: Int?, pv: [String], depth: Int = 20) -> RankedLine {
    RankedLine(rank: rank, scoreCentipawns: cp, mateIn: mate, principalVariationUCI: pv, depth: depth)
}

// MARK: - PunishmentFact

@Test func punishmentFactFiresOnUndefendedHangCapturesJustMovedPiece() {
    // Black bishop a5 -> d2, hanging to White's bishop on c1 for free.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/8/8/b7/8/8/8/2B1K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "4k3/8/8/8/8/8/3b4/2B1K3 w - - 1 2",
                lines: [line(rank: 1, cp: 300, mate: nil, pv: ["c1d2"])],
                playedUCI: "a5d2"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.punishment(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.refutingSAN == "Bxd2")
    #expect(fact?.capturedPieceKind == .bishop)
    #expect(fact?.capturedSquare == "d2")
    #expect(fact?.capturesJustMovedPiece == true)
    #expect(fact?.netMaterialGainForOpponent == 3)
}

@Test func punishmentFactFiresOnUnrelatedHangCapturesJustMovedPieceFalse() {
    // Black plays an unrelated pawn move (h7-h6) while a knight on c6 was
    // already hanging to White's bishop on a4.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/7p/2n5/8/B7/8/8/4K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "4k3/8/2n4p/8/B7/8/8/4K3 w - - 0 2",
                lines: [line(rank: 1, cp: 300, mate: nil, pv: ["a4c6"])],
                playedUCI: "h7h6"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.punishment(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.refutingSAN == "Bxc6+")
    #expect(fact?.capturedPieceKind == .knight)
    #expect(fact?.capturesJustMovedPiece == false)
    #expect(fact?.netMaterialGainForOpponent == 3)
}

@Test func punishmentFactMaterialClauseDoesNotFireOnFairTrade() {
    // A knight on d5, defended by another knight on b6, is "captured" by a
    // bishop, then recaptured - equal-value trade, net material change 0.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/8/1n6/8/8/8/6B1/4K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "4k3/8/1n6/3n4/8/8/6B1/4K3 w - - 0 1",
                lines: [line(rank: 1, cp: 0, mate: nil, pv: ["g2d5", "b6d5"])],
                playedUCI: "f6d5"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.punishment(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.netMaterialGainForOpponent == 0)
}

@Test func punishmentFactDoesNotFireWithoutACapturingPV() {
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "3k4/8/8/8/8/8/8/4K3 w - - 0 1",
                lines: [line(rank: 1, cp: 10, mate: nil, pv: ["e1e2"])],
                playedUCI: "e8d8"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.punishment(input: input, ply: 1) == nil)
}

// MARK: - MissedMateFact / AllowedMateFact

private let missedMatePreFEN = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
private let missedMatePostFEN = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/5N2/PPPP1PPP/RNB1K2R b KQkq - 5 4"

@Test func missedMateFactFiresAndCitesVerifiedLine() {
    // plies[0] = the position with mate-in-1 available (White to move,
    // side-to-move read from this FEN for the mover-parity check);
    // plies[1] = after White played Nf3 instead, letting the mate slip.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: missedMatePreFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: ["h5f7"])], playedUCI: nil),
            PlyRecord(fen: missedMatePostFEN, lines: [line(rank: 1, cp: 800, mate: nil, pv: [])], playedUCI: "g1f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.missedMate(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.mateInN == 1)
    #expect(fact?.matingLineSANs == ["Qxf7#"])
}

@Test func missedMateFactDoesNotFireWhenMateStillAvailableAfter() {
    // The mate is still there after the move (a different, still-mating
    // continuation) - not "missed".
    let input = ReportInput(
        plies: [
            PlyRecord(fen: missedMatePreFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: ["h5f7"])], playedUCI: nil),
            PlyRecord(fen: missedMatePreFEN, lines: [line(rank: 1, cp: nil, mate: 1, pv: ["h5f7"])], playedUCI: "d1d2"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.missedMate(input: input, ply: 1) == nil)
}

@Test func missedMateFactExcludesTerminalSentinel() {
    // |mateIn| == 99 means "game over" (verified fact 1), never a real
    // mate-in-99 claim - the sentinel must not be treated as a missed mate.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: missedMatePreFEN, lines: [line(rank: 1, cp: nil, mate: 99, pv: [])], playedUCI: nil),
            PlyRecord(fen: missedMatePostFEN, lines: [line(rank: 1, cp: 800, mate: nil, pv: [])], playedUCI: "d1d2"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.missedMate(input: input, ply: 1) == nil)
}

// White to move pre-move, boxed in by f2/g2/h2, before Black's rook has
// reached e8 (a plausible predecessor position - only the side-to-move
// field and eval matter to the detector, not full continuity).
private let allowedMatePreFEN = "6k1/4r3/8/8/8/8/5PPP/6K1 w - - 0 1"
private let allowedMatePostFEN = "4r1k1/8/8/8/8/8/5PPP/6K1 b - - 0 1"

@Test func allowedMateFactFiresAndCitesVerifiedLine() {
    let input = ReportInput(
        plies: [
            PlyRecord(fen: allowedMatePreFEN, lines: [line(rank: 1, cp: 20, mate: nil, pv: [])], playedUCI: nil),
            PlyRecord(fen: allowedMatePostFEN, lines: [line(rank: 1, cp: nil, mate: -1, pv: ["e8e1"])], playedUCI: "f2f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.allowedMate(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.mateInN == 1)
    #expect(fact?.matingLineSANs == ["Re1#"])
}

@Test func allowedMateFactDoesNotFireWhenAlreadyMatingBefore() {
    let input = ReportInput(
        plies: [
            PlyRecord(fen: allowedMatePreFEN, lines: [line(rank: 1, cp: nil, mate: -1, pv: ["e8e1"])], playedUCI: nil),
            PlyRecord(fen: allowedMatePostFEN, lines: [line(rank: 1, cp: nil, mate: -1, pv: ["e8e1"])], playedUCI: "f2f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.allowedMate(input: input, ply: 1) == nil)
}

// MARK: - BetterMoveFact / EvalSwingFact

@Test func betterMoveFactCitesRank1PVWhenDifferentFromPlayed() {
    let preFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [line(rank: 1, cp: 30, mate: nil, pv: ["e2e4", "e7e5", "g1f3"])], playedUCI: nil),
            PlyRecord(fen: "rnbqkbnr/pppppppp/8/8/7P/8/PPPPPPP1/RNBQKBNR b KQkq - 0 1", lines: [], playedUCI: "h2h4"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.betterMove(input: input, ply: 1)
    #expect(fact?.bestMoveSAN == "e4")
    #expect(fact?.lineSANs == ["e4", "e5", "Nf3"])
    #expect(fact?.preMoveScoreCentipawns == 30)
}

@Test func betterMoveFactDoesNotFireWhenPlayedMoveIsBest() {
    let preFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [line(rank: 1, cp: 30, mate: nil, pv: ["e2e4"])], playedUCI: nil),
            PlyRecord(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 1", lines: [], playedUCI: "e2e4"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.betterMove(input: input, ply: 1) == nil)
}
