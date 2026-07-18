import AnalysisKit
import ChessCore
import Foundation
import Persistence

enum MasteryState: String, Codable, Sendable, CaseIterable {
    case new
    case learning
    case review
    case mastered
}

enum TrainingOutcome: String, Codable, Sendable, CaseIterable {
    case strong
    case playable
    case inaccurate
    case incorrect

    var isSuccessfulRecall: Bool {
        self == .strong
    }

    var title: String {
        switch self {
        case .strong: return "Strong move"
        case .playable: return "Playable idea"
        case .inaccurate: return "Inaccurate"
        case .incorrect: return "Try again"
        }
    }
}

struct TrainingCard: Identifiable, Equatable, Sendable {
    let id: Int64
    let gameId: Int64
    let sourcePly: Int
    let preMoveFEN: String
    let sideToMove: ChessCore.PieceColor
    let rankedLines: [RankedLine]
    let classification: MoveClassification
    let themes: [String]
    let explanation: String?
    let dueAt: Date
    let consecutiveSuccesses: Int
    let masteryState: MasteryState
    let lastResult: TrainingOutcome?

    var bestMoveUCI: String? {
        rankedLines.sorted { $0.rank < $1.rank }.compactMap(\.principalVariationUCI.first).first
    }

    var bestMoveSAN: String? {
        guard let bestMoveUCI else { return nil }
        return ChessGame.replayLine(fromUCI: [bestMoveUCI], startingFEN: preMoveFEN).first?.san
    }
}

extension TrainingCard {
    init?(record: TrainingCardRecord) {
        guard let id = record.id,
            let sideToMove = ChessCore.PieceColor(rawValue: record.sideToMove),
            let classification = MoveClassification(rawValue: record.classification),
            let masteryState = MasteryState(rawValue: record.masteryState)
        else { return nil }
        let decoder = JSONDecoder()
        guard let rankedData = record.rankedLinesJSON.data(using: .utf8),
            let rankedLines = try? decoder.decode([RankedLine].self, from: rankedData)
        else { return nil }
        let themesData = record.themesJSON.data(using: .utf8) ?? Data()
        let themes = (try? decoder.decode([String].self, from: themesData)) ?? []

        self.id = id
        self.gameId = record.gameId
        self.sourcePly = record.sourcePly
        self.preMoveFEN = record.preMoveFEN
        self.sideToMove = sideToMove
        self.rankedLines = rankedLines
        self.classification = classification
        self.themes = themes
        self.explanation = record.explanation
        self.dueAt = record.dueAt
        self.consecutiveSuccesses = record.consecutiveSuccesses
        self.masteryState = masteryState
        self.lastResult = record.lastResult.flatMap(TrainingOutcome.init(rawValue:))
    }
}

extension TrainingCardRecord {
    init(cardDraft: TrainingCardDraft, gameId: Int64, now: Date = Date()) throws {
        let encoder = JSONEncoder()
        let rankedData = try encoder.encode(cardDraft.rankedLines)
        let themesData = try encoder.encode(cardDraft.themes)
        self.init(
            gameId: gameId,
            sourcePly: cardDraft.sourcePly,
            preMoveFEN: cardDraft.preMoveFEN,
            sideToMove: cardDraft.sideToMove.rawValue,
            bestMoveUCI: cardDraft.rankedLines.first?.principalVariationUCI.first ?? "",
            rankedLinesJSON: String(decoding: rankedData, as: UTF8.self),
            classification: cardDraft.classification.rawValue,
            themesJSON: String(decoding: themesData, as: UTF8.self),
            explanation: cardDraft.explanation,
            dueAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct TrainingCardDraft: Equatable, Sendable {
    let sourcePly: Int
    let preMoveFEN: String
    let sideToMove: ChessCore.PieceColor
    let rankedLines: [RankedLine]
    let classification: MoveClassification
    let themes: [String]
    let explanation: String?
}

enum TrainingCardFactory {
    static func drafts(report: GameReport, input: ReportInput) -> [TrainingCardDraft] {
        var drafts: [TrainingCardDraft] = []
        let userIsWhite: Bool? = if input.isUser(isWhite: true) {
            true
        } else if input.isUser(isWhite: false) {
            false
        } else {
            nil
        }
        for moment in report.keyMoments {
            guard moment.ply > 0, moment.ply - 1 < input.plies.count else { continue }
            if let userIsWhite, moment.evalSwing.moverIsWhite != userIsWhite {
                continue
            }
            let preMove = input.plies[moment.ply - 1]
            let rankedLines = preMove.lines.sorted { $0.rank < $1.rank }
            guard rankedLines.contains(where: { !$0.principalVariationUCI.isEmpty }) else { continue }
            let side: ChessCore.PieceColor = input.moverIsWhite(atPly: moment.ply) ? .white : .black
            drafts.append(TrainingCardDraft(
                sourcePly: moment.ply,
                preMoveFEN: preMove.fen,
                sideToMove: side,
                rankedLines: rankedLines,
                classification: moment.evalSwing.classification,
                themes: themes(for: moment),
                explanation: ReportText.momentSummary(moment, report: report)
            ))
        }
        return drafts
    }

    private static func themes(for moment: KeyMoment) -> [String] {
        var result: [String] = []
        if moment.punishment != nil { result.append("Material left en prise") }
        if moment.missedMate != nil { result.append("Missed forced mate") }
        if moment.allowedMate != nil { result.append("Allowed forced mate") }
        return result
    }
}

enum TrainingCardReconciler {
    static func reconcile(
        report: GameReport,
        input: ReportInput,
        gameId: Int64,
        store: GameStore
    ) async throws -> [TrainingCardRecord] {
        let candidates = try TrainingCardFactory.drafts(report: report, input: input).map {
            try TrainingCardRecord(cardDraft: $0, gameId: gameId)
        }
        try Task.checkCancellation()
        return try await store.reconcileTrainingCards(
            gameId: gameId,
            candidates: candidates
        )
    }
}

enum TrainingCardSynchronizationState: Equatable {
    case idle
    case preparing
    case ready(cardCount: Int, sourcePlies: Set<Int>)
    case failed(String)
}

@MainActor
final class TrainingCardSynchronizer {
    typealias Operation = @Sendable () async throws -> [TrainingCardRecord]

    private(set) var state: TrainingCardSynchronizationState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((TrainingCardSynchronizationState) -> Void)?

    private var task: Task<[TrainingCardRecord], Error>?
    private var generation = 0
    private var latestRecords: [TrainingCardRecord] = []

    func start(operation: @escaping Operation) {
        task?.cancel()
        generation += 1
        let runGeneration = generation
        latestRecords = []
        state = .preparing

        task = Task { [weak self] in
            do {
                let records = try await operation()
                try Task.checkCancellation()
                guard let self, self.generation == runGeneration else {
                    throw CancellationError()
                }
                self.latestRecords = records
                self.state = .ready(
                    cardCount: records.count,
                    sourcePlies: Set(records.map(\.sourcePly))
                )
                return records
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard let self, self.generation == runGeneration else {
                    throw CancellationError()
                }
                self.latestRecords = []
                self.state = .failed(error.localizedDescription)
                throw error
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        latestRecords = []
        state = .idle
    }

    func records() async throws -> [TrainingCardRecord] {
        if let task {
            return try await task.value
        }
        return latestRecords
    }
}

struct TrainingEvaluation: Equatable, Sendable {
    let outcome: TrainingOutcome
    let attemptedUCI: String
    let lossCentipawns: Int?
    let bestMoveUCI: String?
    let bestMoveSAN: String?
    let attemptedMoveSAN: String?
    let explanation: String
}

/// The training domain's engine seam: given the pre-move position and an
/// attempted move, produce a White-perspective evaluation of the resulting
/// position.
typealias EvaluatePosition = @Sendable (TrainingPositionRequest) async throws -> WhitePerspectiveScore

protocol TrainingMoveEvaluator: Sendable {
    func evaluate(card: TrainingCard, attemptedUCI: String) async throws -> TrainingEvaluation
}

struct DefaultTrainingMoveEvaluator: TrainingMoveEvaluator {
    var evaluateAttemptedMove: EvaluatePosition

    init(evaluateAttemptedMove: @escaping EvaluatePosition) {
        self.evaluateAttemptedMove = evaluateAttemptedMove
    }

    func evaluate(card: TrainingCard, attemptedUCI: String) async throws -> TrainingEvaluation {
        let replayed = ChessGame.replayLine(fromUCI: [attemptedUCI], startingFEN: card.preMoveFEN)
        guard let attempted = replayed.first else {
            return feedback(card: card, attemptedUCI: attemptedUCI, attemptedSAN: nil, outcome: .incorrect, loss: nil)
        }

        guard let best = card.rankedLines.sorted(by: { $0.rank < $1.rank }).first,
            let bestScore = WhitePerspectiveScore(scoreCentipawns: best.scoreCentipawns, mateIn: best.mateIn)
        else {
            return feedback(card: card, attemptedUCI: attemptedUCI, attemptedSAN: attempted.san, outcome: .incorrect, loss: nil)
        }

        let attemptedScore = try await scoreAttemptedMove(attempted, card: card, attemptedUCI: attemptedUCI)
        let outcomeAndLoss = classify(best: bestScore, attempted: attemptedScore, mover: card.sideToMove)
        return feedback(
            card: card,
            attemptedUCI: attemptedUCI,
            attemptedSAN: attempted.san,
            outcome: outcomeAndLoss.outcome,
            loss: outcomeAndLoss.loss
        )
    }

    /// Scores the attempted move without ever reaching the engine when the
    /// position after it is provably terminal or already cached.
    ///
    /// Terminal positions (F3) are resolved by `ChessCore` alone: a
    /// checkmating move is `mate(1)` (mover perspective, converted to
    /// white-perspective below) with no search, and a stalemating move is a
    /// dead draw (`.centipawns(0)`).
    ///
    /// A move matching any cached ranked line's first move (F6) is graded
    /// against that line's own cached score rather than accepted outright -
    /// rank one matching itself still yields a loss of 0 and grades
    /// `.strong`, but a rank-two or rank-three line grades on its own merit.
    private func scoreAttemptedMove(
        _ attempted: ReplayedMove,
        card: TrainingCard,
        attemptedUCI: String
    ) async throws -> WhitePerspectiveScore {
        if attempted.isCheckmate {
            return .mate(card.sideToMove == .white ? 1 : -1)
        }
        if !attempted.isCheck, Self.hasNoLegalMoves(fen: attempted.resultingFEN, sideToMove: card.sideToMove.opposite) {
            return .centipawns(0)
        }
        if let cached = card.rankedLines.first(where: { $0.principalVariationUCI.first == attemptedUCI }),
            let cachedScore = WhitePerspectiveScore(scoreCentipawns: cached.scoreCentipawns, mateIn: cached.mateIn)
        {
            return cachedScore
        }
        return try await evaluateAttemptedMove(
            TrainingPositionRequest(preMoveFEN: card.preMoveFEN, attemptedMoveUCI: attemptedUCI)
        )
    }

    /// Whether the side to move in `fen` has no legal move anywhere on the
    /// board - used to detect stalemate (paired with the caller's own check
    /// that the side to move is not in check).
    private static func hasNoLegalMoves(fen: String, sideToMove: ChessCore.PieceColor) -> Bool {
        let game = ChessGame(startingFEN: fen)
        let index = game.startIndex
        return occupiedSquares(ofColor: sideToMove, fen: fen).allSatisfy {
            game.legalMoves(from: SquareCoordinate(notation: $0), at: index).isEmpty
        }
    }

    /// Parses a FEN's piece-placement field for the square notations
    /// occupied by `color`, without depending on any engine-side board type.
    private static func occupiedSquares(ofColor color: ChessCore.PieceColor, fen: String) -> [String] {
        guard let placement = fen.split(separator: " ").first else { return [] }
        var squares: [String] = []
        var rank = 8
        for row in placement.split(separator: "/") {
            var file = 1
            for character in row {
                if let emptySquares = character.wholeNumberValue {
                    file += emptySquares
                } else {
                    let pieceIsWhite = character.isUppercase
                    if (pieceIsWhite && color == .white) || (!pieceIsWhite && color == .black) {
                        let fileLetter = Character(UnicodeScalar(96 + file)!)
                        squares.append("\(fileLetter)\(rank)")
                    }
                    file += 1
                }
            }
            rank -= 1
        }
        return squares
    }

    private func feedback(
        card: TrainingCard,
        attemptedUCI: String,
        attemptedSAN: String?,
        outcome: TrainingOutcome,
        loss: Int?
    ) -> TrainingEvaluation {
        let bestSAN = card.bestMoveSAN
        let explanation: String
        switch outcome {
        case .strong:
            explanation = card.explanation ?? "That move keeps the engine's preferred idea."
        case .playable:
            explanation = "Your idea is playable, but \(bestSAN ?? "the engine move") keeps more pressure."
        case .inaccurate:
            explanation = "\(bestSAN ?? "The engine move") was stronger here."
        case .incorrect:
            explanation = "That move misses the point of the position. Reset and try to find \(bestSAN ?? "the engine move")."
        }
        return TrainingEvaluation(
            outcome: outcome,
            attemptedUCI: attemptedUCI,
            lossCentipawns: loss,
            bestMoveUCI: card.bestMoveUCI,
            bestMoveSAN: bestSAN,
            attemptedMoveSAN: attemptedSAN,
            explanation: explanation
        )
    }

    /// A total comparison over `WhitePerspectiveScore`, oriented once to the
    /// mover's own perspective (the one place the Black-to-move sign
    /// convention is applied). Every combination of mate/centipawns on
    /// either side is handled explicitly - the old two-optional
    /// representation let a forced mate compare against a `nil` best
    /// centipawn value and fall through to `.incorrect` (F7); this cannot,
    /// because `WhitePerspectiveScore` has no representable "neither" case.
    private func classify(
        best: WhitePerspectiveScore,
        attempted: WhitePerspectiveScore,
        mover: ChessCore.PieceColor
    ) -> (outcome: TrainingOutcome, loss: Int?) {
        let orientedBest = best.oriented(forMover: mover)
        let orientedAttempted = attempted.oriented(forMover: mover)

        if case .mate(let attemptedDistance) = orientedAttempted, attemptedDistance <= 0 {
            // The mover is being mated - always incorrect, whatever the
            // cached best line was.
            return (.incorrect, nil)
        }

        switch orientedAttempted {
        case .mate(let attemptedDistance):
            // attemptedDistance > 0 guaranteed above: the mover forces mate.
            guard case .mate(let bestDistance) = orientedBest else {
                // A forced mate is never worse than any centipawn evaluation.
                return (.strong, nil)
            }
            // The plan specifies only that "a shorter or equal distance is
            // .strong" for mate vs. mate; the playable/inaccurate split
            // below for a *slower* mate is this evaluator's own judgement
            // call (mirroring the old classifyMate's tiering, shifted so
            // only extraMoves == 0 is strong), not a value the plan itself
            // fixes.
            let extraMoves = max(0, attemptedDistance - bestDistance)
            switch extraMoves {
            case 0: return (.strong, nil)
            case 1...3: return (.playable, nil)
            default: return (.inaccurate, nil)
            }

        case .centipawns(let attemptedCP):
            if case .mate = orientedBest {
                // The forced win was lost. Still credit a clearly winning
                // position rather than grading it as flatly wrong. 200cp is
                // this evaluator's own judgement call for "clearly winning"
                // - the plan asks for the distinction but does not fix a
                // number.
                return attemptedCP >= 200 ? (.inaccurate, nil) : (.incorrect, nil)
            }
            guard case .centipawns(let bestCP) = orientedBest else {
                return (.incorrect, nil)
            }
            let loss = max(0, bestCP - attemptedCP)
            switch loss {
            case 0...30: return (.strong, loss)
            case 31...90: return (.playable, loss)
            case 91...220: return (.inaccurate, loss)
            default: return (.incorrect, loss)
            }
        }
    }
}

protocol ReviewScheduling {
    func next(card: TrainingCardRecord, outcome: TrainingOutcome, now: Date) -> TrainingCardRecord
}

struct DeterministicReviewScheduler: ReviewScheduling {
    func next(card: TrainingCardRecord, outcome: TrainingOutcome, now: Date) -> TrainingCardRecord {
        var updated = card
        updated.lastResult = outcome.rawValue
        if outcome == .strong {
            updated.consecutiveSuccesses += 1
        } else {
            updated.consecutiveSuccesses = 0
        }

        switch outcome {
        case .incorrect, .inaccurate:
            updated.masteryState = MasteryState.learning.rawValue
            updated.dueAt = now
        case .playable:
            updated.masteryState = MasteryState.learning.rawValue
            updated.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        case .strong:
            if updated.consecutiveSuccesses >= 3 {
                updated.masteryState = MasteryState.mastered.rawValue
                updated.dueAt = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
            } else if updated.consecutiveSuccesses == 2 {
                updated.masteryState = MasteryState.review.rawValue
                updated.dueAt = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            } else {
                updated.masteryState = MasteryState.review.rawValue
                updated.dueAt = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
            }
        }
        return updated
    }
}
