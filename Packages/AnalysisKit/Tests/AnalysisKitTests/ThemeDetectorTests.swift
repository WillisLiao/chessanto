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

@Test func punishmentFactDoesNotFireOnAFairTrade() {
    // A knight on d5, defended by another knight on b6, is captured by a
    // bishop and recaptured: an equal trade, netting nothing.
    //
    // This used to produce a fact with a zero material gain, which rendered
    // as "This also left the knight on d5 hanging: Bxd5." for an ordinary
    // exchange - and then fed the "Material left en prise" practice theme
    // and the Player Brief's "Loose pieces" motif, turning a routine trade
    // into evidence about the player.
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
    #expect(ThemeDetector.punishment(input: input, ply: 1) == nil)
}

@Test func punishmentFactDoesNotFireOnATradeTruncatedBeforeTheRecapture() {
    // The same defended knight, but the stored PV stops after the capture.
    // Measuring material at the end of the line would read as a free piece
    // purely because the line was cut there; the recapture decides it.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/8/1n6/8/8/8/6B1/4K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "4k3/8/1n6/3n4/8/8/6B1/4K3 w - - 0 1",
                lines: [line(rank: 1, cp: 0, mate: nil, pv: ["g2d5"])],
                playedUCI: "f6d5"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.punishment(input: input, ply: 1) == nil)
}

@Test func punishmentFactFiresOnAnUndefendedPieceEvenFromASingleMovePV() {
    // The same shape as the trade above with the defender removed, so the
    // knight really is hanging. A one-move PV is enough here, because the
    // test is whether anything can take back, not how long the line is.
    let input = ReportInput(
        plies: [
            PlyRecord(fen: "4k3/8/8/8/8/8/6B1/4K3 b - - 0 1", lines: [], playedUCI: nil),
            PlyRecord(
                fen: "4k3/8/8/3n4/8/8/6B1/4K3 w - - 0 1",
                lines: [line(rank: 1, cp: 0, mate: nil, pv: ["g2d5"])],
                playedUCI: "f6d5"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.punishment(input: input, ply: 1)
    #expect(fact?.refutingSAN == "Bxd5")
    #expect(fact?.netMaterialGainForOpponent == 3)
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

// MARK: - IgnoredThreatFact

@Test func ignoredThreatFactFiresOnIgnoredCheckmate() {
    // Scholar's mate threat: White Queen on h5 + Bishop on c4 threaten Qxf7#.
    // Black plays a7-a6, completely ignoring the checkmate threat.
    // White duly plays Qxf7# on the next move.
    let preFEN = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3"
    let postFEN = "r1bqkbnr/1ppp1ppp/p1n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 4"
    let mateFEN = "r1bqkbnr/1ppp1Qpp/p1n5/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "a7a6"),
            PlyRecord(fen: mateFEN, lines: [], playedUCI: "h5f7"),
        ],
        whiteName: "White", blackName: "Black", result: "1-0", chessComUsername: nil
    )
    let fact = ThemeDetector.ignoredThreat(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.isCheckmate == true)
    #expect(fact?.threatenedSAN == "Qxf7#")
    #expect(fact?.capturedPieceKind == .pawn)
    #expect(fact?.capturedSquare == "f7")
}

@Test func ignoredThreatFactFiresOnIgnoredHangingPiece() {
    // Black bishop on c5 is undefended. White bishop on e3 attacks c5.
    // Black plays an unrelated pawn move (h7-h6).
    // White captures the bishop with Bxc5.
    let preFEN = "4k3/7p/8/2b5/8/4B3/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/7p/2b5/8/4B3/8/4K3 w - - 0 2"
    let capFEN = "4k3/8/7p/2B5/8/8/8/4K3 b - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "h7h6"),
            PlyRecord(fen: capFEN, lines: [], playedUCI: "e3c5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.ignoredThreat(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.threatenedSAN == "Bxc5")
    #expect(fact?.capturedPieceKind == .bishop)
    #expect(fact?.capturedSquare == "c5")
    #expect(fact?.netMaterialGainForOpponent == 3)
    #expect(fact?.isCheckmate == false)
}

@Test func ignoredThreatFactFiresOnDefendedQueenAttackedByLesserPiece() {
    // Black Queen on d5 defended by pawn on e6. White Bishop on b3 attacks d5.
    // Queen is defended, but Bishop is worth 3 and Queen is worth 9 (net +6 for White).
    // Black ignores the threat and plays a7-a6.
    // White plays Bxd5.
    let preFEN = "4k3/8/4p3/3q4/8/1B6/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/p3p3/3q4/8/1B6/8/4K3 w - - 0 2"
    let capFEN = "4k3/8/p3p3/3B4/8/8/8/4K3 b - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "a7a6"),
            PlyRecord(fen: capFEN, lines: [], playedUCI: "b3d5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    let fact = ThemeDetector.ignoredThreat(input: input, ply: 1)
    #expect(fact != nil)
    #expect(fact?.threatenedSAN == "Bxd5")
    #expect(fact?.capturedPieceKind == .queen)
    #expect(fact?.capturedSquare == "d5")
    #expect(fact?.netMaterialGainForOpponent == 6)
    #expect(fact?.isCheckmate == false)
}

@Test func ignoredThreatFactDoesNotFireWhenThreatIsAddressedByDefending() {
    // Black bishop on c5 was undefended.
    // Black plays b7-b6, defending the bishop on c5 with the pawn.
    // White plays Bxc5, Black can recapture with bxc5 (equal trade, 3 for 3).
    let preFEN = "4k3/1p6/8/2b5/8/4B3/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/1p6/2b5/8/4B3/8/4K3 w - - 0 2"
    let capFEN = "4k3/8/1p6/2B5/8/8/8/4K3 b - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "b7b6"),
            PlyRecord(fen: capFEN, lines: [], playedUCI: "e3c5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireWhenThreatIsAddressedByMovingPieceAway() {
    // Black bishop on c5 was attacked.
    // Black plays c5-b6, saving the bishop.
    // White plays a quiet move a2-a3.
    let preFEN = "4k3/8/8/2b5/8/4B3/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/1b6/8/8/4B3/8/4K3 w - - 0 2"
    let quietFEN = "4k3/8/1b6/8/8/4B3/P7/4K3 b - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "c5b6"),
            PlyRecord(fen: quietFEN, lines: [], playedUCI: "a2a3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireWhenThreatIsAddressedByCapturingAttacker() {
    // Black knight on d5 captures White's attacking bishop on e3.
    let preFEN = "4k3/8/8/2bn4/8/4B3/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/8/2b5/8/4n3/8/4K3 w - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "d5e3"),
            PlyRecord(fen: "4k3/8/8/2b5/8/4K3/8/8 b - - 0 2", lines: [], playedUCI: "e1e3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireWhenThreatIsAddressedByBlockingLine() {
    // Scholar's mate threatened: White Queen on h5, White Bishop on c4.
    // Black plays g7-g6, blocking the Queen's path to f7.
    let preFEN = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3"
    let postFEN = "r1bqkbnr/pppp1p1p/2n3p1/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 4"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "g7g6"),
            PlyRecord(fen: "r1bqkbnr/pppp1p1p/2n3p1/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 1 4", lines: [], playedUCI: "h5f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireOnQuietPositionWithNoThreat() {
    let preFEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    let postFEN = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    let nextFEN = "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "e7e5"),
            PlyRecord(fen: nextFEN, lines: [], playedUCI: "g1f3"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireWhenVulnerabilityWasCreatedByMover() {
    // Black bishop is safe on c8. White bishop on c1.
    // Black blunders by moving the bishop to d7 where it hangs for free.
    // This is a hanging-piece blunder created by the mover, NOT an ignored existing threat.
    let preFEN = "r1bqkbnr/pppppppp/2n5/8/8/2N5/PPPPPPPP/R1BQKBNR b KQkq - 1 2"
    let postFEN = "r2qkbnr/pppbpppp/2n5/8/8/2N5/PPPPPPPP/R1BQKBNR w KQkq - 2 3"
    let capFEN = "r2qkbnr/pppBpppp/2n5/8/8/2N5/PPPPPPPP/R2QKBNR b KQkq - 0 3"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "c8d7"),
            PlyRecord(fen: capFEN, lines: [], playedUCI: "c1d7"), // not legal in pre-move
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireOnDefendedEqualTrade() {
    // Defended knight on d5 (defended by pawn on c6). White bishop on c4.
    // Black plays an unrelated move (h7-h6). White plays Bxd5, Black recaptures cxd5.
    // This is an equal trade, not winning material.
    let preFEN = "4k3/8/2p5/3n4/2B5/8/8/4K3 b - - 0 1"
    let postFEN = "4k3/7p/2p5/3n4/2B5/8/8/4K3 w - - 0 2"
    let capFEN = "4k3/7p/2p5/3B4/8/8/8/4K3 b - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "h7h6"),
            PlyRecord(fen: capFEN, lines: [], playedUCI: "c4d5"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}

@Test func ignoredThreatFactDoesNotFireAtLastPlyOfGame() {
    // Only 2 plies in game, asking for ply 1 - no follow-up opponent move exists.
    let preFEN = "4k3/7p/8/2b5/8/4B3/8/4K3 b - - 0 1"
    let postFEN = "4k3/8/7p/2b5/8/4B3/8/4K3 w - - 0 2"
    let input = ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [], playedUCI: "h7h6"),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
    #expect(ThemeDetector.ignoredThreat(input: input, ply: 1) == nil)
}
