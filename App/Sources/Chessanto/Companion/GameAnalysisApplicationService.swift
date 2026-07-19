import CoachKit
import CompanionDomain
import Foundation
import Persistence

struct MacCompletedAnalysis: Sendable {
    let record: GameRecord
    let analysisRows: [AnalysisRecord]
    let chessComUsername: String?
    let narrationsByPly: [Int: CoachNarration]
}

protocol MacGameAnalysisBacking: Sendable {
    func analyze(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> MacCompletedAnalysis
}

enum GameAnalysisApplicationServiceError: LocalizedError {
    case incompleteReport

    var errorDescription: String? {
        switch self {
        case .incompleteReport:
            return "The Mac completed analysis but could not package a complete offline report."
        }
    }
}

enum LocalAnalysisRequestFactory {
    private static let localEndpoint = "mac-local-analysis"

    static func make(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        requestID: AnalysisRequestID = AnalysisRequestID(
            UUID().uuidString.lowercased()
        ),
        now: Date = Date()
    ) -> AnalysisRequest {
        AnalysisRequest(
            protocolVersion: .v1,
            id: requestID,
            endpointID: EndpointID(localEndpoint),
            senderDeviceID: CompanionDeviceID(localEndpoint),
            gameID: gameID,
            quality: quality,
            createdAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )
    }
}

private actor SerialAnalysisExecutionQueue {
    private var tail = Task<Void, Never> {}

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let work = Task<Value, Error> {
            await predecessor.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task {
            _ = try? await work.value
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

/// The single UI-independent analysis use case shared by local replay
/// controls and the remote coordinator.
final class GameAnalysisApplicationService: GameAnalysisApplication, @unchecked Sendable {
    private let backing: any MacGameAnalysisBacking
    private let executionQueue = SerialAnalysisExecutionQueue()
    private let makeReportID: @Sendable () -> ReportID
    private let now: @Sendable () -> Date

    init(
        backing: any MacGameAnalysisBacking,
        makeReportID: @escaping @Sendable () -> ReportID = {
            ReportID(UUID().uuidString.lowercased())
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backing = backing
        self.makeReportID = makeReportID
        self.now = now
    }

    func analyze(
        request: AnalysisRequest
    ) -> AsyncThrowingStream<AnalysisApplicationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await executionQueue.run {
                        try await self.backing.analyze(
                            gameID: request.gameID,
                            quality: request.quality
                        ) { progress in
                            continuation.yield(.progress(progress))
                        }
                    }
                    guard let report = PortableReportAssembler.assemble(
                        id: makeReportID(),
                        gameID: request.gameID,
                        record: result.record,
                        quality: request.quality,
                        analysisRows: result.analysisRows,
                        chessComUsername: result.chessComUsername,
                        narrationsByPly: result.narrationsByPly,
                        generatedAt: now()
                    ) else {
                        throw GameAnalysisApplicationServiceError.incompleteReport
                    }
                    continuation.yield(.report(report))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
