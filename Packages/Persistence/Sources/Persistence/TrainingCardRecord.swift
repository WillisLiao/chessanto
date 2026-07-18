import Foundation
import GRDB
import ChessCore

private struct PersistedRankedLine: Decodable {
    let rank: Int
    let scoreCentipawns: Int?
    let mateIn: Int?
    let principalVariationUCI: [String]
    let depth: Int
}

public enum TrainingCardReconciliationError: Error, Equatable, LocalizedError {
    case mismatchedGame
    case duplicateSourcePly
    case persistedCandidateID
    case invalidSourcePly
    case invalidFEN
    case invalidSideToMove
    case invalidBestMove
    case malformedRankedLines
    case invalidClassification
    case invalidProgressState

    public var errorDescription: String? {
        switch self {
        case .mismatchedGame:
            return "A practice card belonged to a different game."
        case .duplicateSourcePly:
            return "The report produced more than one practice card for the same move."
        case .persistedCandidateID:
            return "A new practice card unexpectedly contained a saved database identifier."
        case .invalidSourcePly:
            return "A practice card referenced an invalid move number."
        case .invalidFEN:
            return "A practice card contained an invalid chess position."
        case .invalidSideToMove:
            return "A practice card's side to move did not match its chess position."
        case .invalidBestMove:
            return "A practice card's best move was not legal in its chess position."
        case .malformedRankedLines:
            return "A practice card contained incomplete engine lines."
        case .invalidClassification:
            return "A practice card contained an unknown move classification."
        case .invalidProgressState:
            return "A practice card contained an unknown review state."
        }
    }
}

public struct TrainingQueueSnapshot: Sendable {
    public let dueCards: [TrainingCardRecord]
    public let dueCount: Int
    public let fallbackCards: [TrainingCardRecord]
    public let nextDueDate: Date?

    public var hasDueNow: Bool {
        dueCount > 0
    }
}

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

    func validateForReconciliation() throws {
        guard id == nil else {
            throw TrainingCardReconciliationError.persistedCandidateID
        }
        guard sourcePly > 0 else {
            throw TrainingCardReconciliationError.invalidSourcePly
        }
        guard ChessGame.isValidFEN(preMoveFEN) else {
            throw TrainingCardReconciliationError.invalidFEN
        }

        let fenFields = preMoveFEN.split(separator: " ")
        let expectedSide = fenFields.count > 1 && fenFields[1] == "b" ? "black" : "white"
        guard sideToMove == expectedSide else {
            throw TrainingCardReconciliationError.invalidSideToMove
        }
        guard ChessGame.replayLine(
            fromUCI: [bestMoveUCI],
            startingFEN: preMoveFEN
        ).count == 1 else {
            throw TrainingCardReconciliationError.invalidBestMove
        }

        guard let rankedData = rankedLinesJSON.data(using: .utf8),
            let rankedLines = try? JSONDecoder().decode(
                [PersistedRankedLine].self,
                from: rankedData
            ),
            let rankOne = rankedLines.first(where: { $0.rank == 1 }),
            rankOne.principalVariationUCI.first == bestMoveUCI
        else {
            throw TrainingCardReconciliationError.malformedRankedLines
        }
        guard let themesData = themesJSON.data(using: .utf8),
            (try? JSONDecoder().decode([String].self, from: themesData)) != nil
        else {
            throw TrainingCardReconciliationError.malformedRankedLines
        }

        let validClassifications: Set<String> = [
            "brilliant", "best", "excellent", "good",
            "inaccuracy", "mistake", "blunder", "missedWin"
        ]
        guard validClassifications.contains(classification) else {
            throw TrainingCardReconciliationError.invalidClassification
        }

        let validMasteryStates: Set<String> = ["new", "learning", "review", "mastered"]
        let validResults: Set<String> = ["strong", "playable", "inaccurate", "incorrect"]
        guard validMasteryStates.contains(masteryState),
            lastResult == nil || validResults.contains(lastResult!)
        else {
            throw TrainingCardReconciliationError.invalidProgressState
        }
    }
}
