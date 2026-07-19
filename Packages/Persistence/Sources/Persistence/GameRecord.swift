import Foundation
import GRDB

public enum GameSource: String, Codable, Sendable {
    case chessCom
    case pgnImport
}

public struct GameRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "game"

    public var id: Int64?
    public var source: GameSource
    public var sourceURL: String?
    public var pgn: String
    public var white: String
    public var black: String
    public var whiteRating: Int?
    public var blackRating: Int?
    public var result: String?
    public var timeControl: String?
    public var playedAt: Date?
    public var importedAt: Date
    public var pinnedAt: Date?
    public var isFavorite: Bool
    public var deletedAt: Date?

    public init(
        id: Int64? = nil,
        source: GameSource,
        sourceURL: String? = nil,
        pgn: String,
        white: String,
        black: String,
        whiteRating: Int? = nil,
        blackRating: Int? = nil,
        result: String? = nil,
        timeControl: String? = nil,
        playedAt: Date? = nil,
        importedAt: Date = Date(),
        pinnedAt: Date? = nil,
        isFavorite: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceURL = sourceURL
        self.pgn = pgn
        self.white = white
        self.black = black
        self.whiteRating = whiteRating
        self.blackRating = blackRating
        self.result = result
        self.timeControl = timeControl
        self.playedAt = playedAt
        self.importedAt = importedAt
        self.pinnedAt = pinnedAt
        self.isFavorite = isFavorite
        self.deletedAt = deletedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
