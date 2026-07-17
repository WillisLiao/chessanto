import Foundation
import GRDB

/// One played move within a user-explored variation branch.
///
/// The tree shape is entirely defined by these rows, independent of any
/// in-memory chess engine's own move-tree representation:
/// - A root move of a top-level variation (`parentVariationId == nil`)
///   branches off the mainline after `parentPlyIndex`.
/// - Any other move continues from `parentVariationId`, the row for the
///   move immediately before it (whether that's the previous move in the
///   same branch, or the branch point of a nested sub-variation).
///
/// `orderIndex` orders sibling alternatives at the same branch point.
public struct VariationRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "variation"

    public var id: Int64?
    public var gameId: Int64
    public var parentPlyIndex: Int
    public var moveSAN: String
    public var orderIndex: Int
    public var parentVariationId: Int64?

    public init(
        id: Int64? = nil,
        gameId: Int64,
        parentPlyIndex: Int,
        moveSAN: String,
        orderIndex: Int,
        parentVariationId: Int64? = nil
    ) {
        self.id = id
        self.gameId = gameId
        self.parentPlyIndex = parentPlyIndex
        self.moveSAN = moveSAN
        self.orderIndex = orderIndex
        self.parentVariationId = parentVariationId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
