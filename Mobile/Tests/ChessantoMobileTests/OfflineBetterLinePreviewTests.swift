import CompanionDomain
import Foundation
import Testing
@testable import ChessantoMobile

@Suite("Offline better-line preview")
struct OfflineBetterLinePreviewTests {
    @Test("preview is created only by the explicit better-line action")
    func explicitActionBuildsPreviewFrames() throws {
        let report = makeReport()
        let moment = try #require(report.keyMoments.first)

        let preview = try #require(
            OfflineBetterLinePreview(report: report, moment: moment)
        )

        #expect(preview.frames.map(\.san) == [nil, "e4", "e5"])
        #expect(preview.frames.count == 3)
    }

    private func makeReport() -> PortableAnalysisReport {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        return PortableAnalysisReport(
            protocolVersion: .v1,
            id: ReportID("report-1"),
            gameID: CompanionGameID("game-1"),
            generatedAt: Date(timeIntervalSince1970: 100),
            analysisQuality: .standard,
            metadata: PortableGameMetadata(
                white: "Willis",
                black: "Coach",
                result: "*",
                playedAt: nil,
                timeControl: nil
            ),
            pgn: "1. d4",
            positions: [
                PortablePosition(ply: 0, fen: start, playedSAN: nil),
                PortablePosition(
                    ply: 1,
                    fen:
                        "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
                    playedSAN: "d4"
                ),
            ],
            evaluations: [],
            rankedLines: [
                PortableRankedLine(
                    ply: 0,
                    rank: 1,
                    depth: 18,
                    scoreCentipawns: 20,
                    mateIn: nil,
                    principalVariationUCI: ["e2e4", "e7e5"],
                    principalVariationSAN: ["e4", "e5"]
                )
            ],
            classifications: [],
            opening: nil,
            keyMoments: [
                PortableKeyMoment(
                    ply: 1,
                    canonicalPlayedSAN: "d4",
                    classification: "inaccuracy",
                    summary: "Prefer the central break.",
                    betterLineSAN: ["e4", "e5"],
                    playedContinuationSAN: [],
                    narration: nil
                )
            ],
            takeaways: []
        )
    }
}
