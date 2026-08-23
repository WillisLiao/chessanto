import Testing

@testable import AnalysisKit

/// `ReportText`'s register-driven branching (P4.1): beginner drops win
/// percentages and eval-label numerals, and shortens the better-line quote;
/// intermediate/advanced keep today's wording exactly.
private func makeReport(register: RatingRegister, keyMoments: [KeyMoment] = []) -> GameReport {
    GameReport(
        whiteName: "White",
        blackName: "Black",
        result: "*",
        chessComUsername: nil,
        whiteAccuracy: 90,
        blackAccuracy: 80,
        whiteClassificationCounts: [],
        blackClassificationCounts: [],
        opening: nil,
        keyMoments: keyMoments,
        takeaways: [],
        register: register
    )
}

private func makeMoment(before: Double, after: Double, moverIsWhite: Bool = true, lineSANs: [String] = ["d4", "Nf3", "Nc6", "Bb5", "a6", "Ba4"]) -> KeyMoment {
    KeyMoment(
        ply: 1,
        evalSwing: EvalSwingFact(
            ply: 1,
            moverIsWhite: moverIsWhite,
            playedSAN: "e4",
            moverWinProbabilityBefore: before,
            moverWinProbabilityAfter: after,
            classification: .mistake
        ),
        betterMove: BetterMoveFact(
            ply: 1,
            bestMoveSAN: "d4",
            lineSANs: lineSANs,
            preMoveScoreCentipawns: 120,
            preMoveMateIn: nil
        ),
        punishment: nil,
        missedMate: nil,
        allowedMate: nil
    )
}

@Test func beginnerEvalSwingSentenceHasNoPercentSign() {
    let moment = makeMoment(before: 60, after: 30)
    let report = makeReport(register: .beginner, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(!summary.contains("%"))
}

@Test func intermediateAndAdvancedKeepWinPercentageWording() {
    for register: RatingRegister in [.intermediate, .advanced] {
        let moment = makeMoment(before: 60, after: 30)
        let report = makeReport(register: register, keyMoments: [moment])
        let summary = ReportText.momentSummary(moment, report: report)
        #expect(summary.contains("%"))
    }
}

@Test func beginnerBetterMoveLineIsAtMostTwoPliesAndHasNoEvalLabel() {
    let moment = makeMoment(before: 60, after: 30)
    let report = makeReport(register: .beginner, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("(d4 Nf3)"))
    #expect(!summary.contains("Nc6"))
    #expect(!summary.contains("keeping the evaluation"))
}

@Test func advancedBetterMoveLineKeepsUpToSixPliesAndTheEvalLabel() {
    let moment = makeMoment(before: 60, after: 30)
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("(d4 Nf3 Nc6 Bb5 a6 Ba4)"))
    #expect(summary.contains("keeping the evaluation"))
}

@Test func betterMoveSentenceWithASingleMoveLineHasNoDanglingParenthesis() {
    let moment = makeMoment(before: 60, after: 30, lineSANs: ["d4"])
    for register: RatingRegister in [.beginner, .intermediate, .advanced] {
        let report = makeReport(register: register, keyMoments: [moment])
        let summary = ReportText.momentSummary(moment, report: report)
        #expect(!summary.contains("("))
        #expect(!summary.contains(")"))
    }
}

@Test func includingMoveLabelFalseOmitsOnlyTheLeadingMoveToken() {
    let moment = makeMoment(before: 60, after: 30)
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let withLabel = ReportText.momentSummary(moment, report: report)
    let withoutLabel = ReportText.momentSummary(moment, report: report, includingMoveLabel: false)
    #expect(withLabel == "1. " + withoutLabel)
}

@Test func beginnerStateClauseDescribesEachWinProbabilityBand() {
    let bands: [(before: Double, after: Double, expectedSubstring: String)] = [
        (95, 80, "still winning, just by less"),
        (95, 60, "still better"),
        (95, 47, "position is level now"),
        (95, 35, "better now"),
        (95, 10, "winning now"),
    ]
    for band in bands {
        let moment = makeMoment(before: band.before, after: band.after)
        let report = makeReport(register: .beginner, keyMoments: [moment])
        let summary = ReportText.momentSummary(moment, report: report)
        #expect(summary.contains(band.expectedSubstring))
    }
}

// MARK: - IgnoredThreatFact rendering

@Test func ignoredThreatSentenceRendersCheckmate() {
    let moment = KeyMoment(
        ply: 6,
        evalSwing: EvalSwingFact(
            ply: 6, moverIsWhite: false, playedSAN: "Nf6",
            moverWinProbabilityBefore: 50, moverWinProbabilityAfter: 0, classification: .blunder
        ),
        betterMove: nil,
        punishment: nil,
        ignoredThreat: IgnoredThreatFact(
            ply: 6, threatenedSAN: "Qxf7#", capturedPieceKind: .pawn, capturedSquare: "f7",
            netMaterialGainForOpponent: 0, isCheckmate: true
        ),
        missedMate: nil,
        allowedMate: nil
    )
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("This ignored the threat of checkmate: Qxf7#."))
}

@Test func ignoredThreatSentenceRendersPieceWon() {
    let moment = KeyMoment(
        ply: 2,
        evalSwing: EvalSwingFact(
            ply: 2, moverIsWhite: false, playedSAN: "h6",
            moverWinProbabilityBefore: 50, moverWinProbabilityAfter: 20, classification: .mistake
        ),
        betterMove: nil,
        punishment: nil,
        ignoredThreat: IgnoredThreatFact(
            ply: 2, threatenedSAN: "Bxc5", capturedPieceKind: .bishop, capturedSquare: "c5",
            netMaterialGainForOpponent: 3, isCheckmate: false
        ),
        missedMate: nil,
        allowedMate: nil
    )
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("This ignored the threat to the bishop on c5: Bxc5 winning the bishop."))
}

@Test func ignoredThreatSentenceRendersMaterialWon() {
    let moment = KeyMoment(
        ply: 2,
        evalSwing: EvalSwingFact(
            ply: 2, moverIsWhite: false, playedSAN: "a6",
            moverWinProbabilityBefore: 50, moverWinProbabilityAfter: 30, classification: .inaccuracy
        ),
        betterMove: nil,
        punishment: nil,
        ignoredThreat: IgnoredThreatFact(
            ply: 2, threatenedSAN: "Bxd8", capturedPieceKind: .rook, capturedSquare: "d8",
            netMaterialGainForOpponent: 2, isCheckmate: false
        ),
        missedMate: nil,
        allowedMate: nil
    )
    let report = makeReport(register: .beginner, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("This ignored the threat to the rook on d8: Bxd8 winning material."))
}

@Test func ignoredThreatSuppressesRedundantUnrelatedHangPunishmentSentence() {
    let moment = KeyMoment(
        ply: 2,
        evalSwing: EvalSwingFact(
            ply: 2, moverIsWhite: false, playedSAN: "h6",
            moverWinProbabilityBefore: 50, moverWinProbabilityAfter: 20, classification: .mistake
        ),
        betterMove: nil,
        punishment: PunishmentFact(
            ply: 2, refutingSAN: "Bxc5", capturedPieceKind: .bishop, capturedSquare: "c5",
            capturesJustMovedPiece: false, netMaterialGainForOpponent: 3
        ),
        ignoredThreat: IgnoredThreatFact(
            ply: 2, threatenedSAN: "Bxc5", capturedPieceKind: .bishop, capturedSquare: "c5",
            netMaterialGainForOpponent: 3, isCheckmate: false
        ),
        missedMate: nil,
        allowedMate: nil
    )
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("This ignored the threat to the bishop on c5: Bxc5 winning the bishop."))
    #expect(!summary.contains("This also left the bishop on c5 hanging"))
}

@Test func forkSentenceNamesForkSquareTargetsAndVerifiedWonTarget() {
    let moment = KeyMoment(
        ply: 1,
        evalSwing: EvalSwingFact(
            ply: 1, moverIsWhite: true, playedSAN: "Nd5",
            moverWinProbabilityBefore: 90, moverWinProbabilityAfter: 55, classification: .blunder
        ),
        fork: ForkFact(
            ply: 1,
            forkingPieceKind: .knight,
            destinationSquare: "d5",
            targets: [
                ForkTarget(square: "b6", kind: .rook),
                ForkTarget(square: "f6", kind: .bishop),
            ],
            wonTarget: ForkTarget(square: "f6", kind: .bishop),
            netMaterialGain: 3
        )
    )
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("fork by the knight on d5"))
    #expect(summary.contains("rook on b6 and bishop on f6"))
    #expect(summary.contains("won the bishop on f6"))
    #expect(summary.contains("net material gain: 3"))
}

@Test func mateSentenceTakesPrecedenceOverForkSentence() {
    let moment = KeyMoment(
        ply: 1,
        evalSwing: EvalSwingFact(
            ply: 1, moverIsWhite: true, playedSAN: "Nd5",
            moverWinProbabilityBefore: 90, moverWinProbabilityAfter: 10, classification: .blunder
        ),
        fork: ForkFact(
            ply: 1,
            forkingPieceKind: .knight,
            destinationSquare: "d5",
            targets: [ForkTarget(square: "b6", kind: .rook), ForkTarget(square: "f6", kind: .bishop)],
            wonTarget: ForkTarget(square: "f6", kind: .bishop),
            netMaterialGain: 3
        ),
        missedMate: MissedMateFact(ply: 1, mateInN: 1, matingLineSANs: nil)
    )
    let report = makeReport(register: .advanced, keyMoments: [moment])
    let summary = ReportText.momentSummary(moment, report: report)
    #expect(summary.contains("missed a forced mate in 1"))
    #expect(!summary.contains("fork by the knight"))
}
