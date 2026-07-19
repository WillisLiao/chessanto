import CoachKit
import CompanionDomain
import Foundation
import Persistence
import Testing
@testable import Chessanto

@Suite("Game analysis application service")
struct GameAnalysisApplicationServiceTests {
    @Test("local requests do not depend on a CloudKit or Keychain identity")
    func localRequestsUseAnIndependentIdentity() {
        let request = LocalAnalysisRequestFactory.make(
            gameID: CompanionGameID("local-game"),
            quality: .fast,
            requestID: AnalysisRequestID("local-request"),
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(request.endpointID == EndpointID("mac-local-analysis"))
        #expect(request.senderDeviceID == CompanionDeviceID("mac-local-analysis"))
        #expect(request.gameID == CompanionGameID("local-game"))
        #expect(request.quality == .fast)
        #expect(request.expiresAt == Date(timeIntervalSince1970: 86_500))
    }

    @Test("remote request emits backend progress and a complete portable report")
    func remoteRequestEmitsProgressAndReport() async throws {
        let backing = MockMacGameAnalysisBacking(completed: makeCompletedAnalysis())
        let service = GameAnalysisApplicationService(
            backing: backing,
            makeReportID: { ReportID("report-remote") },
            now: { Date(timeIntervalSince1970: 300) }
        )
        let request = AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID("request-1"),
            endpointID: EndpointID("mac-1"),
            senderDeviceID: CompanionDeviceID("phone-1"),
            gameID: CompanionGameID("opaque-game"),
            quality: .deep,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 500)
        )

        var events: [AnalysisApplicationEvent] = []
        for try await event in service.analyze(request: request) {
            events.append(event)
        }

        #expect(await backing.receivedGameID == CompanionGameID("opaque-game"))
        #expect(await backing.receivedQuality == .deep)
        #expect(
            events.contains(
                .progress(AnalysisProgress(completedPlies: 2, totalPlies: 3))
            )
        )
        var foundReport: PortableAnalysisReport?
        for event in events {
            if case .report(let report) = event {
                foundReport = report
            }
        }
        let report: PortableAnalysisReport = try #require(foundReport)
        #expect(report.id == ReportID("report-remote"))
        #expect(report.gameID == CompanionGameID("opaque-game"))
        #expect(report.analysisQuality == .deep)
        #expect(report.positions.map { $0.playedSAN } == [nil, "Nf3", "Nf6"])
    }

    @Test("all local and remote engine batches execute one at a time")
    func analysisBatchesAreSerialized() async throws {
        let backing = ConcurrencyTrackingBacking(
            completed: makeCompletedAnalysis()
        )
        let service = GameAnalysisApplicationService(backing: backing)
        let first = makeRequest(id: "request-first", gameID: "game-first")
        let second = makeRequest(id: "request-second", gameID: "game-second")

        async let firstEvents: Void = drain(
            service.analyze(request: first)
        )
        async let secondEvents: Void = drain(
            service.analyze(request: second)
        )
        _ = try await (firstEvents, secondEvents)

        #expect(await backing.maximumConcurrentAnalyses == 1)
        #expect(await backing.startedGameIDs.count == 2)
    }

    private func makeRequest(
        id: String,
        gameID: String
    ) -> AnalysisRequest {
        AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID(id),
            endpointID: EndpointID("mac-1"),
            senderDeviceID: CompanionDeviceID("phone-1"),
            gameID: CompanionGameID(gameID),
            quality: .standard,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func drain(
        _ events: AsyncThrowingStream<AnalysisApplicationEvent, Error>
    ) async throws {
        for try await _ in events {}
    }

    private func makeCompletedAnalysis() -> MacCompletedAnalysis {
        let pgn = """
            [White "Willis"]
            [Black "Coach"]
            [Result "*"]

            1. Nf3 Nf6 *
            """
        return MacCompletedAnalysis(
            record: GameRecord(
                id: 7,
                source: .pgnImport,
                pgn: pgn,
                white: "Willis",
                black: "Coach",
                result: "*"
            ),
            analysisRows: [
                makeRow(ply: 0, fen: "start", pv: "g1f3 g8f6"),
                makeRow(ply: 1, fen: "after-nf3", pv: "g8f6"),
                makeRow(ply: 2, fen: "after-nf6", pv: "e2e4"),
            ],
            chessComUsername: "Willis",
            narrationsByPly: [:]
        )
    }

    private func makeRow(ply: Int, fen: String, pv: String) -> AnalysisRecord {
        AnalysisRecord(
            gameId: 7,
            plyIndex: ply,
            fen: fen,
            depth: 18,
            scoreCentipawns: 20 - ply,
            principalVariation: pv,
            multiPVRank: 1,
            qualityPreset: .deep,
            analyzedAt: Date(timeIntervalSince1970: 200)
        )
    }
}

private actor ConcurrencyTrackingBacking: MacGameAnalysisBacking {
    private let completed: MacCompletedAnalysis
    private var concurrentAnalyses = 0
    private(set) var maximumConcurrentAnalyses = 0
    private(set) var startedGameIDs: [CompanionGameID] = []

    init(completed: MacCompletedAnalysis) {
        self.completed = completed
    }

    func analyze(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> MacCompletedAnalysis {
        startedGameIDs.append(gameID)
        concurrentAnalyses += 1
        maximumConcurrentAnalyses = max(
            maximumConcurrentAnalyses,
            concurrentAnalyses
        )
        try await Task.sleep(for: .milliseconds(75))
        concurrentAnalyses -= 1
        return completed
    }
}

private actor MockMacGameAnalysisBacking: MacGameAnalysisBacking {
    private let completed: MacCompletedAnalysis
    private(set) var receivedGameID: CompanionGameID?
    private(set) var receivedQuality: CompanionAnalysisQuality?

    init(completed: MacCompletedAnalysis) {
        self.completed = completed
    }

    func analyze(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> MacCompletedAnalysis {
        receivedGameID = gameID
        receivedQuality = quality
        progress(AnalysisProgress(completedPlies: 2, totalPlies: 3))
        return completed
    }
}
