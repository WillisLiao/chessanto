import ChessCore
import Foundation
import Persistence

@MainActor
final class PracticeSessionViewModel: ObservableObject {
    enum SessionState: Equatable {
        case loading
        case empty
        case prompt
        case evaluating
        case feedback(TrainingEvaluation)
        case completed(SessionSummary)
        case failed(String)
    }

    struct SessionSummary: Equatable {
        let cardsCompleted: Int
        let firstAttemptSuccesses: Int
        let recurringTheme: String?
        let nextDueDate: Date?
    }

    @Published private(set) var state: SessionState = .loading
    @Published private(set) var cards: [TrainingCard] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var hintCount = 0
    @Published private(set) var selectedSquare: BoardSquare?
    @Published private(set) var completedEvaluations: [TrainingEvaluation] = []
    @Published private(set) var firstAttemptSuccesses = 0

    private var cardRecords: [TrainingCardRecord] = []
    private let store: GameStore
    private let loadCards: () async throws -> [TrainingCardRecord]
    private let evaluator: any TrainingMoveEvaluator
    private let scheduler: any ReviewScheduling
    private var attemptsOnCurrentCard = 0
    private var completedCardCount = 0

    init(
        store: GameStore,
        loadCards: @escaping () async throws -> [TrainingCardRecord],
        evaluator: any TrainingMoveEvaluator,
        scheduler: any ReviewScheduling = DeterministicReviewScheduler()
    ) {
        self.store = store
        self.loadCards = loadCards
        self.evaluator = evaluator
        self.scheduler = scheduler
    }

    var currentCard: TrainingCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var position: BoardPosition {
        guard let fen = currentCard?.preMoveFEN else { return .empty }
        return BoardPositionMapper.position(fromFEN: fen) ?? .empty
    }

    var flipped: Bool {
        currentCard?.sideToMove == .black
    }

    var revealArrow: [(from: BoardSquare, to: BoardSquare)] {
        guard case .feedback(let feedback) = state,
            feedback.outcome != .strong,
            let uci = feedback.bestMoveUCI
        else { return [] }
        return arrow(for: uci).map { [$0] } ?? []
    }

    var legalDestinations: Set<BoardSquare> {
        guard let selectedSquare, let card = currentCard else { return [] }
        let game = ChessGame(startingFEN: card.preMoveFEN)
        return Set(
            game.legalMoves(from: SquareCoordinate(notation: selectedSquare.algebraic), at: game.startIndex)
                .compactMap { BoardSquare(algebraic: $0.notation) }
        )
    }

    func load() async {
        state = .loading
        do {
            cardRecords = try await loadCards()
            cards = cardRecords.compactMap(TrainingCard.init(record:))
            currentIndex = 0
            hintCount = 0
            attemptsOnCurrentCard = 0
            completedCardCount = 0
            state = cards.isEmpty ? .empty : .prompt
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func select(square: BoardSquare) {
        guard case .prompt = state else { return }
        guard let selectedSquare else {
            if position.pieces[square] != nil {
                self.selectedSquare = square
            }
            return
        }

        if square == selectedSquare {
            self.selectedSquare = nil
            return
        }
        if legalDestinations.contains(square) {
            self.selectedSquare = nil
            let attemptedUCI = selectedSquare.algebraic + square.algebraic
            Task { await submit(attemptedUCI: attemptedUCI) }
        } else if position.pieces[square] != nil {
            self.selectedSquare = square
        } else {
            self.selectedSquare = nil
        }
    }

    func hint() {
        guard case .prompt = state else { return }
        hintCount = min(hintCount + 1, 2)
    }

    func reveal() {
        guard let card = currentCard else { return }
        let feedback = TrainingEvaluation(
            outcome: .incorrect,
            attemptedUCI: "",
            lossCentipawns: nil,
            bestMoveUCI: card.bestMoveUCI,
            bestMoveSAN: card.bestMoveSAN,
            attemptedMoveSAN: nil,
            explanation: "Best was \(card.bestMoveSAN ?? "the engine move")."
        )
        state = .feedback(feedback)
    }

    func tryAgain() {
        selectedSquare = nil
        state = .prompt
    }

    func next() async {
        selectedSquare = nil
        hintCount = 0
        attemptsOnCurrentCard = 0
        if currentIndex < cards.count {
            completedCardCount += 1
        }
        currentIndex += 1
        if currentIndex >= cards.count {
            let nextDue = try? await store.nextTrainingDueDate()
            let theme = recurringTheme()
            state = .completed(SessionSummary(
                cardsCompleted: completedCardCount,
                firstAttemptSuccesses: firstAttemptSuccesses,
                recurringTheme: theme,
                nextDueDate: nextDue
            ))
        } else {
            state = .prompt
        }
    }

    func submit(attemptedUCI: String) async {
        guard let card = currentCard, currentIndex < cardRecords.count else { return }
        attemptsOnCurrentCard += 1
        state = .evaluating
        do {
            let result = try await evaluator.evaluate(card: card, attemptedUCI: attemptedUCI)
            completedEvaluations.append(result)
            if attemptsOnCurrentCard == 1, result.outcome == .strong {
                firstAttemptSuccesses += 1
            }

            let updatedCard = scheduler.next(card: cardRecords[currentIndex], outcome: result.outcome, now: Date())
            try await store.saveTrainingAttempt(
                TrainingAttemptRecord(
                    cardId: card.id,
                    attemptedUCI: attemptedUCI,
                    evaluationLossCentipawns: result.lossCentipawns,
                    outcome: result.outcome.rawValue,
                    hintCount: hintCount
                ),
                updatedCard: updatedCard
            )
            cardRecords[currentIndex] = updatedCard
            if let card = TrainingCard(record: updatedCard) {
                cards[currentIndex] = card
            }
            state = .feedback(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func recurringTheme() -> String? {
        let themes = cards.flatMap(\.themes)
        return Dictionary(grouping: themes, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    private func arrow(for uci: String) -> (from: BoardSquare, to: BoardSquare)? {
        guard uci.count >= 4,
            let from = BoardSquare(algebraic: String(uci.prefix(2))),
            let to = BoardSquare(algebraic: String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }
}
