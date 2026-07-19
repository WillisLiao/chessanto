import Foundation

public struct AnalysisCancellation: Codable, Equatable, Sendable {
    public let protocolVersion: CompanionProtocolVersion
    public let id: String
    public let requestID: AnalysisRequestID
    public let senderDeviceID: CompanionDeviceID
    public let endpointID: EndpointID
    public let createdAt: Date

    public init(
        protocolVersion: CompanionProtocolVersion,
        id: String,
        requestID: AnalysisRequestID,
        senderDeviceID: CompanionDeviceID,
        endpointID: EndpointID,
        createdAt: Date
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.requestID = requestID
        self.senderDeviceID = senderDeviceID
        self.endpointID = endpointID
        self.createdAt = createdAt
    }
}

public enum CompanionMessage: Codable, Equatable, Sendable {
    case gameCatalog(GameCatalogSnapshot)
    case analysisRequest(AnalysisRequest)
    case analysisCancellation(AnalysisCancellation)
    case analysisStatus(AnalysisJobSnapshot)
    case report(PortableAnalysisReport)
}

public enum AnalysisApplicationEvent: Equatable, Sendable {
    case progress(AnalysisProgress)
    case report(PortableAnalysisReport)
}

public protocol GameAnalysisApplication: Sendable {
    func analyze(
        request: AnalysisRequest
    ) -> AsyncThrowingStream<AnalysisApplicationEvent, Error>
}
