import AnalysisKit
import ChessCore
import Foundation
import Persistence
import Testing
@testable import Chessanto

struct TrainingDomainTests {
    @Test
    func cachedTopLineIsAcceptedWithoutEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _, _ in
            await probe.markSearched()
            return TrainingEngineEvaluation(scoreCentipawnsWhitePerspective: 0, mateInWhitePerspective: nil)
        }

        let result = try await evaluator.evaluate(card: card(), attemptedUCI: "e2e4")

        #expect(result.outcome == .strong)
        #expect(result.lossCentipawns == 0)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func centipawnLossUsesMoverPerspectiveForBlack() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _, _ in
            TrainingEngineEvaluation(scoreCentipawnsWhitePerspective: 20, mateInWhitePerspective: nil)
        }
        let result = try await evaluator.evaluate(
            card: card(
                fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
                side: .black,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: -60, mateIn: nil, principalVariationUCI: ["b8c6"], depth: 12)
                ]
            ),
            attemptedUCI: "g8f6"
        )

        #expect(result.outcome == .playable)
        #expect(result.lossCentipawns == 80)
    }

    @Test
    func illegalMoveIsRejectedBeforeEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _, _ in
            await probe.markSearched()
            return TrainingEngineEvaluation(scoreCentipawnsWhitePerspective: 0, mateInWhitePerspective: nil)
        }

        let result = try await evaluator.evaluate(card: card(), attemptedUCI: "e2e5")

        #expect(result.outcome == .incorrect)
        #expect(result.attemptedMoveSAN == nil)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func mateScoresAreClassifiedWithoutFakeCentipawns() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _, _ in
            TrainingEngineEvaluation(scoreCentipawnsWhitePerspective: nil, mateInWhitePerspective: 3)
        }
        let result = try await evaluator.evaluate(
            card: card(
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 1, principalVariationUCI: ["e2e4"], depth: 12)
                ]
            ),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .playable)
        #expect(result.lossCentipawns == nil)
    }

    @Test
    func deterministicScheduleTransitionsToMasteredAfterThreeStrongRecalls() {
        let scheduler = DeterministicReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_000)
        var record = TrainingCardRecord(
            id: 10,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake",
            consecutiveSuccesses: 2,
            masteryState: "review"
        )

        record = scheduler.next(card: record, outcome: .strong, now: now)

        #expect(record.consecutiveSuccesses == 3)
        #expect(record.masteryState == "mastered")
        #expect(Calendar.current.dateComponents([.day], from: now, to: record.dueAt).day == 14)
    }

    @Test
    func playableResetsSuccessesAndIsDueTomorrow() {
        let scheduler = DeterministicReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_000)
        let record = TrainingCardRecord(
            id: 10,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake",
            consecutiveSuccesses: 2,
            masteryState: "review"
        )

        let updated = scheduler.next(card: record, outcome: .playable, now: now)

        #expect(updated.consecutiveSuccesses == 0)
        #expect(updated.masteryState == "learning")
        #expect(Calendar.current.dateComponents([.day], from: now, to: updated.dueAt).day == 1)
    }

    private func card(
        fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        side: ChessCore.PieceColor = .white,
        rankedLines: [RankedLine] = [
            RankedLine(rank: 1, scoreCentipawns: 40, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 12),
            RankedLine(rank: 2, scoreCentipawns: 32, mateIn: nil, principalVariationUCI: ["d2d4"], depth: 12)
        ]
    ) -> TrainingCard {
        TrainingCard(
            id: 1,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: fen,
            sideToMove: side,
            rankedLines: rankedLines,
            classification: .mistake,
            themes: [],
            explanation: "Better was e4.",
            dueAt: Date(),
            consecutiveSuccesses: 0,
            masteryState: .new,
            lastResult: nil
        )
    }
}

private actor SearchProbe {
    private var searched = false

    var wasSearched: Bool { searched }

    func markSearched() {
        searched = true
    }
}
