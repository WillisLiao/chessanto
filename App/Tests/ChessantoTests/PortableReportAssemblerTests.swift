import ChessCore
import CompanionDomain
import Foundation
import Persistence
import Testing
@testable import Chessanto

@Suite("Portable report assembler")
struct PortableReportAssemblerTests {
    @Test("played continuation starts after the key move")
    func playedContinuationStartsAfterTheKeyMove() {
        #expect(
            PortableReportAssembler.playedContinuationSAN(
                afterPly: 2,
                mainlineSAN: ["e4", "e5", "Nf3", "Nc6"]
            ) == ["Nf3", "Nc6"]
        )
    }

    @Test("portable report keeps canonical SAN and complete offline analysis")
    func portableReportKeepsCanonicalSANAndCompleteOfflineAnalysis() throws {
        let pgn = """
            [White "Willis"]
            [Black "Coach"]
            [Result "*"]

            1. Nf3 Nf6 *
            """
        let game = try ChessGame(pgn: pgn)
        let indices = [game.startIndex] + game.mainlineIndices
        let fens = indices.compactMap { game.fen(at: $0) }
        let record = GameRecord(
            id: 1,
            source: .pgnImport,
            pgn: pgn,
            white: "Willis",
            black: "Coach",
            result: "*"
        )
        let rows = [
            AnalysisRecord(
                gameId: 1,
                plyIndex: 0,
                fen: fens[0],
                depth: 18,
                scoreCentipawns: 20,
                principalVariation: "g1f3 g8f6",
                multiPVRank: 1,
                qualityPreset: .standard,
                analyzedAt: Date(timeIntervalSince1970: 100)
            ),
            AnalysisRecord(
                gameId: 1,
                plyIndex: 1,
                fen: fens[1],
                depth: 18,
                scoreCentipawns: 18,
                principalVariation: "g8f6",
                multiPVRank: 1,
                qualityPreset: .standard,
                analyzedAt: Date(timeIntervalSince1970: 101)
            ),
            AnalysisRecord(
                gameId: 1,
                plyIndex: 2,
                fen: fens[2],
                depth: 18,
                scoreCentipawns: 17,
                principalVariation: "e2e4",
                multiPVRank: 1,
                qualityPreset: .standard,
                analyzedAt: Date(timeIntervalSince1970: 102)
            ),
        ]

        let report = try #require(
            PortableReportAssembler.assemble(
                id: ReportID("report-1"),
                gameID: CompanionGameID("game-a"),
                record: record,
                quality: .standard,
                analysisRows: rows,
                chessComUsername: "Willis",
                narrationsByPly: [:],
                generatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(report.pgn == pgn)
        #expect(report.positions.map(\.playedSAN) == [nil, "Nf3", "Nf6"])
        #expect(report.evaluations.count == 3)
        #expect(report.rankedLines.first?.principalVariationSAN.first == "Nf3")
        #expect(report.classifications.count == 2)
        #expect(report.takeaways.isEmpty == false)
    }
}
