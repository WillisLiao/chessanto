import AnalysisKit
import ChessCore
import Persistence
import Testing
@testable import Chessanto

/// P4.1: `GameReplayViewModel.buildReport()` resolves the user's saved
/// `ratingBand` into a real `RatingRegister` and threads it into the built
/// `GameReport`, instead of always defaulting to `.advanced`.
@MainActor
struct GameReplayViewModelRegisterTests {
    private func analyzedViewModel(pgn: String, ratingBand: String) async throws -> GameReplayViewModel {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.ratingBand = ratingBand
        try store.saveUserProfile(profile)

        let record = try #require(
            try store.save(GameRecord(source: .pgnImport, pgn: pgn, white: "White", black: "Black")).id
        )
        let game = try ChessGame(pgn: pgn)
        let indices = [game.startIndex] + game.mainlineIndices
        let fens = try indices.map { index in try #require(game.fen(at: index)) }
        for ply in fens.indices {
            try await store.saveAnalysis(
                [
                    AnalysisRecord(
                        gameId: record,
                        plyIndex: ply,
                        fen: fens[ply],
                        depth: 16,
                        scoreCentipawns: 0,
                        principalVariation: "e2e4",
                        multiPVRank: 1
                    )
                ],
                gameId: record,
                plyIndex: ply
            )
        }
        let saved = try #require(try store.allGames().first)
        let viewModel = GameReplayViewModel(record: saved, store: store)
        try await waitUntilReportIsBuilt(viewModel)
        return viewModel
    }

    @Test func beginnerRatingBandProducesABeginnerRegisterReport() async throws {
        let viewModel = try await analyzedViewModel(pgn: "1. e4 e5 2. Nf3 Nc6", ratingBand: "beginner")
        #expect(viewModel.report?.register == .beginner)
    }

    @Test func advancedRatingBandProducesAnAdvancedRegisterReport() async throws {
        let viewModel = try await analyzedViewModel(pgn: "1. e4 e5 2. Nf3 Nc6", ratingBand: "advanced")
        #expect(viewModel.report?.register == .advanced)
    }
}

@MainActor
private func waitUntilReportIsBuilt(
    _ viewModel: GameReplayViewModel,
    timeout: Duration = .seconds(2)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while viewModel.report == nil {
        guard clock.now < deadline else {
            throw RegisterTestError.timedOut
        }
        await Task.yield()
    }
}

private enum RegisterTestError: Error {
    case timedOut
}
