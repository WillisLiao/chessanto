import Foundation

public struct CatalogGame: Codable, Equatable, Sendable, Identifiable {
    public let id: CompanionGameID
    public let white: String
    public let black: String
    public let result: String
    public let playedAt: Date?
    public let isAnalyzed: Bool

    public init(
        id: CompanionGameID,
        white: String,
        black: String,
        result: String,
        playedAt: Date?,
        isAnalyzed: Bool
    ) {
        self.id = id
        self.white = white
        self.black = black
        self.result = result
        self.playedAt = playedAt
        self.isAnalyzed = isAnalyzed
    }
}

public struct GameCatalogSnapshot: Codable, Equatable, Sendable {
    public let protocolVersion: CompanionProtocolVersion
    public let endpointID: EndpointID
    public let version: Int
    public let generatedAt: Date
    public let games: [CatalogGame]

    public init(
        protocolVersion: CompanionProtocolVersion,
        endpointID: EndpointID,
        version: Int,
        generatedAt: Date,
        games: [CatalogGame]
    ) {
        self.protocolVersion = protocolVersion
        self.endpointID = endpointID
        self.version = version
        self.generatedAt = generatedAt
        self.games = games
    }
}
