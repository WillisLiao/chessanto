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

private func forkReportInput() -> ReportInput {
    let preFEN = "7k/8/1r3b2/8/1p6/2N5/8/7K w - - 0 1"
    let postFEN = "7k/8/1r3b2/3N4/1p6/8/8/7K b - - 0 1"
    let preLine = RankedLine(rank: 1, scoreCentipawns: 500, mateIn: nil, principalVariationUCI: ["h1g1"], depth: 20)
    let postLine = RankedLine(rank: 1, scoreCentipawns: -500, mateIn: nil, principalVariationUCI: ["h8g8", "d5f6", "g8h8"], depth: 20)
    return ReportInput(
        plies: [
            PlyRecord(fen: preFEN, lines: [preLine], playedUCI: nil),
            PlyRecord(fen: postFEN, lines: [postLine], playedUCI: "c3d5"),
        ],
        whiteName: "WhitePlayer", blackName: "BlackPlayer", result: "1-0", chessComUsername: nil
    )
}

private func pinReportInput() -> ReportInput {
    let preFEN = "k7/3r4/8/8/8/8/4N3/4K3 b - - 0 1"
    let postFEN = "k7/4r3/8/8/8/8/4N3/4K3 w - - 1 2"
    return ReportInput(
        plies: [
            PlyRecord(
                fen: preFEN,
                lines: [RankedLine(rank: 1, scoreCentipawns: 0, mateIn: nil, principalVariationUCI: [], depth: 20)],
                playedUCI: nil
            ),
            PlyRecord(
                fen: postFEN,
                lines: [RankedLine(rank: 1, scoreCentipawns: 1000, mateIn: nil, principalVariationUCI: [], depth: 20)],
                playedUCI: "d7e7"
            ),
        ],
        whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil
    )
}

@Test func reportBuilderCarriesForkThroughAuditIntoKeyMoment() {
    let input = forkReportInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report?.keyMoments.count == 1)
    guard let moment = report?.keyMoments.first else { return }
    #expect(moment.fork?.targets == [
        ForkTarget(square: "b6", kind: .rook),
        ForkTarget(square: "f6", kind: .bishop),
    ])
    if let fork = moment.fork {
        #expect(FactAuditor.verify(fork, input: input))
    }
}

@Test func reportBuilderCarriesPinThroughAuditIntoKeyMoment() {
    let input = pinReportInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report?.keyMoments.count == 1)
    guard let moment = report?.keyMoments.first else { return }
    let expected = PinFact(
        ply: 1,
        pinningPieceKind: .rook,
        pinningSquare: "e7",
        pinnedPieceKind: .knight,
        pinnedSquare: "e2",
        kingSquare: "e1"
    )
    #expect(moment.pin == expected)
    #expect(FactAuditor.verify(expected, input: input))
}

@Test func factAuditorDropsAPinFactWithACorruptedField() {
    let input = pinReportInput()
    let real = ThemeDetector.pin(input: input, ply: 1)!
    let corrupted = PinFact(
        ply: real.ply,
        pinningPieceKind: real.pinningPieceKind,
        pinningSquare: real.pinningSquare,
        pinnedPieceKind: real.pinnedPieceKind,
        pinnedSquare: "e3",
        kingSquare: real.kingSquare
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func reportTextRendersAPinAsNeutralVerifiedAlignment() {
    let report = ReportBuilder.build(input: pinReportInput(), openingBook: OpeningBook.build(from: []))!
    let summary = ReportText.momentSummary(report.keyMoments[0], report: report)
    #expect(summary.contains("This move resulted in an absolute pin: the rook on e7 lined up the knight on e2 with its king on e1."))
    #expect(!summary.contains("because"))
    #expect(!summary.contains("cannot move"))
    #expect(!summary.contains("trapped"))
    #expect(!summary.contains("material"))
    #expect(!summary.contains("evaluation"))
    #expect(!summary.contains("caused"))
}

@Test func pinFactsDoNotChangeKeyMomentSelectionPriority() {
    let input = pinReportInput()
    #expect(KeyMomentSelector.selectPlies(classifications: [.excellent], input: input, register: .beginner).isEmpty)
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

    #expect(moment.ignoredThreat?.isCheckmate == true)
    #expect(moment.ignoredThreat?.threatenedSAN == "Qxf7#")

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

@Test func reportBuilderCountsIncludeAGenuineBrilliantMove() {
    // A queen sacrifice forcing a smothered mate: White plays the engine's
    // own top choice (Qd5-g8+), Black's only sensible reply accepts the
    // sacrifice, and White is left in a forced mate - a genuine brilliancy
    // reaching all the way through classification into the report's
    // aggregate counts, not just the raw classify() output.
    let preFEN = "5r1k/6pp/8/3Q2N1/8/8/8/6K1 w - - 0 1"
    let postFEN = "5rQk/6pp/8/6N1/8/8/8/6K1 b - - 1 1"
    let plies = [
        PlyRecord(
            fen: preFEN,
            lines: [
                RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 2, principalVariationUCI: ["d5g8", "f8g8", "g5f7"], depth: 20),
                RankedLine(rank: 2, scoreCentipawns: 50, mateIn: nil, principalVariationUCI: ["g5f7"], depth: 20),
            ],
            playedUCI: nil
        ),
        PlyRecord(
            fen: postFEN,
            lines: [RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 1, principalVariationUCI: ["f8g8", "g5f7"], depth: 20)],
            playedUCI: "d5g8"
        ),
    ]
    let input = ReportInput(plies: plies, whiteName: "WhitePlayer", blackName: "BlackPlayer", result: "*", chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    #expect(report.whiteClassificationCounts.contains(ClassificationCount(classification: .brilliant, count: 1)))
    #expect(!report.blackClassificationCounts.contains { $0.classification == .brilliant })
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

@Test func reportTextComposesMoveQualityFlagsWithoutImplyingCausation() {
    let report = ReportBuilder.build(input: scholarsMateInput(), openingBook: OpeningBook.build(from: []))!
    let base = report.keyMoments[0]
    let quality = MoveQualityFact(
        ply: base.ply,
        movedPieceKind: .queen,
        isCapture: true,
        capturedPieceKind: .pawn,
        isCheck: true,
        isCheckmate: true,
        isRedevelopedPiece: true,
        isMovedTwiceBeforeCastling: true,
        isEarlyQueenMove: true
    )
    let moment = KeyMoment(
        ply: base.ply,
        evalSwing: base.evalSwing,
        betterMove: base.betterMove,
        punishment: base.punishment,
        ignoredThreat: base.ignoredThreat,
        missedMate: base.missedMate,
        allowedMate: base.allowedMate,
        moveQuality: quality
    )
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("Move quality: captured a pawn, delivered checkmate, moved the queen again before castling, and brought the queen out before move 5."))
    #expect(!summary.contains("gave check"))
    #expect(!summary.contains("moved the queen again in the opening"))
    #expect(!summary.contains("because"))
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

@Test func takeawaysIncludeRecurringIgnoredThreats() {
    func rank1(_ cp: Int?, _ mate: Int?, _ pv: [String]) -> [RankedLine] {
        [RankedLine(rank: 1, scoreCentipawns: cp, mateIn: mate, principalVariationUCI: pv, depth: 20)]
    }
    let plies = [
        PlyRecord(fen: "4k3/p6p/8/2b5/8/4B3/8/4K3 b - - 0 1", lines: rank1(0, nil, ["c5e3"]), playedUCI: nil),
        PlyRecord(fen: "4k3/p7/7p/2b5/8/4B3/8/4K3 w - - 0 2", lines: rank1(300, nil, ["e3c5"]), playedUCI: "h7h6"),
        PlyRecord(fen: "4k3/p7/7p/2B5/8/8/8/4K3 b - - 0 2", lines: rank1(300, nil, ["a7a6"]), playedUCI: "e3c5"),
        PlyRecord(fen: "8/p2k4/7p/2B5/8/8/8/4K3 w - - 1 3", lines: rank1(600, nil, ["c5a7"]), playedUCI: "e8d7"),
        PlyRecord(fen: "8/B2k4/7p/8/8/8/8/4K3 b - - 0 3", lines: rank1(600, nil, ["d7e6"]), playedUCI: "c5a7"),
    ]
    let input = ReportInput(plies: plies, whiteName: "WhitePlayer", blackName: "BlackPlayer", result: "1-0", chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    #expect(report.takeaways.contains { $0.contains("2 of BlackPlayer's mistakes ignored an active threat from the opponent (1..., 2...)") })
    #expect(!report.takeaways.contains { $0.contains("WhitePlayer") && $0.contains("ignored an active threat") })
}

@Test func takeawaysIncludeGeneralErrorFrequency() {
    func rank1(_ cp: Int?, _ mate: Int?, _ pv: [String]) -> [RankedLine] {
        [RankedLine(rank: 1, scoreCentipawns: cp, mateIn: mate, principalVariationUCI: pv, depth: 20)]
    }
    let plies = [
        PlyRecord(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", lines: rank1(20, nil, ["e2e4"]), playedUCI: nil),
        PlyRecord(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", lines: rank1(25, nil, ["e7e5"]), playedUCI: "e2e4"),
        PlyRecord(fen: "rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", lines: rank1(210, nil, ["d2d4"]), playedUCI: "e7e6"),
        PlyRecord(fen: "rnbqkbnr/pppp1ppp/4p3/8/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", lines: rank1(0, nil, ["d7d5"]), playedUCI: "g1f3"),
        PlyRecord(fen: "rnbqkbnr/1ppp1ppp/p3p3/8/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3", lines: rank1(300, nil, ["b1c3"]), playedUCI: "a7a6"),
        PlyRecord(fen: "rnbqkbnr/1ppp1ppp/p3p3/8/4P3/2N2N2/PPPP1PPP/R1BQKB1R b KQkq - 1 3", lines: rank1(-100, nil, ["g8f6"]), playedUCI: "b1c3"),
        PlyRecord(fen: "rnbqkbnr/1ppp1pp1/p3p2p/8/4P3/2N2N2/PPPP1PPP/R1BQKB1R w KQkq - 0 4", lines: rank1(400, nil, ["d2d4"]), playedUCI: "h7h6"),
        PlyRecord(fen: "rnbqkbnr/1ppp1pp1/p3p2p/8/3PP3/2N2N2/PPP2PPP/R1BQKB1R b KQkq - 0 4", lines: rank1(400, nil, ["d7d5"]), playedUCI: "d2d4"),
        PlyRecord(fen: "rnbqkbnr/1pp2pp1/p3p2p/3p4/3PP3/2N2N2/PPP2PPP/R1BQKB1R w KQkq - 0 5", lines: rank1(400, nil, ["e4d5"]), playedUCI: "d7d5"),
    ]
    let input = ReportInput(plies: plies, whiteName: "WhitePlayer", blackName: "BlackPlayer", result: "1-0", chessComUsername: nil)
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    #expect(report.takeaways == [
        "BlackPlayer made 3 errors across 4 scored moves (1 inaccuracy, 1 mistake, 1 blunder).",
        "WhitePlayer made 1 error across 4 scored moves (1 inaccuracy)."
    ])
}

@Test func takeawaysPrioritizeRareTacticalMomentsOverGeneralErrors() {
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report != nil)
    guard let report else { return }

    #expect(report.takeaways.count >= 2)
    #expect(report.takeaways[0].contains("forced mate in 1"))
    #expect(report.takeaways[1].contains("BlackPlayer made 1 error across 3 scored moves (1 blunder)."))
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

@Test func factAuditorDropsAnIgnoredThreatFactWithACorruptedSAN() {
    let input = scholarsMateInput()
    let real = ThemeDetector.ignoredThreat(input: input, ply: 6)!
    let corrupted = IgnoredThreatFact(
        ply: real.ply, threatenedSAN: "Qxf7##", capturedPieceKind: real.capturedPieceKind,
        capturedSquare: real.capturedSquare, netMaterialGainForOpponent: real.netMaterialGainForOpponent,
        isCheckmate: real.isCheckmate
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsAnIgnoredThreatFactWithAWrongMaterialGain() {
    let input = scholarsMateInput()
    let real = ThemeDetector.ignoredThreat(input: input, ply: 6)!
    let corrupted = IgnoredThreatFact(
        ply: real.ply, threatenedSAN: real.threatenedSAN, capturedPieceKind: real.capturedPieceKind,
        capturedSquare: real.capturedSquare, netMaterialGainForOpponent: 99,
        isCheckmate: real.isCheckmate
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsAForkFactWithAWrongWonTarget() {
    let input = forkReportInput()
    let real = ThemeDetector.fork(input: input, ply: 1)!
    let corrupted = ForkFact(
        ply: real.ply,
        forkingPieceKind: real.forkingPieceKind,
        destinationSquare: real.destinationSquare,
        targets: real.targets,
        wonTarget: ForkTarget(square: "b6", kind: .rook),
        netMaterialGain: real.netMaterialGain
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func factAuditorDropsAMoveQualityFactWithCorruptedField() {
    let input = scholarsMateInput()
    let real = ThemeDetector.moveQuality(input: input, ply: 6)!
    let corrupted = MoveQualityFact(
        ply: real.ply,
        movedPieceKind: .queen, // was .knight
        isCapture: real.isCapture,
        capturedPieceKind: real.capturedPieceKind,
        isCheck: real.isCheck,
        isCheckmate: real.isCheckmate,
        isRedevelopedPiece: real.isRedevelopedPiece,
        isMovedTwiceBeforeCastling: real.isMovedTwiceBeforeCastling,
        isEarlyQueenMove: real.isEarlyQueenMove
    )
    #expect(!FactAuditor.verify(corrupted, input: input))
}

@Test func fullReportKeyMomentSurvivesAuditUnchanged() {
    // Sanity check the positive path: a genuine, correctly-built moment is
    // never dropped by the auditor.
    let input = scholarsMateInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.build(from: []))
    #expect(report?.keyMoments.count == 1)
    guard let moment = report?.keyMoments.first else { return }
    #expect(moment.moveQuality != nil)
    #expect(moment.moveQuality?.movedPieceKind == .knight)
    #expect(moment.moveQuality?.isCapture == false)
    #expect(moment.moveQuality?.isCheck == false)
    #expect(moment.moveQuality?.isRedevelopedPiece == false)
}
