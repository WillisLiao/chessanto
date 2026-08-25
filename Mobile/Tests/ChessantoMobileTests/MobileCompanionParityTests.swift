import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import ChessantoMobile

@Suite("Mobile companion parity")
struct MobileCompanionParityTests {
    @Test("classification style maps all classifications to expected labels and marks")
    func classificationStyleMapping() {
        #expect(MobileClassificationStyle.label(for: "best") == "Best")
        #expect(MobileClassificationStyle.label(for: "brilliant") == "Brilliant")
        #expect(MobileClassificationStyle.label(for: "excellent") == "Excellent")
        #expect(MobileClassificationStyle.label(for: "good") == "Good")
        #expect(MobileClassificationStyle.label(for: "inaccuracy") == "Inaccuracy")
        #expect(MobileClassificationStyle.label(for: "mistake") == "Mistake")
        #expect(MobileClassificationStyle.label(for: "blunder") == "Blunder")
        #expect(MobileClassificationStyle.label(for: "missedWin") == "Missed Win")
        #expect(MobileClassificationStyle.label(for: "missed win") == "Missed Win")
        #expect(MobileClassificationStyle.label(for: "book") == "Book")
        #expect(MobileClassificationStyle.label(for: "forced") == "Forced")

        #expect(MobileClassificationStyle.compactMark(for: "best") == "★")
        #expect(MobileClassificationStyle.compactMark(for: "brilliant") == "!!")
        #expect(MobileClassificationStyle.compactMark(for: "inaccuracy") == "?!")
        #expect(MobileClassificationStyle.compactMark(for: "mistake") == "?")
        #expect(MobileClassificationStyle.compactMark(for: "blunder") == "??")
        #expect(MobileClassificationStyle.compactMark(for: "good") == nil)
    }

    @Test("mobile colors adapt across light and dark user interface styles")
    func mobileColorsAdapt() {
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)

        let paperLight = UIColor(hex: "#FAF9F6")
        let paperDark = UIColor(hex: "#1C1A17")
        let dynamicPaper = UIColor { trait in
            trait.userInterfaceStyle == .dark ? paperDark : paperLight
        }

        #expect(dynamicPaper.resolvedColor(with: lightTrait) == paperLight)
        #expect(dynamicPaper.resolvedColor(with: darkTrait) == paperDark)
    }

    @Test("rich report with multiple fact types and takeaways round trips through cache")
    func richReportRoundTripsThroughCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = OfflineReportCache(rootURL: root)

        let report = makeRichReport()
        try await cache.save(report)

        let loaded = try #require(try await cache.report(id: report.id))
        #expect(loaded.id == report.id)
        #expect(loaded.keyMoments.count == 3)
        #expect(loaded.takeaways.count == 3)
        #expect(loaded.takeaways.contains { $0.contains("time pressure") })
        #expect(loaded.keyMoments.contains { $0.summary.contains("absolute pin") })
        #expect(loaded.keyMoments.contains { $0.summary.contains("fork") })
    }

    private func makeRichReport() -> PortableAnalysisReport {
        PortableAnalysisReport(
            protocolVersion: .v1,
            id: ReportID("parity-report-1"),
            gameID: CompanionGameID("game-parity"),
            generatedAt: Date(timeIntervalSince1970: 1_721_260_800),
            analysisQuality: .deep,
            metadata: PortableGameMetadata(
                white: "artin10862",
                black: "MagnusCarlsen",
                result: "0-1",
                playedAt: Date(timeIntervalSince1970: 1_721_174_400),
                timeControl: "180+2"
            ),
            pgn: "1. e4 c5 2. Nf3 d6",
            positions: [
                PortablePosition(ply: 0, fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", playedSAN: nil),
                PortablePosition(ply: 1, fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", playedSAN: "e4"),
                PortablePosition(ply: 2, fen: "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2", playedSAN: "c5"),
                PortablePosition(ply: 3, fen: "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", playedSAN: "Nf3"),
                PortablePosition(ply: 4, fen: "rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3", playedSAN: "d6"),
            ],
            evaluations: [
                PortableEvaluation(ply: 0, scoreCentipawns: 20, mateIn: nil),
                PortableEvaluation(ply: 1, scoreCentipawns: 22, mateIn: nil),
                PortableEvaluation(ply: 2, scoreCentipawns: 18, mateIn: nil),
                PortableEvaluation(ply: 3, scoreCentipawns: 19, mateIn: nil),
                PortableEvaluation(ply: 4, scoreCentipawns: 15, mateIn: nil),
            ],
            rankedLines: [
                PortableRankedLine(
                    ply: 3,
                    rank: 1,
                    depth: 18,
                    scoreCentipawns: 19,
                    mateIn: nil,
                    principalVariationUCI: ["f3d4"],
                    principalVariationSAN: ["Nd4"]
                )
            ],
            classifications: [
                PortableMoveClassification(ply: 1, canonicalSAN: "e4", classification: "book"),
                PortableMoveClassification(ply: 2, canonicalSAN: "c5", classification: "book"),
                PortableMoveClassification(ply: 3, canonicalSAN: "Nf3", classification: "best"),
                PortableMoveClassification(ply: 4, canonicalSAN: "d6", classification: "inaccuracy"),
            ],
            opening: PortableOpening(eco: "B50", name: "Sicilian Defense", deepestBookPly: 3),
            keyMoments: [
                PortableKeyMoment(
                    ply: 15,
                    canonicalPlayedSAN: "Bb5+",
                    classification: "best",
                    summary: "This move resulted in an absolute pin: the bishop on b5 lined up the knight on c6 with its king on e8.",
                    betterLineSAN: ["Bb5+"],
                    playedContinuationSAN: ["Bd7"],
                    narration: AuditedCoachNarration(
                        id: NarrationID("narration-pin"),
                        text: "This move resulted in an absolute pin: the bishop on b5 lined up the knight on c6 with its king on e8.",
                        source: .verifiedCoach,
                        mood: .instructive
                    )
                ),
                PortableKeyMoment(
                    ply: 24,
                    canonicalPlayedSAN: "Nd5",
                    classification: "mistake",
                    summary: "This fork by the knight on d5 attacked queen on b6 and rook on e7; it won the rook on e7 (net material gain: 2).",
                    betterLineSAN: ["Nf3"],
                    playedContinuationSAN: ["Qd8"],
                    narration: AuditedCoachNarration(
                        id: NarrationID("narration-fork"),
                        text: "This fork by the knight on d5 attacked queen on b6 and rook on e7; it won the rook on e7 (net material gain: 2).",
                        source: .verifiedCoach,
                        mood: .concerned
                    )
                ),
                PortableKeyMoment(
                    ply: 31,
                    canonicalPlayedSAN: "Qe2",
                    classification: "blunder",
                    summary: "31. Qe2 drops White's winning chances from 65% to 12%. This ignored the threat of checkmate: Qxf2#.",
                    betterLineSAN: ["Qf3", "Qxf3"],
                    playedContinuationSAN: ["Qxf2#"],
                    narration: AuditedCoachNarration(
                        id: NarrationID("narration-mate"),
                        text: "31. Qe2 drops White's winning chances from 65% to 12%. This ignored the threat of checkmate: Qxf2#.",
                        source: .verifiedCoach,
                        mood: .concerned
                    )
                ),
            ],
            takeaways: [
                "White missed a forced mate in 3 on move 22.",
                "artin10862 made 2 errors under time pressure (moves 24, 31 with under 30s remaining).",
                "MagnusCarlsen made 1 error across 26 scored moves (1 inaccuracy)."
            ]
        )
    }
}
