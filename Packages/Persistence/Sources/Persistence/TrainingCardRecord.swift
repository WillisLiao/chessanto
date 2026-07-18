import Foundation
import GRDB

public struct TrainingCardRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trainingCard"

    public var id: Int64?
    public var gameId: Int64
    public var sourcePly: Int
    public var preMoveFEN: String
    public var sideToMove: String
    public var bestMoveUCI: String
    public var rankedLinesJSON: String
    public var classification: String
    public var themesJSON: String
    public var explanation: String?
    public var dueAt: Date
    public var consecutiveSuccesses: Int
    public var masteryState: String
    public var lastResult: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        gameId: Int64,
        sourcePly: Int,
        preMoveFEN: String,
        sideToMove: String,
        bestMoveUCI: String,
        rankedLinesJSON: String,
        classification: String,
        themesJSON: String = "[]",
        explanation: String? = nil,
        dueAt: Date = Date(),
        consecutiveSuccesses: Int = 0,
        masteryState: String = "new",
        lastResult: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.gameId = gameId
        self.sourcePly = sourcePly
        self.preMoveFEN = preMoveFEN
        self.sideToMove = sideToMove
        self.bestMoveUCI = bestMoveUCI
        self.rankedLinesJSON = rankedLinesJSON
        self.classification = classification
        self.themesJSON = themesJSON
        self.explanation = explanation
        self.dueAt = dueAt
        self.consecutiveSuccesses = consecutiveSuccesses
        self.masteryState = masteryState
        self.lastResult = lastResult
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
