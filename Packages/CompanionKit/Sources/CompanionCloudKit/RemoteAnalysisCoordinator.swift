import CompanionDomain
import Foundation

public actor RemoteAnalysisCoordinator {
    private let application: any GameAnalysisApplication
    private let ledger: AnalysisRequestLedger

    public init(
        application: any GameAnalysisApplication,
        ledger: AnalysisRequestLedger = .init()
    ) {
        self.application = application
        self.ledger = ledger
    }

    public func restoreLedger(
        _ entries: [AnalysisRequestLedgerEntry]
    ) async {
        await ledger.restore(entries)
    }

    public func durableLedgerEntries() async -> [AnalysisRequestLedgerEntry] {
        await ledger.durableEntries()
    }

    public func process(
        _ messages: [CompanionMessage],
        now: Date
    ) async throws -> [CompanionMessage] {
        let collector = CompanionMessageCollector()
        for message in messages {
            try await process(message, now: now) { response in
                await collector.append(response)
            }
        }
        return await collector.messages()
    }

    public func process(
        _ message: CompanionMessage,
        now: Date,
        deliver: @escaping @Sendable (CompanionMessage) async throws -> Void
    ) async throws {
        switch message {
        case .analysisRequest(let request):
            try await process(request, now: now, deliver: deliver)
        case .analysisCancellation(let cancellation):
            if let snapshot = await ledger.snapshot(
                for: cancellation.requestID
            ) {
                let disposition = try AnalysisCancellationReducer.apply(
                    to: snapshot,
                    at: now
                )
                if disposition == .cancelled, !snapshot.state.isTerminal {
                    let cancelled = try AnalysisJobReducer.advance(
                        snapshot,
                        to: .cancelled,
                        at: now,
                        terminalReason: .cancelledByUser
                    )
                    await ledger.update(cancelled)
                    try await deliver(.analysisStatus(cancelled))
                } else {
                    try await deliver(.analysisStatus(snapshot))
                }
            }
        case .gameCatalog, .analysisStatus, .report:
            break
        }
    }

    private func process(
        _ request: AnalysisRequest,
        now: Date,
        deliver: @escaping @Sendable (CompanionMessage) async throws -> Void
    ) async throws {
        let fingerprint = try CanonicalCoding.encode(request)
        let admission = await ledger.admit(
            request,
            fingerprint: fingerprint,
            now: now
        )
        switch admission {
        case .duplicate(let snapshot):
            try await deliver(.analysisStatus(snapshot))
        case .rejected(let rejection):
            let reason: AnalysisTerminalReason =
                rejection == .expired ? .expired : .tamperedPayload
            let snapshot = AnalysisJobSnapshot(
                protocolVersion: request.protocolVersion,
                requestID: request.id,
                state: .rejected,
                reception: .accepted,
                progress: nil,
                updatedAt: now,
                terminalReason: reason,
                reportID: nil
            )
            try await deliver(.analysisStatus(snapshot))
        case .accepted(let accepted), .resumed(let accepted):
            try await run(
                request: request,
                accepted: accepted,
                now: now,
                deliver: deliver
            )
        }
    }

    private func run(
        request: AnalysisRequest,
        accepted: AnalysisJobSnapshot,
        now: Date,
        deliver: @escaping @Sendable (CompanionMessage) async throws -> Void
    ) async throws {
        try await deliver(.analysisStatus(accepted))
        var current = try AnalysisJobReducer.advance(
            accepted,
            to: .waitingForEngine,
            at: now
        )
        await ledger.update(current)
        try await deliver(.analysisStatus(current))

        do {
            for try await event in application.analyze(request: request) {
                if
                    let latest = await ledger.snapshot(for: request.id),
                    latest.state == .cancelled
                {
                    throw CancellationError()
                }
                switch event {
                case .progress(let progress):
                    current = try AnalysisJobReducer.advance(
                        current,
                        to: .analyzing,
                        at: Date(),
                        progress: progress
                    )
                    await ledger.update(current)
                    try await deliver(.analysisStatus(current))
                case .report(let report):
                    current = try AnalysisJobReducer.advance(
                        current,
                        to: .packaging,
                        at: Date()
                    )
                    await ledger.update(current)
                    try await deliver(.analysisStatus(current))

                    current = try AnalysisJobReducer.advance(
                        current,
                        to: .transferring,
                        at: Date()
                    )
                    await ledger.update(current)
                    try await deliver(.analysisStatus(current))
                    try await deliver(.report(report))

                    current = try AnalysisJobReducer.advance(
                        current,
                        to: .completed,
                        at: Date(),
                        reportID: report.id
                    )
                    await ledger.update(current)
                    try await deliver(.analysisStatus(current))
                }
            }
        } catch {
            if
                let latest = await ledger.snapshot(for: request.id),
                latest.state.isTerminal
            {
                return
            }
            let failed = try AnalysisJobReducer.advance(
                current,
                to: error is CancellationError ? .cancelled : .failed,
                at: Date(),
                terminalReason: error is CancellationError
                    ? .cancelledByUser
                    : .engineUnavailable
            )
            await ledger.update(failed)
            try await deliver(.analysisStatus(failed))
        }
    }
}

private actor CompanionMessageCollector {
    private var values: [CompanionMessage] = []

    func append(_ message: CompanionMessage) {
        values.append(message)
    }

    func messages() -> [CompanionMessage] {
        values
    }
}
