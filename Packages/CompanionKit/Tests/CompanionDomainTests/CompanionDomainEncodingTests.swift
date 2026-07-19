import Foundation
import Testing
@testable import CompanionDomain

@Suite("Companion domain canonical encoding")
struct CompanionDomainEncodingTests {
    @Test("versioned catalog has stable golden encoding")
    func versionedCatalogHasStableGoldenEncoding() throws {
        let catalog = GameCatalogSnapshot(
            protocolVersion: .v1,
            endpointID: EndpointID("mac-1"),
            version: 7,
            generatedAt: Date(timeIntervalSince1970: 1_721_260_800),
            games: [
                CatalogGame(
                    id: CompanionGameID("game-a"),
                    white: "Willis",
                    black: "Coach",
                    result: "1-0",
                    playedAt: Date(timeIntervalSince1970: 1_721_174_400),
                    isAnalyzed: true
                ),
            ]
        )

        let encoded = try CanonicalCoding.encode(catalog)

        #expect(
            String(decoding: encoded, as: UTF8.self)
                == #"{"endpointID":"mac-1","games":[{"black":"Coach","id":"game-a","isAnalyzed":true,"playedAt":"2024-07-17T00:00:00Z","result":"1-0","white":"Willis"}],"generatedAt":"2024-07-18T00:00:00Z","protocolVersion":1,"version":7}"#
        )
        #expect(try CanonicalCoding.decode(GameCatalogSnapshot.self, from: encoded) == catalog)
    }

    @Test("analysis request has stable golden encoding")
    func analysisRequestHasStableGoldenEncoding() throws {
        let request = AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID("request-1"),
            endpointID: EndpointID("mac-1"),
            senderDeviceID: CompanionDeviceID("phone-1"),
            gameID: CompanionGameID("game-a"),
            quality: .deep,
            createdAt: Date(timeIntervalSince1970: 1_721_260_800),
            expiresAt: Date(timeIntervalSince1970: 1_721_347_200),
            retryOf: AnalysisRequestID("request-0")
        )

        let encoded = try CanonicalCoding.encode(request)

        #expect(
            String(decoding: encoded, as: UTF8.self)
                == #"{"createdAt":"2024-07-18T00:00:00Z","endpointID":"mac-1","expiresAt":"2024-07-19T00:00:00Z","gameID":"game-a","id":"request-1","protocolVersion":1,"quality":"deep","retryOf":"request-0","senderDeviceID":"phone-1"}"#
        )
        #expect(try CanonicalCoding.decode(AnalysisRequest.self, from: encoded) == request)
    }

    @Test("job snapshot has stable golden encoding")
    func jobSnapshotHasStableGoldenEncoding() throws {
        let snapshot = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: AnalysisRequestID("request-1"),
            state: .analyzing,
            reception: .accepted,
            progress: AnalysisProgress(completedPlies: 18, totalPlies: 42),
            updatedAt: Date(timeIntervalSince1970: 1_721_261_100),
            terminalReason: nil,
            reportID: nil
        )

        let encoded = try CanonicalCoding.encode(snapshot)

        #expect(
            String(decoding: encoded, as: UTF8.self)
                == #"{"progress":{"completedPlies":18,"totalPlies":42},"protocolVersion":1,"reception":"accepted","requestID":"request-1","state":"analyzing","updatedAt":"2024-07-18T00:05:00Z"}"#
        )
        #expect(try CanonicalCoding.decode(AnalysisJobSnapshot.self, from: encoded) == snapshot)
    }

    @Test("portable report has stable golden encoding and canonical SAN")
    func portableReportHasStableGoldenEncodingAndCanonicalSAN() throws {
        let report = PortableAnalysisReport(
            protocolVersion: .v1,
            id: ReportID("report-1"),
            gameID: CompanionGameID("game-a"),
            generatedAt: Date(timeIntervalSince1970: 1_721_260_800),
            analysisQuality: .standard,
            metadata: PortableGameMetadata(
                white: "Willis",
                black: "Coach",
                result: "1-0",
                playedAt: nil,
                timeControl: "600"
            ),
            pgn: "[Result \"1-0\"]\n\n1. Nf3",
            positions: [
                PortablePosition(ply: 0, fen: "start", playedSAN: nil),
                PortablePosition(ply: 1, fen: "after-nf3", playedSAN: "Nf3"),
            ],
            evaluations: [
                PortableEvaluation(ply: 0, scoreCentipawns: 18, mateIn: nil),
            ],
            rankedLines: [
                PortableRankedLine(
                    ply: 0,
                    rank: 1,
                    depth: 18,
                    scoreCentipawns: 18,
                    mateIn: nil,
                    principalVariationUCI: ["g1f3"],
                    principalVariationSAN: ["Nf3"]
                ),
            ],
            classifications: [
                PortableMoveClassification(ply: 1, canonicalSAN: "Nf3", classification: "best"),
            ],
            opening: PortableOpening(eco: "A06", name: "Zukertort Opening", deepestBookPly: 1),
            keyMoments: [
                PortableKeyMoment(
                    ply: 1,
                    canonicalPlayedSAN: "Nf3",
                    classification: "best",
                    summary: "Nf3 keeps the position balanced.",
                    betterLineSAN: ["Nf3"],
                    playedContinuationSAN: [],
                    narration: AuditedCoachNarration(
                        id: NarrationID("narration-1"),
                        text: "Nf3 keeps the position balanced.",
                        source: .verifiedCoach,
                        mood: .encouraging
                    )
                ),
            ],
            takeaways: ["Develop before attacking."]
        )

        let encoded = try CanonicalCoding.encode(report)
        let decoded = try CanonicalCoding.decode(PortableAnalysisReport.self, from: encoded)

        #expect(decoded == report)
        #expect(decoded.positions[1].playedSAN == "Nf3")
        #expect(decoded.keyMoments[0].narration?.mood == .encouraging)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""protocolVersion":1"#))
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""principalVariationSAN":["Nf3"]"#))
    }
}
