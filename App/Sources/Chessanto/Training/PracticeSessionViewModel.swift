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
    @Published private(set) var linePreview: LinePreviewController?
    /// A non-blocking message for a recoverable engine failure during
    /// `submit`, shown alongside the prompt controls. `.failed` stays
    /// reserved for a failure to load the lesson at all (see `load()`); a
    /// bounded-search error mid-grading must not destroy the whole session.
    @Published private(set) var promptError: String?

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

    /// Defaults to the learner's own side to move, but the flip button
    /// (which stays available during inline practice per DD1) can override
    /// it, same as the replay board's own flip control.
    @Published private var isManuallyFlipped = false

    var flipped: Bool {
        isManuallyFlipped != (currentCard?.sideToMove == .black)
    }

    func toggleFlip() {
        isManuallyFlipped.toggle()
    }

    var revealArrow: [(from: BoardSquare, to: BoardSquare)] {
        guard case .feedback(let feedback) = state,
            feedback.outcome != .strong,
            let uci = feedback.bestMoveUCI
        else { return [] }
        return arrow(for: uci).map { [$0] } ?? []
    }

    /// The best move's origin square, shown once the learner has taken both
    /// hints (D2). Empty before then so the board reveals nothing early.
    var hintSquares: Set<BoardSquare> {
        guard hintCount >= 2, let uci = currentCard?.bestMoveUCI,
            let from = arrow(for: uci)?.from
        else { return [] }
        return [from]
    }

    /// The classification's plain word, e.g. "Inaccuracy" - never just the
    /// bare `?!` glyph the chip alone would show (D1/DD2).
    var classificationLabel: String? {
        currentCard?.classification.abbreviation
    }

    /// The first theme plus its plain-language gloss, once the learner has
    /// taken the first hint. `nil` before that hint, so nothing is revealed
    /// early.
    var themeHintText: String? {
        guard hintCount >= 1 else { return nil }
        return themeHintTextIgnoringHintCount
    }

    /// Same text as `themeHintText`, but always computed regardless of
    /// `hintCount` - the view renders this unconditionally and only toggles
    /// its opacity, so the reserved space (DD6) is the text's *real* height
    /// rather than a differently-wrapping placeholder's.
    var themeHintTextIgnoringHintCount: String {
        guard let theme = currentCard?.themes.first else { return "Look for the forcing idea." }
        guard let gloss = ChessGlossary.gloss(for: theme) else { return theme }
        return "\(theme) - \(gloss)"
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
        endLinePreview()
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
        startBetterLinePreview()
    }

    func tryAgain() {
        endLinePreview()
        selectedSquare = nil
        state = .prompt
    }

    func next() async {
        endLinePreview()
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
        promptError = nil
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
            startBetterLinePreview()
        } catch let error as EngineSearchError {
            // Recoverable: the card, board, and attempt count are untouched
            // so the learner can simply try the same card again.
            attemptsOnCurrentCard -= 1
            promptError = retryableMessage(for: error)
            state = .prompt
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func retryableMessage(for error: EngineSearchError) -> String {
        switch error {
        case .timedOut:
            return "The engine took too long to respond. Try again."
        case .cancelled:
            return "The evaluation was cancelled. Try again."
        case .noAnalysis, .engineUnavailable:
            return "The engine couldn't evaluate that move. Try again."
        }
    }

    func startBetterLinePreview() {
        guard let card = currentCard,
            let line = card.rankedLines
                .sorted(by: { $0.rank < $1.rank })
                .first(where: { !$0.principalVariationUCI.isEmpty })
        else {
            endLinePreview()
            return
        }
        let preview = LinePreviewController(
            label: "Better line",
            startingFEN: card.preMoveFEN,
            uciMoves: line.principalVariationUCI
        )
        linePreview = preview
        preview.play()
    }

    func endLinePreview() {
        linePreview?.pause()
        linePreview = nil
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
