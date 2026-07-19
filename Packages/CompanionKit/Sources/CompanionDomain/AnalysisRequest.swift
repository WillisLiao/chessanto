import Foundation

public enum CompanionAnalysisQuality: String, Codable, CaseIterable, Sendable {
    case fast
    case standard
    case deep
}

public struct AnalysisRequest: Codable, Equatable, Sendable, Identifiable {
    public let protocolVersion: CompanionProtocolVersion
    public let id: AnalysisRequestID
    public let endpointID: EndpointID
    public let senderDeviceID: CompanionDeviceID
    public let gameID: CompanionGameID
    public let quality: CompanionAnalysisQuality
    public let createdAt: Date
    public let expiresAt: Date
    public let retryOf: AnalysisRequestID?

    public init(
        protocolVersion: CompanionProtocolVersion,
        id: AnalysisRequestID,
        endpointID: EndpointID,
        senderDeviceID: CompanionDeviceID,
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        createdAt: Date,
        expiresAt: Date,
        retryOf: AnalysisRequestID? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.endpointID = endpointID
        self.senderDeviceID = senderDeviceID
        self.gameID = gameID
        self.quality = quality
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.retryOf = retryOf
    }
}
