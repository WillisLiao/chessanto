import Foundation
import GRDB

public struct TrainingAttemptRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trainingAttempt"

    public var id: Int64?
    public var cardId: Int64
    public var attemptedUCI: String
    public var attemptedAt: Date
    public var evaluationLossCentipawns: Int?
    public var outcome: String
    public var hintCount: Int

    public init(
        id: Int64? = nil,
        cardId: Int64,
        attemptedUCI: String,
        attemptedAt: Date = Date(),
        evaluationLossCentipawns: Int? = nil,
        outcome: String,
        hintCount: Int
    ) {
        self.id = id
        self.cardId = cardId
        self.attemptedUCI = attemptedUCI
        self.attemptedAt = attemptedAt
        self.evaluationLossCentipawns = evaluationLossCentipawns
        self.outcome = outcome
        self.hintCount = hintCount
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
