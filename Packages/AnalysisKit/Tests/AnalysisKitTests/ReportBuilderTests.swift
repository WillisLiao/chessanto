import ChessCore
import Testing

@testable import AnalysisKit

/// A real 7-ply Scholar's-mate game (1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4.
/// Qxf7#), with hand-assigned but internally consistent evaluations (real
/// FENs/UCIs verified by replay - see the M5 handoff's verified facts 1/2).
/// Black's 3rd move (Nf6??) is a genuine blunder that both hangs the f7
/// pawn to an immediate capture AND allows a real forced mate, so this one
/// small fixture exercises EvalSwingFact, BetterMoveFact, PunishmentFact,
/// and AllowedMateFact together.
private func scholarsMateInput(chessComUsername: String? = "BlackPlayer") -> ReportInput {
    func rank1(_ cp: Int?, _ mate: Int?, _ pv: [String]) -> [RankedLine] {
        [RankedLine(rank: 1, scoreCentipawns: cp, mateIn: mate, principalVariationUCI: pv, depth: 20)]
    }
    let plies = [
        PlyRecord(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", lines: rank1(20, nil, ["e2e4"]), playedUCI: nil),
        PlyRecord(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", lines: rank1(25, nil, ["e7e5"]), playedUCI: "e2e4"),
        PlyRecord(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", lines: rank1(30, nil, ["f1c4"]), playedUCI: "e7e5"),
        PlyRecord(fen: "rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 1 2", lines: rank1(25, nil, ["b8c6"]), playedUCI: "f1c4"),
        PlyRecord(fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3", lines: rank1(40, nil, ["d1h5"]), playedUCI: "b8c6"),
        PlyRecord(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", lines: rank1(50, nil, ["g8e7"]), playedUCI: "d1h5"),
        PlyRecord(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", lines: rank1(nil, 1, ["h5f7"]), playedUCI: "g8f6"),
        PlyRecord(fen: "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4", lines: rank1(nil, 99, []), playedUCI: "h5f7"),
    ]
    return ReportInput(plies: plies, whiteName: "WhitePlayer", blackName: "BlackPlayer", result: "1-0", chessComUsername: chessComUsername)
}

@Test func reportBuilderProducesTheExpectedKeyMomentWithAllFacts() {
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    #expect(report.keyMoments.count == 1)
    guard let moment = report.keyMoments.first else { return }
    #expect(moment.ply == 6)
    #expect(moment.evalSwing.playedSAN == "Nf6")
    #expect(moment.evalSwing.classification == .blunder)
    #expect(moment.evalSwing.moverIsWhite == false)

    #expect(moment.betterMove?.bestMoveSAN == "Nge7")

    #expect(moment.punishment?.refutingSAN == "Qxf7#")
    #expect(moment.punishment?.capturedPieceKind == .pawn)
    #expect(moment.punishment?.capturesJustMovedPiece == false)
    #expect(moment.punishment?.netMaterialGainForOpponent == 1)

    #expect(moment.allowedMate?.mateInN == 1)
    #expect(moment.allowedMate?.matingLineSANs == ["Qxf7#"])
    #expect(moment.missedMate == nil)
}

@Test func reportBuilderComputesClassificationCountsAndAccuracies() {
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    // White played 4 "best" moves (e4, Bc4, Qh5, Qxf7#).
    #expect(report.whiteClassificationCounts == [ClassificationCount(classification: .best, count: 4)])
    // Black played 2 "best" moves (e5, Nc6) and 1 blunder (Nf6).
    #expect(report.blackClassificationCounts.contains(ClassificationCount(classification: .best, count: 2)))
    #expect(report.blackClassificationCounts.contains(ClassificationCount(classification: .blunder, count: 1)))
    #expect(report.whiteAccuracy > report.blackAccuracy)
}

@Test func reportBuilderTakeawaysRestateTheAllowedMate() {
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }
    #expect(report.takeaways.contains { $0.contains("forced mate in 1") })
}

@Test func reportTextAddressesTheMatchingUsernameAsYou() {
    let input = scholarsMateInput(chessComUsername: "blackplayer") // case-insensitive
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }
    let text = ReportText.render(report)
    #expect(text.contains("your winning chances"))
    #expect(!text.contains("BlackPlayer's winning chances"))
}

@Test func reportTextDoesNotAddressAnyoneAsYouWithoutAMatchingUsername() {
    let input = scholarsMateInput(chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }
    let text = ReportText.render(report)
    // Winning-chances prose says "White"/"Black", not the player's real
    // name (user decision, UI/UX redesign session) - color reads faster
    // than usernames on a board-focused report.
    #expect(text.contains("Black's winning chances"))
    #expect(!text.contains("BlackPlayer's winning chances"))
    #expect(!text.contains(" your "))
}

@Test func reportTextRendersNoSignificantMistakesMessageOnACleanGame() {
    // Reuse the same fixture but strip the blunder ply down to "best" by
    // simply omitting keyMoments via a trivially clean 1-move game.
    let plies = [
        PlyRecord(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            lines: [RankedLine(rank: 1, scoreCentipawns: 20, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 20)],
            playedUCI: nil
        ),
        PlyRecord(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            lines: [RankedLine(rank: 1, scoreCentipawns: 25, mateIn: nil, principalVariationUCI: ["e7e5"], depth: 20)],
            playedUCI: "e2e4"
        ),
    ]
    let input = ReportInput(plies: plies, whiteName: "W", blackName: "B", result: "*", chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }
    #expect(report.keyMoments.isEmpty)
    let text = ReportText.render(report)
    #expect(text.contains("No significant mistakes at this analysis depth."))
    #expect(report.takeaways == ["A clean game: no mistakes or blunders at this analysis depth."])
}

@Test func takeawaysDoNotClaimACleanGameWhenAKeyMomentExistsWithNoAggregatePattern() {
    // A single blunder with no punishment/mate/recurring pattern and no
    // opening match: the "clean game" fallback must NOT fire just because
    // no *other* takeaway rule triggered - that claim is only true when
    // there are truly no key moments (regression test for a real bug
    // caught during the M5 E2E audit: a real analyzed game with a genuine
    // blunder still rendered "A clean game: no mistakes or blunders").
    let plies = [
        PlyRecord(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            lines: [RankedLine(rank: 1, scoreCentipawns: 20, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 20)],
            playedUCI: nil
        ),
        PlyRecord(
            fen: "rnbqkbnr/pppppppp/8/8/8/P7/1PPPPPPP/RNBQKBNR b KQkq - 0 1",
            lines: [RankedLine(rank: 1, scoreCentipawns: -800, mateIn: nil, principalVariationUCI: ["e7e5"], depth: 20)],
            playedUCI: "a2a3"
        ),
    ]
    let input = ReportInput(plies: plies, whiteName: "W", blackName: "B", result: "*", chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }
    #expect(!report.keyMoments.isEmpty)
    #expect(!report.takeaways.contains("A clean game: no mistakes or blunders at this analysis depth."))
}

// MARK: - FactAuditor

@Test func factAuditorDropsAFactWithACorruptedSAN() {
    let input = scholarsMateInput()
    let realFact = ThemeDetector.evalSwing(input: input, ply: 6, classification: .blunder)!
    let corrupted = EvalSwingFact(
        ply: realFact.ply, moverIsWhite: realFact.moverIsWhite, playedSAN: "Qxh7##",
        moverWinProbabilityBefore: realFact.moverWinProbabilityBefore, moverWinProbabilityAfter: realFact.moverWinProbabilityAfter,
        classification: realFact.classification
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsABetterMoveFactWithANonPrefixLine() {
    let input = scholarsMateInput()
    let real = ThemeDetector.betterMove(input: input, ply: 6)!
    let corrupted = BetterMoveFact(
        ply: real.ply, bestMoveSAN: real.bestMoveSAN, lineSANs: ["Qh4"],
        preMoveScoreCentipawns: real.preMoveScoreCentipawns, preMoveMateIn: real.preMoveMateIn
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsAPunishmentFactWithAWrongEval() {
    let input = scholarsMateInput()
    let real = ThemeDetector.punishment(input: input, ply: 6)!
    let corrupted = PunishmentFact(
        ply: real.ply, refutingSAN: real.refutingSAN, capturedPieceKind: real.capturedPieceKind,
        capturedSquare: real.capturedSquare, capturesJustMovedPiece: real.capturesJustMovedPiece,
        netMaterialGainForOpponent: 99
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsAMissedMateFactWithANonMatingLine() {
    let input = scholarsMateInput()
    // Fabricate a MissedMateFact (not actually produced by this fixture)
    // whose cited "mating" line does not actually end in checkmate.
    let bogus = MissedMateFact(ply: 6, mateInN: 1, matingLineSANs: ["Nf6"])
    #expect(!FactAuditor.verify(bogus, input: input))
}

@Test func fullReportKeyMomentSurvivesAuditUnchanged() {
    // Sanity check the positive path: a genuine, correctly-built moment is
    // never dropped by the auditor.
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report?.keyMoments.count == 1)
}
