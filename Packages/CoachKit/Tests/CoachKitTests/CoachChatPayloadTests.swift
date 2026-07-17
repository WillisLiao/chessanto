import AnalysisKit
import ChessCore
import Foundation
import Testing

@testable import CoachKit

private enum TestFixtureError: Error { case missingResource }

private func loadFixtureInput() throws -> ReportInput {
    guard let url = Bundle.module.url(forResource: "real-fixture-game-report-input", withExtension: "json") else {
        throw TestFixtureError.missingResource
    }
    return try JSONDecoder().decode(ReportInput.self, from: Data(contentsOf: url))
}

struct CoachChatPayloadTests {

    @Test func chatPayloadMatchesTheCommittedGoldenJSON() throws {
        let input = try loadFixtureInput()
        let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        #expect(report != nil)
        guard let report, let firstMoment = report.keyMoments.first else { return }

        let ply = firstMoment.ply
        let playedUCIs = (1...ply).compactMap { input.plies[$0].playedUCI }
        let mainlineSAN = ChessGame.sanLine(fromUCI: playedUCIs, startingFEN: input.plies[0].fen)
        let context = CoachChatContext(
            currentFEN: input.plies[ply].fen,
            isMainlinePosition: true,
            mainlineMovesSAN: mainlineSAN,
            currentPositionLines: input.plies[ply].lines,
            keyMomentOneLiner: ReportText.momentSummary(firstMoment, report: report),
            whiteName: report.whiteName,
            blackName: report.blackName,
            result: report.result,
            whiteAccuracy: report.whiteAccuracy,
            blackAccuracy: report.blackAccuracy
        )
        let payload = CoachPayloadBuilder.chatPayload(context)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(payload)
        let rendered = String(data: data, encoding: .utf8)!


        guard let goldenURL = Bundle.module.url(forResource: "real-fixture-first-moment-golden-chat-payload", withExtension: "json") else {
            Issue.record("missing golden chat payload fixture")
            return
        }
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(rendered == golden.trimmingCharacters(in: .newlines))
    }

    @Test func variationPositionPayloadCarriesPathSAN() {
        let context = CoachChatContext(
            currentFEN: "rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            isMainlinePosition: false,
            mainlineMovesSAN: ["e4", "e5"],
            variationBranchPly: 2,
            variationMovesSAN: ["Nf3", "Nf6"]
        )
        let payload = CoachPayloadBuilder.chatPayload(context)
        #expect(payload.isMainlinePosition == false)
        #expect(payload.movesSoFarSAN == "1. e4 e5")
        #expect(payload.variationPathSAN == "2. Nf3 Nf6")
    }

    @Test func unanalyzedGamePayloadHasNoLinesOrAccuracies() {
        let context = CoachChatContext(
            currentFEN: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            isMainlinePosition: true,
            mainlineMovesSAN: ["e4"]
        )
        let payload = CoachPayloadBuilder.chatPayload(context)
        #expect(payload.currentPositionLines.isEmpty)
        #expect(payload.whiteAccuracy == nil)
        #expect(payload.blackAccuracy == nil)
        #expect(payload.sideToMoveIsWhite == false)
    }

    // MARK: - Context-block inclusion toggling

    @Test func chatUserMessageOmitsContextBlockWhenPositionUnchanged() throws {
        let context = CoachChatContext(
            currentFEN: "startpos",
            isMainlinePosition: true,
            mainlineMovesSAN: []
        )
        let payload = CoachPayloadBuilder.chatPayload(context)

        let withContext = try CoachPrompt.chatUserMessage(question: "what about Nf3?", payload: payload, includeContext: true)
        #expect(withContext.contains("\"fen\""))
        #expect(withContext.contains("what about Nf3?"))

        let withoutContext = try CoachPrompt.chatUserMessage(question: "what about Nf3?", payload: payload, includeContext: false)
        #expect(withoutContext == "what about Nf3?")
        #expect(!withoutContext.contains("\"fen\""))
    }
}
