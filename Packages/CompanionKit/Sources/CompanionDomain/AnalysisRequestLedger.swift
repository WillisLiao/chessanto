import Foundation

public enum AnalysisRequestRejection: Equatable, Sendable {
    case expired
    case tamperedPayload
}

public enum AnalysisRequestAdmission: Equatable, Sendable {
    case accepted(AnalysisJobSnapshot)
    case resumed(AnalysisJobSnapshot)
    case duplicate(AnalysisJobSnapshot)
    case rejected(AnalysisRequestRejection)
}

public struct AnalysisRequestLedgerEntry: Codable, Equatable, Sendable {
    public let requestID: AnalysisRequestID
    public let fingerprint: Data
    public let snapshot: AnalysisJobSnapshot
    public let request: AnalysisRequest?

    public init(
        requestID: AnalysisRequestID,
        fingerprint: Data,
        snapshot: AnalysisJobSnapshot,
        request: AnalysisRequest? = nil
    ) {
        self.requestID = requestID
        self.fingerprint = fingerprint
        self.snapshot = snapshot
        self.request = request
    }
}

public actor AnalysisRequestLedger {
    private struct Entry: Sendable {
        let fingerprint: Data
        var snapshot: AnalysisJobSnapshot
        let request: AnalysisRequest?
        var isRunning: Bool
    }

    private var entries: [AnalysisRequestID: Entry] = [:]

    public init() {}

    public var count: Int {
        entries.count
    }

    public func admit(
        _ request: AnalysisRequest,
        fingerprint: Data,
        now: Date
    ) -> AnalysisRequestAdmission {
        if var existing = entries[request.id] {
            guard existing.fingerprint == fingerprint else {
                return .rejected(.tamperedPayload)
            }
            guard
                !existing.snapshot.state.isTerminal,
                !existing.isRunning,
                existing.request != nil
            else {
                return .duplicate(existing.snapshot)
            }
            let resumed = AnalysisJobSnapshot(
                protocolVersion: request.protocolVersion,
                requestID: request.id,
                state: .accepted,
                reception: .accepted,
                progress: nil,
                updatedAt: now,
                terminalReason: nil,
                reportID: nil
            )
            existing.snapshot = resumed
            existing.isRunning = true
            entries[request.id] = existing
            return .resumed(resumed)
        }
        guard request.expiresAt > now else {
            return .rejected(.expired)
        }

        let snapshot = AnalysisJobSnapshot(
            protocolVersion: request.protocolVersion,
            requestID: request.id,
            state: .accepted,
            reception: .accepted,
            progress: nil,
            updatedAt: now,
            terminalReason: nil,
            reportID: nil
        )
        entries[request.id] = Entry(
            fingerprint: fingerprint,
            snapshot: snapshot,
            request: request,
            isRunning: true
        )
        return .accepted(snapshot)
    }

    public func snapshot(
        for requestID: AnalysisRequestID
    ) -> AnalysisJobSnapshot? {
        entries[requestID]?.snapshot
    }

    public func update(_ snapshot: AnalysisJobSnapshot) {
        guard var entry = entries[snapshot.requestID] else {
            return
        }
        entry.snapshot = snapshot
        if snapshot.state.isTerminal {
            entry.isRunning = false
        }
        entries[snapshot.requestID] = entry
    }

    public func restore(_ durableEntries: [AnalysisRequestLedgerEntry]) {
        entries = Dictionary(
            uniqueKeysWithValues: durableEntries.map {
                (
                    $0.requestID,
                    Entry(
                        fingerprint: $0.fingerprint,
                        snapshot: $0.snapshot,
                        request: $0.request,
                        isRunning: false
                    )
                )
            }
        )
    }

    public func durableEntries() -> [AnalysisRequestLedgerEntry] {
        entries.map { requestID, entry in
            AnalysisRequestLedgerEntry(
                requestID: requestID,
                fingerprint: entry.fingerprint,
                snapshot: entry.snapshot,
                request: entry.request
            )
        }
        .sorted { $0.requestID.rawValue < $1.requestID.rawValue }
    }
}
