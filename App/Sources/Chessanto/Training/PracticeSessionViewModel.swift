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
        case replying(String)
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

    /// One value owns the whole exchange. `legalPVPrefix` is created once
    /// from the stored rank-one line and never includes a move that replay
    /// could not legally apply. `nextLearnerIndex` points at the next even
    /// index in that prefix; the intervening odd index is the automatic reply.
    /// The first-attempt flag survives a retry by being copied into the reset
    /// value rather than being inferred from a collection of booleans.
    struct PracticeExchange: Equatable, Sendable {
        enum CompletionReason: Equatable, Sendable {
            case lineExhausted
            case checkmate
        }

        enum Stage: Equatable, Sendable {
            case awaitingLearner
            case grading
            case replying(String)
            case wrongFeedback(TrainingEvaluation)
            case completed(CompletionReason)
        }

        let legalPVPrefix: [String]
        var nextLearnerIndex: Int
        var appliedUCI: [String]
        var stage: Stage
        var learnerOutcomes: [TrainingOutcome]
        var learnerEvaluations: [TrainingEvaluation]
        var allPliesFirstAttempt: Bool

        init(legalPVPrefix: [String], allPliesFirstAttempt: Bool = true) {
            self.legalPVPrefix = legalPVPrefix
            self.nextLearnerIndex = 0
            self.appliedUCI = []
            self.stage = .awaitingLearner
            self.learnerOutcomes = []
            self.learnerEvaluations = []
            self.allPliesFirstAttempt = allPliesFirstAttempt
        }
    }

    @Published private(set) var state: SessionState = .loading
    @Published private(set) var cards: [TrainingCard] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var hintCount = 0
    @Published private var interaction = BoardInteraction()
    @Published private(set) var completedEvaluations: [TrainingEvaluation] = []
    @Published private(set) var firstAttemptSuccesses = 0
    @Published private(set) var linePreview: LinePreviewController?
    @Published private(set) var promptError: String?
    @Published private(set) var exchange: PracticeExchange?

    private var cardRecords: [TrainingCardRecord] = []
    private let store: GameStore
    private let loadCards: () async throws -> [TrainingCardRecord]
    private let evaluator: any TrainingMoveEvaluator
    private let scheduler: any ReviewScheduling
    private let replyDelay: @Sendable () async -> Void
    private var replyTask: Task<Void, Never>?
    private var completedCardCount = 0

    init(
        store: GameStore,
        loadCards: @escaping () async throws -> [TrainingCardRecord],
        evaluator: any TrainingMoveEvaluator,
        scheduler: any ReviewScheduling = DeterministicReviewScheduler(),
        replyDelay: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    ) {
        self.store = store
        self.loadCards = loadCards
        self.evaluator = evaluator
        self.scheduler = scheduler
        self.replyDelay = replyDelay
    }

    var currentCard: TrainingCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    private var appliedMoves: [ReplayedMove] {
        guard let card = currentCard, let exchange else { return [] }
        return ChessGame.replayLine(fromUCI: exchange.appliedUCI, startingFEN: card.preMoveFEN)
    }

    private var currentFEN: String? {
        appliedMoves.last?.resultingFEN ?? currentCard?.preMoveFEN
    }

    var position: BoardPosition {
        guard let fen = currentFEN else { return .empty }
        return BoardPositionMapper.position(fromFEN: fen) ?? .empty
    }

    var lastMove: (from: BoardSquare, to: BoardSquare)? {
        guard let uci = appliedMoves.last?.uci else { return nil }
        return arrow(for: uci)
    }

    /// The progress label counts learner turns, not automatic replies.
    var stepProgressText: String {
        guard let exchange else { return "Step 0 of 0" }
        let total = learnerCount(in: exchange.legalPVPrefix)
        guard total > 0 else { return "Step 0 of 0" }
        let step = min(exchange.nextLearnerIndex / 2 + 1, total)
        return "Step \(step) of \(total)"
    }

    var isInteractionEnabled: Bool {
        guard case .prompt = state, exchange?.stage == .awaitingLearner else { return false }
        return true
    }

    /// Defaults to the learner's own side to move, but the flip button can
    /// override it, same as the replay board's own flip control.
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

    /// Kept at level two for source compatibility with the phase-one board
    /// tests. The live board uses `originHintSquares` for the third hint slot.
    var hintSquares: Set<BoardSquare> {
        guard hintCount >= 2, let uci = expectedLearnerUCI,
            let from = arrow(for: uci)?.from
        else { return [] }
        return [from]
    }

    var originHintSquares: Set<BoardSquare> {
        guard hintCount >= 3, let uci = expectedLearnerUCI,
            let from = arrow(for: uci)?.from
        else { return [] }
        return [from]
    }

    var classificationLabel: String? {
        currentCard?.classification.abbreviation
    }

    /// This property retains the phase-one API, while the view places the same
    /// text in the second of the three stable hint slots.
    var themeHintText: String? {
        guard hintCount >= 1 else { return nil }
        return themeHintTextIgnoringHintCount
    }

    var themeHintTextIgnoringHintCount: String {
        guard let theme = currentCard?.displayThemes.first else { return "Look for the forcing idea." }
        guard let gloss = ChessGlossary.gloss(for: theme) else { return theme }
        return "\(theme) - \(gloss)"
    }

    var threatHintText: String? {
        guard hintCount >= 1 else { return nil }
        return threatHintTextIgnoringHintCount
    }

    var threatHintTextIgnoringHintCount: String {
        guard let san = currentCard?.ignoredThreatSAN else { return "Look for the forcing idea." }
        return "What is your opponent threatening? \(san)"
    }

    var originHintTextIgnoringHintCount: String {
        guard let uci = expectedLearnerUCI else { return " " }
        return "Start from \(String(uci.prefix(2))) - highlighted on the board."
    }

    var selectedSquare: BoardSquare? { interaction.selectedSquare }

    var pendingPromotion: BoardInteraction.PendingPromotion? { interaction.pendingPromotion }

    var legalDestinations: Set<BoardSquare> {
        interaction.legalDestinations(context: interactionContext)
    }

    /// BoardInteraction remains the only selection, drag, and promotion
    /// machine. Its context is rebuilt from the currently applied exchange
    /// prefix, so legal moves and promotion checks never use the old card FEN.
    private var interactionContext: BoardInteraction.Context {
        let fen = currentFEN
        return BoardInteraction.Context(
            position: position,
            legalDestinations: { square in
                guard let fen else { return [] }
                let game = ChessGame(startingFEN: fen)
                return Set(
                    game.legalMoves(from: SquareCoordinate(notation: square.algebraic), at: game.startIndex)
                        .compactMap { BoardSquare(algebraic: $0.notation) }
                )
            },
            isPromotion: { from, to in
                guard let fen else { return false }
                let game = ChessGame(startingFEN: fen)
                return game.isPromotion(
                    from: SquareCoordinate(notation: from.algebraic),
                    to: SquareCoordinate(notation: to.algebraic),
                    at: game.startIndex
                )
            }
        )
    }

    func load() async {
        endLinePreview()
        cancelReplyTask()
        interaction.reset()
        exchange = nil
        state = .loading
        do {
            let loadedRecords = try await loadCards()
            let validPairs = loadedRecords.compactMap { record -> (TrainingCardRecord, TrainingCard)? in
                guard let card = TrainingCard(record: record) else { return nil }
                return (record, card)
            }
            cardRecords = validPairs.map(\.0)
            cards = validPairs.map(\.1)
            currentIndex = 0
            hintCount = 0
            completedCardCount = 0
            resetExchange(allPliesFirstAttempt: true)
            state = cards.isEmpty ? .empty : .prompt
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func select(square: BoardSquare) {
        guard isInteractionEnabled else { return }
        resolve(interaction.select(square, context: interactionContext))
    }

    func beginDrag(from square: BoardSquare) {
        guard isInteractionEnabled else { return }
        interaction.beginDrag(from: square, context: interactionContext)
    }

    func drop(from: BoardSquare, to: BoardSquare) {
        guard isInteractionEnabled else { return }
        resolve(interaction.drop(from: from, to: to, context: interactionContext))
    }

    func completePromotion(with kind: PromotionKind) async {
        guard isInteractionEnabled else { return }
        guard case .play(let move) = interaction.choosePromotion(kind) else { return }
        await submit(attemptedUCI: move.uci)
    }

    func cancelPromotion() {
        interaction.cancelPromotion()
    }

    private func resolve(_ resolution: BoardInteraction.Resolution) {
        guard case .play(let move) = resolution else { return }
        Task { await submit(attemptedUCI: move.uci) }
    }

    func hint() {
        guard isInteractionEnabled else { return }
        hintCount = min(hintCount + 1, 3)
    }

    func reveal() {
        guard let card = currentCard else { return }
        let expected = expectedLearnerUCI ?? card.bestMoveUCI
        let expectedSAN = expected.flatMap { replayOne($0, from: currentFEN)?.san }
        let feedback = TrainingEvaluation(
            outcome: .incorrect,
            attemptedUCI: "",
            lossCentipawns: nil,
            bestMoveUCI: expected,
            bestMoveSAN: expectedSAN,
            attemptedMoveSAN: nil,
            explanation: "Best was \(expectedSAN ?? "the engine move")."
        )
        exchange?.stage = .wrongFeedback(feedback)
        state = .feedback(feedback)
        startBetterLinePreview()
    }

    func tryAgain() {
        endLinePreview()
        cancelReplyTask()
        interaction.reset()
        resetExchange(allPliesFirstAttempt: false)
        state = .prompt
    }

    func next() async {
        endLinePreview()
        cancelReplyTask()
        interaction.reset()
        hintCount = 0
        if currentIndex < cards.count {
            completedCardCount += 1
        }
        currentIndex += 1
        if currentIndex >= cards.count {
            let nextDue = try? await store.nextTrainingDueDate()
            let theme = recurringTheme()
            exchange = nil
            state = .completed(SessionSummary(
                cardsCompleted: completedCardCount,
                firstAttemptSuccesses: firstAttemptSuccesses,
                recurringTheme: theme,
                nextDueDate: nextDue
            ))
        } else {
            resetExchange(allPliesFirstAttempt: true)
            state = .prompt
        }
    }

    func submit(attemptedUCI: String) async {
        guard let card = currentCard,
            currentIndex < cardRecords.count,
            case .prompt = state,
            var currentExchange = exchange,
            currentExchange.stage == .awaitingLearner
        else { return }

        let cardID = card.id
        let learnerIndex = currentExchange.nextLearnerIndex
        let appliedBefore = currentExchange.appliedUCI
        currentExchange.stage = .grading
        exchange = currentExchange
        state = .evaluating
        promptError = nil

        if hasMultipleLearnerPlies(in: currentExchange) {
            await submitExact(
                card: card,
                cardID: cardID,
                learnerIndex: learnerIndex,
                appliedBefore: appliedBefore,
                attemptedUCI: attemptedUCI
            )
        } else {
            await submitLegacy(
                card: card,
                cardID: cardID,
                learnerIndex: learnerIndex,
                appliedBefore: appliedBefore,
                attemptedUCI: attemptedUCI
            )
        }
    }

    private func submitLegacy(
        card: TrainingCard,
        cardID: Int64,
        learnerIndex: Int,
        appliedBefore: [String],
        attemptedUCI: String
    ) async {
        do {
            let result = try await evaluator.evaluate(card: card, attemptedUCI: attemptedUCI)
            guard acceptGrading(cardID: cardID, learnerIndex: learnerIndex, appliedBefore: appliedBefore) else { return }
            completedEvaluations.append(result)
            guard var currentExchange = exchange else { return }
            currentExchange.learnerOutcomes.append(result.outcome)
            currentExchange.learnerEvaluations.append(result)

            let expected = currentExchange.legalPVPrefix.first
            let exactFirstMove = expected == attemptedUCI
            if result.outcome == .strong,
                exactFirstMove,
                let move = replayOne(attemptedUCI, from: currentFEN)
            {
                currentExchange.appliedUCI.append(attemptedUCI)
                currentExchange.nextLearnerIndex = 2
                if move.isCheckmate || currentExchange.legalPVPrefix.count <= 1 {
                    exchange = currentExchange
                    await completeExchange(card: card, result: result, reason: move.isCheckmate ? .checkmate : .lineExhausted)
                } else {
                    exchange = currentExchange
                    beginReply(cardID: cardID, learnerIndex: learnerIndex)
                }
                return
            }

            if result.outcome == .incorrect {
                currentExchange.allPliesFirstAttempt = false
                currentExchange.stage = .wrongFeedback(result)
            } else {
                currentExchange.stage = .completed(.lineExhausted)
            }
            exchange = currentExchange
            await persistTerminal(card: card, result: result)
            state = .feedback(result)
            startBetterLinePreview()
        } catch let error as EngineSearchError {
            guard acceptGrading(cardID: cardID, learnerIndex: learnerIndex, appliedBefore: appliedBefore) else { return }
            promptError = retryableMessage(for: error)
            exchange?.stage = .awaitingLearner
            state = .prompt
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func submitExact(
        card: TrainingCard,
        cardID: Int64,
        learnerIndex: Int,
        appliedBefore: [String],
        attemptedUCI: String
    ) async {
        guard acceptGrading(cardID: cardID, learnerIndex: learnerIndex, appliedBefore: appliedBefore),
            var currentExchange = exchange,
            let expectedUCI = currentExchange.legalPVPrefix[safe: learnerIndex]
        else { return }

        let expectedMove = replayOne(expectedUCI, from: currentFEN)
        let attemptedMove = replayOne(attemptedUCI, from: currentFEN)
        let matches = attemptedUCI == expectedUCI && expectedMove != nil
        let result: TrainingEvaluation
        if matches, let expectedMove {
            result = TrainingEvaluation(
                outcome: .strong,
                attemptedUCI: attemptedUCI,
                lossCentipawns: 0,
                bestMoveUCI: expectedUCI,
                bestMoveSAN: expectedMove.san,
                attemptedMoveSAN: attemptedMove?.san,
                explanation: card.explanation ?? "That move keeps the engine's preferred idea."
            )
        } else {
            let expectedSAN = expectedMove?.san ?? card.bestMoveSAN
            result = TrainingEvaluation(
                outcome: .incorrect,
                attemptedUCI: attemptedUCI,
                lossCentipawns: nil,
                bestMoveUCI: expectedUCI,
                bestMoveSAN: expectedSAN,
                attemptedMoveSAN: attemptedMove?.san,
                explanation: wrongExplanation(card: card, expectedSAN: expectedSAN)
            )
        }

        completedEvaluations.append(result)
        currentExchange.learnerOutcomes.append(result.outcome)
        currentExchange.learnerEvaluations.append(result)
        guard matches, let expectedMove else {
            currentExchange.allPliesFirstAttempt = false
            currentExchange.stage = .wrongFeedback(result)
            exchange = currentExchange
            await persistTerminal(card: card, result: result)
            state = .feedback(result)
            startBetterLinePreview()
            return
        }

        currentExchange.appliedUCI.append(expectedUCI)
        let nextLearnerIndex = learnerIndex + 2
        currentExchange.nextLearnerIndex = nextLearnerIndex
        let hasReply = currentExchange.legalPVPrefix[safe: learnerIndex + 1] != nil
        if expectedMove.isCheckmate || !hasReply {
            exchange = currentExchange
            await completeExchange(
                card: card,
                result: result,
                reason: expectedMove.isCheckmate ? .checkmate : .lineExhausted
            )
        } else {
            exchange = currentExchange
            beginReply(cardID: cardID, learnerIndex: learnerIndex)
        }
    }

    private func beginReply(cardID: Int64, learnerIndex: Int) {
        guard let exchange,
            let replyUCI = exchange.legalPVPrefix[safe: learnerIndex + 1],
            let reply = replayOne(replyUCI, from: currentFEN)
        else {
            return
        }

        var replyingExchange = exchange
        replyingExchange.stage = .replying(reply.san)
        self.exchange = replyingExchange
        state = .replying(reply.san)
        cancelReplyTask()
        let expectedApplied = replyingExchange.appliedUCI
        let nextLearnerIndex = replyingExchange.nextLearnerIndex
        replyTask = Task { [weak self] in
            await self?.replyDelay()
            guard !Task.isCancelled else { return }
            await self?.applyReply(
                cardID: cardID,
                learnerIndex: learnerIndex,
                expectedApplied: expectedApplied,
                nextLearnerIndex: nextLearnerIndex
            )
        }
    }

    private func applyReply(
        cardID: Int64,
        learnerIndex: Int,
        expectedApplied: [String],
        nextLearnerIndex: Int
    ) async {
        guard let card = currentCard,
            card.id == cardID,
            var currentExchange = exchange,
            case .replying = currentExchange.stage,
            currentExchange.nextLearnerIndex == nextLearnerIndex,
            currentExchange.appliedUCI == expectedApplied,
            let replyUCI = currentExchange.legalPVPrefix[safe: learnerIndex + 1],
            let reply = replayOne(replyUCI, from: currentFEN)
        else { return }

        currentExchange.appliedUCI.append(replyUCI)
        if reply.isCheckmate || nextLearnerIndex >= currentExchange.legalPVPrefix.count {
            currentExchange.stage = .completed(reply.isCheckmate ? .checkmate : .lineExhausted)
            exchange = currentExchange
            if let result = currentExchange.learnerEvaluations.last {
                await completeExchange(
                    card: card,
                    result: result,
                    reason: reply.isCheckmate ? .checkmate : .lineExhausted
                )
            }
        } else {
            currentExchange.stage = .awaitingLearner
            exchange = currentExchange
            state = .prompt
        }
    }

    private func completeExchange(
        card: TrainingCard,
        result: TrainingEvaluation,
        reason: PracticeExchange.CompletionReason
    ) async {
        guard var currentExchange = exchange else { return }
        currentExchange.stage = .completed(reason)
        exchange = currentExchange
        await persistTerminal(card: card, result: result)
        if case .failed = state {
            return
        }
        guard case .completed = exchange?.stage else { return }
        state = .feedback(result)
        startBetterLinePreview()
    }

    private func persistTerminal(card: TrainingCard, result: TrainingEvaluation) async {
        guard currentIndex < cardRecords.count else { return }
        let cardID = card.id
        let updatedCard = scheduler.next(card: cardRecords[currentIndex], outcome: result.outcome, now: Date())
        do {
            try await store.saveTrainingAttempt(
                TrainingAttemptRecord(
                    cardId: cardID,
                    attemptedUCI: result.attemptedUCI,
                    evaluationLossCentipawns: result.lossCentipawns,
                    outcome: result.outcome.rawValue,
                    hintCount: hintCount
                ),
                updatedCard: updatedCard
            )
            cardRecords[currentIndex] = updatedCard
            if let updated = TrainingCard(record: updatedCard) {
                cards[currentIndex] = updated
            }
            if result.outcome == .strong, exchange?.allPliesFirstAttempt == true {
                firstAttemptSuccesses += 1
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func acceptGrading(cardID: Int64, learnerIndex: Int, appliedBefore: [String]) -> Bool {
        guard let card = currentCard, card.id == cardID,
            let exchange,
            exchange.nextLearnerIndex == learnerIndex,
            exchange.appliedUCI == appliedBefore,
            exchange.stage == .grading
        else { return false }
        return true
    }

    private func wrongExplanation(card: TrainingCard, expectedSAN: String?) -> String {
        let point = card.explanation ?? "That move misses the point of the position."
        return "\(point) The expected move here is \(expectedSAN ?? "the engine move")."
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
        let themes = cards.flatMap(\.displayThemes)
        return Dictionary(grouping: themes, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    private func resetExchange(allPliesFirstAttempt: Bool) {
        guard let card = currentCard else {
            exchange = nil
            return
        }
        exchange = PracticeExchange(
            legalPVPrefix: legalRankOnePrefix(for: card),
            allPliesFirstAttempt: allPliesFirstAttempt
        )
    }

    private func legalRankOnePrefix(for card: TrainingCard) -> [String] {
        guard let line = card.rankedLines.first(where: { $0.rank == 1 }) else { return [] }
        return ChessGame.replayLine(fromUCI: line.principalVariationUCI, startingFEN: card.preMoveFEN).map(\.uci)
    }

    private var expectedLearnerUCI: String? {
        guard let exchange else { return nil }
        return exchange.legalPVPrefix[safe: exchange.nextLearnerIndex]
    }

    private func learnerCount(in prefix: [String]) -> Int {
        guard !prefix.isEmpty else { return 0 }
        return (prefix.count + 1) / 2
    }

    private func hasMultipleLearnerPlies(in exchange: PracticeExchange) -> Bool {
        learnerCount(in: exchange.legalPVPrefix) > 1
    }

    private func replayOne(_ uci: String, from fen: String?) -> ReplayedMove? {
        guard let fen else { return nil }
        return ChessGame.replayLine(fromUCI: [uci], startingFEN: fen).first
    }

    private func cancelReplyTask() {
        replyTask?.cancel()
        replyTask = nil
    }

    private func arrow(for uci: String) -> (from: BoardSquare, to: BoardSquare)? {
        guard uci.count >= 4,
            let from = BoardSquare(algebraic: String(uci.prefix(2))),
            let to = BoardSquare(algebraic: String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
