import AnalysisKit
import Foundation
import Persistence
import Testing
@testable import Chessanto

private final class RecordingReviewScheduler: ReviewScheduling {
    private(set) var outcomes: [TrainingOutcome] = []

    func next(card: TrainingCardRecord, outcome: TrainingOutcome, now: Date) -> TrainingCardRecord {
        outcomes.append(outcome)
        return card
    }
}

@MainActor
struct PracticeSessionViewModelTests {
    @Test
    func hintStrongMoveAndCompletionUpdateExplicitStates() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake",
            themesJSON: #"["Center control"]"#,
            explanation: "Better was e4."
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                .centipawns(0)
            }
        )

        await viewModel.load()
        #expect(viewModel.state == .prompt)
        #expect(viewModel.cards.count == 1)

        viewModel.hint()
        #expect(viewModel.hintCount == 1)

        await viewModel.submit(attemptedUCI: "e2e4")
        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected feedback state")
            return
        }
        #expect(feedback.outcome == .strong)

        await viewModel.next()
        guard case .completed(let summary) = viewModel.state else {
            Issue.record("Expected completed state")
            return
        }
        #expect(summary.cardsCompleted == 1)
        #expect(summary.firstAttemptSuccesses == 1)

        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.count == 1)
        #expect(attempts[0].outcome == "strong")
        #expect(attempts[0].hintCount == 1)
    }

    @Test
    func revealShowsBestMoveWithoutRecordingAttempt() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                .centipawns(0)
            }
        )

        await viewModel.load()
        viewModel.reveal()

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected feedback state")
            return
        }
        #expect(feedback.bestMoveUCI == "e2e4")
        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.isEmpty)
    }

    @Test
    func retriesDoNotOvercountCompletedCards() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { request in
                .centipawns(request.attemptedMoveUCI == "e2e4" ? 40 : -300)
            }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "g1f3")
        viewModel.tryAgain()
        await viewModel.submit(attemptedUCI: "e2e4")
        await viewModel.next()

        guard case .completed(let summary) = viewModel.state else {
            Issue.record("Expected completed state")
            return
        }
        #expect(summary.cardsCompleted == 1)
        #expect(summary.firstAttemptSuccesses == 0)
    }

    @Test
    func engineTimeoutReturnsToPromptWithRetryableMessage() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                throw EngineSearchError.timedOut(milliseconds: 4400)
            }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "g1f3")

        #expect(viewModel.state == .prompt)
        #expect(viewModel.promptError != nil)
    }

    @Test
    func engineTimeoutDoesNotRecordAnAttemptOrAdvanceScheduling() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                throw EngineSearchError.timedOut(milliseconds: 4400)
            }
        )

        await viewModel.load()
        let dueBefore = try await store.trainingCards(gameId: game.id!).first
        await viewModel.submit(attemptedUCI: "g1f3")

        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.isEmpty)
        let dueAfter = try await store.trainingCards(gameId: game.id!).first
        #expect(dueBefore?.dueAt == dueAfter?.dueAt)
        #expect(dueBefore?.consecutiveSuccesses == dueAfter?.consecutiveSuccesses)
    }

    @Test
    func retryAfterEngineTimeoutCanStillGradeTheSameCard() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let timeoutState = TrainingTimeoutState()
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                if await timeoutState.shouldTimeout {
                    throw EngineSearchError.timedOut(milliseconds: 4400)
                }
                return .centipawns(40)
            }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "g1f3")
        #expect(viewModel.state == .prompt)

        await timeoutState.disable()
        await viewModel.submit(attemptedUCI: "g1f3")

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected feedback state")
            return
        }
        #expect(feedback.outcome == .strong)

        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.count == 1)
    }

    @Test
    func hintSquaresAreEmptyBeforeSecondHint() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        #expect(viewModel.hintSquares.isEmpty)

        viewModel.hint()
        #expect(viewModel.hintCount == 1)
        #expect(viewModel.hintSquares.isEmpty)
    }

    @Test
    func secondHintExposesBestMoveOriginSquare() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        viewModel.hint()
        viewModel.hint()
        #expect(viewModel.hintCount == 2)
        #expect(viewModel.hintSquares == [BoardSquare(algebraic: "e2")!])
    }

    @Test
    func promptExposesClassificationLabelNotOnlyGlyph() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "inaccuracy"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        #expect(viewModel.classificationLabel == "Inaccuracy")
    }

    @Test
    func themeHintExposesGlossForEnPrise() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4"],"depth":12}]
            """,
            classification: "mistake",
            themesJSON: #"["Material left en prise"]"#
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        #expect(viewModel.themeHintText == nil)

        viewModel.hint()
        let hintText = try #require(viewModel.themeHintText)
        #expect(hintText.contains("Material left en prise"))
        #expect(hintText.contains("left where the opponent can capture it for free"))
    }

    @Test
    func completingEveryLearnerPlyStartsTheFullBetterLine() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","g1f3"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                Issue.record("The multi-ply path must not call the evaluator")
                return .centipawns(40)
            },
            replyDelay: { }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "e2e4")
        #expect(viewModel.state == .replying("e5"))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(viewModel.state == .prompt)
        await viewModel.submit(attemptedUCI: "g1f3")

        let preview = try #require(viewModel.linePreview)
        #expect(preview.label == "Better line")
        #expect(preview.stepCount == 4)
        #expect(preview.isPlaying)
    }

    @Test
    func tryingAgainEndsAutomaticLinePlayback() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(-400) }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "g1f3")
        #expect(viewModel.linePreview != nil)

        viewModel.tryAgain()

        #expect(viewModel.linePreview == nil)
        #expect(viewModel.state == .prompt)
    }

    @Test
    func twoPlyPVUsesExactStoredMoveAndRepliesWithoutEvaluator() async throws {
        let store = try GameStore()
        let scheduler = RecordingReviewScheduler()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5"],"depth":12}]
            """,
            classification: "mistake",
            explanation: "The center needed attention."
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                Issue.record("A two-ply PV must use exact stored-line grading")
                return .centipawns(0)
            },
            scheduler: scheduler,
            replyDelay: { }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "d2d4")

        guard case .feedback(let wrongFeedback) = viewModel.state else {
            Issue.record("Expected the non-PV legal alternative to be rejected")
            return
        }
        #expect(wrongFeedback.outcome == .incorrect)
        #expect(wrongFeedback.attemptedMoveSAN == "d4")
        #expect(wrongFeedback.bestMoveSAN == "e4")
        #expect(scheduler.outcomes == [.incorrect])
        #expect(try await store.trainingAttempts(cardId: card.id!).count == 1)

        viewModel.tryAgain()
        await viewModel.submit(attemptedUCI: "e2e4")
        #expect(viewModel.state == .replying("e5"))
        #expect(viewModel.exchange?.appliedUCI == ["e2e4"])
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(viewModel.state == .feedback(TrainingEvaluation(
            outcome: .strong,
            attemptedUCI: "e2e4",
            lossCentipawns: 0,
            bestMoveUCI: "e2e4",
            bestMoveSAN: "e4",
            attemptedMoveSAN: "e4",
            explanation: "The center needed attention."
        )))
        #expect(viewModel.exchange?.appliedUCI == ["e2e4", "e7e5"])
        #expect(viewModel.exchange?.stage == .completed(.lineExhausted))
        #expect(scheduler.outcomes == [.incorrect, .strong])
        #expect(try await store.trainingAttempts(cardId: card.id!).map(\.outcome) == ["incorrect", "strong"])
    }

    @Test
    func feedbackWithoutAPlayableRankedLineDoesNotCreateAPreview() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":[],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        viewModel.reveal()

        #expect(viewModel.linePreview == nil)
    }

    /// The end-user path for a promotion card: click the pawn, click the
    /// promotion square. The engine's own best move is `b7b8q`, so the
    /// square pair alone (`b7b8`) cannot name it - the session has to ask
    /// which piece before it can grade the learner's answer.
    @Test
    func promotingByClickingTheBackRankGradesTheEngineMoveAsStrong() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "8/1P6/8/7k/8/8/8/4K3 w - - 0 1",
            sideToMove: "white",
            bestMoveUCI: "b7b8q",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":900,"principalVariationUCI":["b7b8q"],"depth":16}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(-9999) }
        )

        await viewModel.load()
        viewModel.select(square: try #require(BoardSquare(algebraic: "b7")))
        viewModel.select(square: try #require(BoardSquare(algebraic: "b8")))

        #expect(viewModel.pendingPromotion?.from.algebraic == "b7")
        #expect(viewModel.pendingPromotion?.to.algebraic == "b8")

        await viewModel.completePromotion(with: .queen)

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected feedback state, got \(viewModel.state)")
            return
        }
        #expect(feedback.outcome == .strong)
        #expect(feedback.attemptedUCI == "b7b8q")
        #expect(feedback.attemptedMoveSAN == "b8=Q")
    }

    @Test
    func cancellingThePromotionPickerLeavesTheCardUnanswered() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "8/1P6/8/7k/8/8/8/4K3 w - - 0 1",
            sideToMove: "white",
            bestMoveUCI: "b7b8q",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":900,"principalVariationUCI":["b7b8q"],"depth":16}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(-9999) }
        )

        await viewModel.load()
        viewModel.select(square: try #require(BoardSquare(algebraic: "b7")))
        viewModel.select(square: try #require(BoardSquare(algebraic: "b8")))
        viewModel.cancelPromotion()

        #expect(viewModel.pendingPromotion == nil)
        #expect(viewModel.state == .prompt)
        #expect(try await store.trainingAttempts(cardId: card.id!).isEmpty)
    }

    @Test
    func multiPlyExchangeShowsReplyThenPromptsForTheNextLearnerMove() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5 2. Nf3", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","g1f3"],"depth":12}]
            """,
            classification: "mistake",
            explanation: "Better was e4."
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                Issue.record("A rich multi-ply card must use exact UCI grading without an engine search")
                return .centipawns(0)
            },
            replyDelay: {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        )

        await viewModel.load()
        #expect(viewModel.exchange?.legalPVPrefix == ["e2e4", "e7e5", "g1f3"])
        #expect(viewModel.exchange?.nextLearnerIndex == 0)
        #expect(viewModel.stepProgressText == "Step 1 of 2")

        await viewModel.submit(attemptedUCI: "e2e4")
        guard case .replying(let san) = viewModel.state else {
            Issue.record("Expected the automatic reply state")
            return
        }
        #expect(san == "e5")
        #expect(viewModel.exchange?.appliedUCI == ["e2e4"])

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(viewModel.state == .prompt)
        #expect(viewModel.exchange?.appliedUCI == ["e2e4", "e7e5"])
        #expect(viewModel.exchange?.nextLearnerIndex == 2)
        #expect(viewModel.position.pieces[BoardSquare(algebraic: "e5")!] != nil)
        #expect(viewModel.lastMove?.from.algebraic == "e7")
        #expect(viewModel.lastMove?.to.algebraic == "e5")

        await viewModel.submit(attemptedUCI: "g1f3")
        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected final feedback")
            return
        }
        #expect(feedback.outcome == .strong)
        #expect(viewModel.exchange?.stage == .completed(.lineExhausted))
        #expect(viewModel.exchange?.appliedUCI == ["e2e4", "e7e5", "g1f3"])
        #expect(viewModel.exchange?.learnerOutcomes == [.strong, .strong])
        #expect(viewModel.linePreview != nil)

        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.count == 1)
        #expect(attempts[0].outcome == "strong")
    }

    @Test
    func wrongSecondLearnerMoveResetsWholeExchangeAndKeepsFirstAttemptFalse() async throws {
        let store = try GameStore()
        let scheduler = RecordingReviewScheduler()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5 2. Nf3", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","g1f3"],"depth":12}]
            """,
            classification: "mistake",
            explanation: "The center needed attention."
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) },
            scheduler: scheduler,
            replyDelay: { try? await Task.sleep(nanoseconds: 1_000_000) }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "e2e4")
        try await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.submit(attemptedUCI: "d2d4")

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected wrong feedback on the second learner ply")
            return
        }
        #expect(feedback.outcome == .incorrect)
        #expect(feedback.attemptedMoveSAN == "d4")
        #expect(feedback.bestMoveSAN == "Nf3")
        #expect(feedback.explanation.contains("The center needed attention."))
        #expect(feedback.explanation.contains("Nf3"))
        #expect(viewModel.exchange?.stage == .wrongFeedback(feedback))
        #expect(viewModel.exchange?.appliedUCI == ["e2e4", "e7e5"])
        #expect(viewModel.exchange?.allPliesFirstAttempt == false)
        #expect(scheduler.outcomes == [.incorrect])

        viewModel.tryAgain()
        #expect(viewModel.exchange?.appliedUCI == [])
        #expect(viewModel.exchange?.nextLearnerIndex == 0)
        #expect(viewModel.exchange?.allPliesFirstAttempt == false)

        await viewModel.submit(attemptedUCI: "e2e4")
        try await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.submit(attemptedUCI: "g1f3")
        await viewModel.next()

        guard case .completed(let summary) = viewModel.state else {
            Issue.record("Expected completion after a successful retry")
            return
        }
        #expect(summary.firstAttemptSuccesses == 0)
        #expect(scheduler.outcomes == [.incorrect, .strong])
        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(attempts.count == 2)
        #expect(attempts.map(\.outcome) == ["incorrect", "strong"])
    }

    @Test
    func learnerCheckmateCompletesWithoutAnOpponentReply() async throws {
        let store = try GameStore()
        let scheduler = RecordingReviewScheduler()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","d1h5","b8c6","f1c4","g8f6","h5f7"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                Issue.record("A rich multi-ply card must not invoke engine grading")
                return .centipawns(0)
            },
            scheduler: scheduler,
            replyDelay: { }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "e2e4")
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.submit(attemptedUCI: "d1h5")
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.submit(attemptedUCI: "f1c4")
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.submit(attemptedUCI: "h5f7")

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected learner checkmate to complete the exchange")
            return
        }
        #expect(feedback.outcome == .strong)
        #expect(viewModel.exchange?.stage == .completed(.checkmate))
        #expect(viewModel.exchange?.appliedUCI == [
            "e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"
        ])
        #expect(viewModel.exchange?.learnerOutcomes == [.strong, .strong, .strong, .strong])
        #expect(scheduler.outcomes == [.strong])
        #expect(viewModel.firstAttemptSuccesses == 1)
        #expect(try await store.trainingAttempts(cardId: card.id!).count == 1)
    }

    @Test
    func opponentCheckmateCompletesAfterShowingTheReply() async throws {
        let store = try GameStore()
        let scheduler = RecordingReviewScheduler()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "f2f3",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["f2f3","e7e5","g2g4","d8h4"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                Issue.record("A rich multi-ply card must not invoke engine grading")
                return .centipawns(0)
            },
            scheduler: scheduler,
            replyDelay: { }
        )

        await viewModel.load()
        #expect(viewModel.exchange?.legalPVPrefix == ["f2f3", "e7e5", "g2g4", "d8h4"])
        await viewModel.submit(attemptedUCI: "f2f3")
        guard case .replying(let firstReply) = viewModel.state else {
            Issue.record("Expected the first automatic reply")
            return
        }
        #expect(firstReply == "e5")
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.submit(attemptedUCI: "g2g4")
        guard case .replying(let mateReply) = viewModel.state else {
            Issue.record("Expected the checkmating automatic reply, state=\(String(describing: viewModel.state)), exchange=\(String(describing: viewModel.exchange))")
            return
        }
        #expect(mateReply == "Qh4#")
        try await Task.sleep(nanoseconds: 10_000_000)

        guard case .feedback(let feedback) = viewModel.state else {
            Issue.record("Expected opponent checkmate to complete after the reply")
            return
        }
        #expect(feedback.outcome == .strong)
        #expect(viewModel.exchange?.stage == .completed(.checkmate))
        #expect(viewModel.exchange?.appliedUCI == ["f2f3", "e7e5", "g2g4", "d8h4"])
        #expect(viewModel.exchange?.learnerOutcomes == [.strong, .strong])
        #expect(scheduler.outcomes == [.strong])
    }

    @Test
    func staleReplyCannotMutateTheNextCard() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5 2. Nf3 Nc6", white: "Alice", black: "Bob"))
        let firstCard = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","g1f3"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let secondCard = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 2,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: """
            [{"rank":1,"scoreCentipawns":40,"principalVariationUCI":["e2e4","e7e5","g1f3"],"depth":12}]
            """,
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [firstCard, secondCard] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) },
            replyDelay: {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "e2e4")
        #expect(viewModel.state == .replying("e5"))
        await viewModel.next()
        #expect(viewModel.currentIndex == 1)
        #expect(viewModel.state == .prompt)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(viewModel.currentCard?.id == secondCard.id)
        #expect(viewModel.exchange?.appliedUCI == [])
        #expect(viewModel.exchange?.stage == .awaitingLearner)
    }

    @Test
    func threatHintUsesOnlyTheStableMarkerAndLeavesLegacyCardsGeneric() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let marker = TrainingThemeMarker.ignoredThreat("Qxf7#")
        let markedCard = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[{\"rank\":1,\"scoreCentipawns\":40,\"principalVariationUCI\":[\"e2e4\"],\"depth\":12}]",
            classification: "mistake",
            themesJSON: try String(decoding: JSONEncoder().encode([marker, "Material left en prise"]), as: UTF8.self)
        ))
        let marked = PracticeSessionViewModel(
            store: store,
            loadCards: { [markedCard] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await marked.load()
        #expect(marked.themeHintTextIgnoringHintCount == "Material left en prise - left where the opponent can capture it for free")
        #expect(marked.threatHintTextIgnoringHintCount == "What is your opponent threatening? Qxf7#")
        marked.hint()
        #expect(marked.threatHintText == "What is your opponent threatening? Qxf7#")
        await marked.submit(attemptedUCI: "e2e4")
        await marked.next()
        guard case .completed(let summary) = marked.state else {
            Issue.record("Expected the marked card to complete")
            return
        }
        #expect(summary.recurringTheme == "Material left en prise")

        var legacyCard = markedCard
        legacyCard.themesJSON = "[]"
        let legacy = PracticeSessionViewModel(
            store: store,
            loadCards: { [legacyCard] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )
        await legacy.load()
        #expect(legacy.threatHintTextIgnoringHintCount == "Look for the forcing idea.")
    }

    @Test
    func malformedOrEmptyLegacyLineDoesNotCrashOrCreateAReply() async throws {
        let store = try GameStore()
        let game = try store.save(GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: "Alice", black: "Bob"))
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: game.id!,
            sourcePly: 1,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: "",
            rankedLinesJSON: "[{\"rank\":1,\"scoreCentipawns\":40,\"principalVariationUCI\":[],\"depth\":12}]",
            classification: "mistake"
        ))
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(0) }
        )

        await viewModel.load()
        #expect(viewModel.exchange?.legalPVPrefix.isEmpty == true)
        await viewModel.submit(attemptedUCI: "e2e4")
        #expect(viewModel.state != .replying(""))
        #expect(viewModel.linePreview == nil)
    }
}

private actor TrainingTimeoutState {
    private(set) var shouldTimeout = true

    func disable() {
        shouldTimeout = false
    }
}
