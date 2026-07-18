import ChessCore
import Persistence
import Testing
@testable import Chessanto

@MainActor
struct GameReplayViewModelTrainingTests {
    @Test
    func analyzedReportBecomesReadyWithItsExactLearnerOwnedPreMovePosition() async throws {
        let store = try GameStore()
        let pgn = "1. f3 f6 *"
        let record = try #require(
            try store.save(
                GameRecord(
                    source: .pgnImport,
                    pgn: pgn,
                    white: "Learner",
                    black: "Opponent"
                )
            ).id
        )
        var profile = try store.userProfile()
        profile.chessComUsername = "learner"
        try store.saveUserProfile(profile)

        let game = try ChessGame(pgn: pgn)
        let indices = [game.startIndex] + game.mainlineIndices
        let fens = try indices.map { index in
            try #require(game.fen(at: index))
        }
        let lines = ["e2e4", "e7e5", "d2d4"]
        let scores = [0, -500, 500]
        for ply in fens.indices {
            try await store.saveAnalysis(
                [
                    AnalysisRecord(
                        gameId: record,
                        plyIndex: ply,
                        fen: fens[ply],
                        depth: 16,
                        scoreCentipawns: scores[ply],
                        principalVariation: lines[ply],
                        multiPVRank: 1
                    )
                ],
                gameId: record,
                plyIndex: ply
            )
        }
        let saved = try #require(try store.allGames().first)

        let viewModel = GameReplayViewModel(record: saved, store: store)

        #expect(viewModel.isTrainingReady == false)
        try await waitUntil {
            viewModel.isTrainingReady
        }

        #expect(viewModel.trainingCardCount == 1)
        #expect(viewModel.trainingCardSourcePlies == [1])
        #expect(viewModel.trainingCardError == nil)

        let cards = try await viewModel.trainingCards()
        #expect(cards.map { $0.sourcePly } == [1])
        #expect(cards.first?.preMoveFEN == fens[0])
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw TrainingViewModelTestError.timedOut
        }
        await Task.yield()
    }
}

private enum TrainingViewModelTestError: Error {
    case timedOut
}
