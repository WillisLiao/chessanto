import AnalysisKit
import Foundation
import Persistence
import Testing
@testable import Chessanto

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
        var shouldTimeout = true
        let viewModel = PracticeSessionViewModel(
            store: store,
            loadCards: { [card] },
            evaluator: DefaultTrainingMoveEvaluator { _ in
                if shouldTimeout {
                    throw EngineSearchError.timedOut(milliseconds: 4400)
                }
                return .centipawns(40)
            }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "g1f3")
        #expect(viewModel.state == .prompt)

        shouldTimeout = false
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
    func feedbackAutomaticallyStartsTheFullBetterLine() async throws {
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
            evaluator: DefaultTrainingMoveEvaluator { _ in .centipawns(40) }
        )

        await viewModel.load()
        await viewModel.submit(attemptedUCI: "e2e4")

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
}
