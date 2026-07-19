import Foundation

public enum AnalysisJobState: String, Codable, CaseIterable, Sendable {
    case submitted
    case queued
    case accepted
    case waitingForEngine
    case analyzing
    case packaging
    case transferring
    case completed
    case failed
    case cancelled
    case expired
    case rejected

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .expired, .rejected:
            return true
        default:
            return false
        }
    }
}

public enum RequestReception: String, Codable, Sendable {
    case localOnly
    case submitted
    case accepted
}

public struct AnalysisProgress: Codable, Equatable, Sendable {
    public let completedPlies: Int
    public let totalPlies: Int

    public init(completedPlies: Int, totalPlies: Int) {
        self.completedPlies = completedPlies
        self.totalPlies = totalPlies
    }
}

public enum AnalysisTerminalReason: String, Codable, Sendable {
    case engineUnavailable
    case invalidGame
    case expired
    case revokedDevice
    case tamperedPayload
    case cancellationTooLate
    case cancelledByUser
    case incompatibleProtocol
}

public struct AnalysisJobSnapshot: Codable, Equatable, Sendable {
    public let protocolVersion: CompanionProtocolVersion
    public let requestID: AnalysisRequestID
    public let state: AnalysisJobState
    public let reception: RequestReception
    public let progress: AnalysisProgress?
    public let updatedAt: Date
    public let terminalReason: AnalysisTerminalReason?
    public let reportID: ReportID?

    public init(
        protocolVersion: CompanionProtocolVersion,
        requestID: AnalysisRequestID,
        state: AnalysisJobState,
        reception: RequestReception,
        progress: AnalysisProgress?,
        updatedAt: Date,
        terminalReason: AnalysisTerminalReason?,
        reportID: ReportID?
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.state = state
        self.reception = reception
        self.progress = progress
        self.updatedAt = updatedAt
        self.terminalReason = terminalReason
        self.reportID = reportID
    }
}
