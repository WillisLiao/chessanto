import Foundation
import GRDB

/// One turn in a position-chat conversation attached to a game.
///
/// `role` is `"user"` or `"assistant"`. `source` is set only on assistant
/// rows: `"coach"` / `"fallback"` / `"precheck"` (mirrors
/// `CoachChatReply.Source`'s raw values), and is `nil` on user rows.
/// `plyIndex` is always the mainline ancestor ply of the position the
/// message was asked at, since variation rows can be deleted and plys are
/// the only stable coordinates.
public struct ChatMessageRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "chatMessage"

    public var id: Int64?
    public var gameId: Int64
    public var plyIndex: Int
    public var role: String
    public var content: String
    public var createdAt: Date
    public var source: String?

    public init(
        id: Int64? = nil,
        gameId: Int64,
        plyIndex: Int,
        role: String,
        content: String,
        createdAt: Date = Date(),
        source: String? = nil
    ) {
        self.id = id
        self.gameId = gameId
        self.plyIndex = plyIndex
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.source = source
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
