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
