import CompanionDomain
import Foundation
import Testing
@testable import CompanionCloudKit

@Suite("In-memory companion contract")
struct InMemoryCompanionContractTests {
    @Test("progress is delivered before report packaging completes")
    func progressStreamsBeforeCompletion() async throws {
        let analysis = MockGameAnalysisApplication(report: makeReport())
        let coordinator = RemoteAnalysisCoordinator(application: analysis)
        let deliveries = DeliveryRecorder()

        try await coordinator.process(
            .analysisRequest(makeRequest()),
            now: Date(timeIntervalSince1970: 110)
        ) { message in
            await deliveries.append(message)
        }

        let messages = await deliveries.messages
        let states = messages.compactMap { message -> AnalysisJobState? in
            guard case .analysisStatus(let snapshot) = message else {
                return nil
            }
            return snapshot.state
        }
        #expect(
            states == [
                .accepted,
                .waitingForEngine,
                .analyzing,
                .packaging,
                .transferring,
                .completed,
            ]
        )
        let reportIndex = messages.firstIndex {
            if case .report = $0 { return true }
            return false
        }
        let progressIndex = messages.firstIndex {
            guard case .analysisStatus(let snapshot) = $0 else {
                return false
            }
            return snapshot.state == .analyzing
        }
        #expect(progressIndex != nil)
        #expect(reportIndex != nil)
        #expect(progressIndex! < reportIndex!)
    }

    @Test("queued request runs once when Mac returns and delivers a report")
    func queuedRequestRunsOnceWhenMacReturnsAndDeliversAReport() async throws {
        let mailbox = InMemoryCompanionMailbox()
        let analysis = MockGameAnalysisApplication(report: makeReport())
        let coordinator = RemoteAnalysisCoordinator(application: analysis)
        let request = makeRequest()

        await mailbox.setReachable(false, for: .mac)
        await mailbox.send(.analysisRequest(request), to: .mac)
        await #expect(throws: CompanionMailboxError.endpointUnavailable) {
            try await mailbox.receive(for: .mac)
        }
        #expect(await analysis.runCount == 0)

        await mailbox.setReachable(true, for: .mac)
        let firstDelivery = try await mailbox.receive(for: .mac)
        let firstResponses = try await coordinator.process(
            firstDelivery,
            now: Date(timeIntervalSince1970: 110)
        )
        for response in firstResponses {
            await mailbox.send(response, to: .phone)
        }

        await mailbox.send(.analysisRequest(request), to: .mac)
        let duplicateDelivery = try await mailbox.receive(for: .mac)
        let duplicateResponses = try await coordinator.process(
            duplicateDelivery,
            now: Date(timeIntervalSince1970: 111)
        )
        for response in duplicateResponses {
            await mailbox.send(response, to: .phone)
        }

        let phoneMessages = try await mailbox.receive(for: .phone)
        #expect(await analysis.runCount == 1)
        #expect(
            phoneMessages.contains {
                guard case .analysisStatus(let status) = $0 else {
                    return false
                }
                return status.state == .analyzing
                    && status.progress?.completedPlies == 2
            }
        )
        #expect(
            phoneMessages.contains {
                guard case .analysisStatus(let status) = $0 else {
                    return false
                }
                return status.state == .completed
                    && status.reportID == ReportID("report-1")
            }
        )
        #expect(
            phoneMessages.contains {
                guard case .report(let report) = $0 else {
                    return false
                }
                return report.id == ReportID("report-1")
            }
        )
    }

    @Test("an interrupted durable request resumes after Mac relaunch")
    func interruptedDurableRequestResumesAfterRelaunch() async throws {
        let request = makeRequest()
        let fingerprint = try CanonicalCoding.encode(request)
        let priorLedger = AnalysisRequestLedger()
        _ = await priorLedger.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 110)
        )

        let analysis = MockGameAnalysisApplication(report: makeReport())
        let coordinator = RemoteAnalysisCoordinator(application: analysis)
        await coordinator.restoreLedger(await priorLedger.durableEntries())
        let responses = try await coordinator.process(
            [.analysisRequest(request)],
            now: Date(timeIntervalSince1970: 111)
        )

        #expect(await analysis.runCount == 1)
        #expect(
            responses.contains {
                guard case .analysisStatus(let status) = $0 else {
                    return false
                }
                return status.state == .completed
            }
        )
    }

    private func makeRequest() -> AnalysisRequest {
        AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID("request-1"),
            endpointID: EndpointID("mac-1"),
            senderDeviceID: CompanionDeviceID("phone-1"),
            gameID: CompanionGameID("game-a"),
            quality: .deep,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
    }

    private func makeReport() -> PortableAnalysisReport {
        PortableAnalysisReport(
            protocolVersion: .v1,
            id: ReportID("report-1"),
            gameID: CompanionGameID("game-a"),
            generatedAt: Date(timeIntervalSince1970: 110),
            analysisQuality: .deep,
            metadata: PortableGameMetadata(
                white: "Willis",
                black: "Coach",
                result: "1-0",
                playedAt: nil,
                timeControl: nil
            ),
            pgn: "1. Nf3",
            positions: [],
            evaluations: [],
            rankedLines: [],
            classifications: [],
            opening: nil,
            keyMoments: [],
            takeaways: ["Develop before attacking."]
        )
    }
}

private actor DeliveryRecorder {
    private(set) var messages: [CompanionMessage] = []

    func append(_ message: CompanionMessage) {
        messages.append(message)
    }
}

private actor MockGameAnalysisApplication: GameAnalysisApplication {
    private(set) var runCount = 0
    private let report: PortableAnalysisReport

    init(report: PortableAnalysisReport) {
        self.report = report
    }

    nonisolated func analyze(
        request: AnalysisRequest
    ) -> AsyncThrowingStream<AnalysisApplicationEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await incrementRunCount()
                continuation.yield(
                    .progress(
                        AnalysisProgress(completedPlies: 2, totalPlies: 4)
                    )
                )
                continuation.yield(.report(report))
                continuation.finish()
            }
        }
    }

    private func incrementRunCount() {
        runCount += 1
    }
}
