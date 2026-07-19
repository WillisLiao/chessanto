import Foundation
import GRDB

public struct AnalysisRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "analysis"

    public var id: Int64?
    public var gameId: Int64
    public var plyIndex: Int
    public var fen: String
    public var depth: Int
    public var scoreCentipawns: Int?
    public var mateIn: Int?
    public var principalVariation: String
    public var multiPVRank: Int
    public var qualityPreset: AnalysisQualityProvenance?
    public var analyzedAt: Date?
    public var engineIdentifier: String?

    public init(
        id: Int64? = nil,
        gameId: Int64,
        plyIndex: Int,
        fen: String,
        depth: Int,
        scoreCentipawns: Int? = nil,
        mateIn: Int? = nil,
        principalVariation: String,
        multiPVRank: Int,
        qualityPreset: AnalysisQualityProvenance? = nil,
        analyzedAt: Date? = nil,
        engineIdentifier: String? = nil
    ) {
        self.id = id
        self.gameId = gameId
        self.plyIndex = plyIndex
        self.fen = fen
        self.depth = depth
        self.scoreCentipawns = scoreCentipawns
        self.mateIn = mateIn
        self.principalVariation = principalVariation
        self.multiPVRank = multiPVRank
        self.qualityPreset = qualityPreset
        self.analyzedAt = analyzedAt
        self.engineIdentifier = engineIdentifier
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
