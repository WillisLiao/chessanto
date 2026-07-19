import Persistence
import Testing
@testable import Chessanto

@MainActor
struct GameReplayViewModelLinePreviewTests {
    private func makeViewModel() throws -> GameReplayViewModel {
        let store = try GameStore()
        let record = GameRecord(
            source: .pgnImport,
            pgn: """
            [Event "Preview test"]
            [White "Alice"]
            [Black "Bob"]
            [Result "1-0"]

            1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0
            """,
            white: "Alice",
            black: "Bob",
            result: "1-0"
        )
        return GameReplayViewModel(record: record, store: store)
    }

    @Test
    func continuationStartsWithTheMoveAfterTheSelectedPly() throws {
        let viewModel = try makeViewModel()

        #expect(
            viewModel.uciContinuation(fromPly: 2, maxPlies: 10)
                == ["g1f3", "b8c6", "f1b5", "a7a6"]
        )
    }

    @Test
    func continuationRespectsTheRequestedCap() throws {
        let viewModel = try makeViewModel()

        #expect(
            viewModel.uciContinuation(fromPly: 1, maxPlies: 2)
                == ["e7e5", "g1f3"]
        )
    }

    @Test
    func continuationAtTheFinalPlyIsEmpty() throws {
        let viewModel = try makeViewModel()

        #expect(viewModel.uciContinuation(fromPly: 6, maxPlies: 10).isEmpty)
    }

    @Test
    func continuationRejectsInvalidBounds() throws {
        let viewModel = try makeViewModel()

        #expect(viewModel.uciContinuation(fromPly: -1, maxPlies: 10).isEmpty)
        #expect(viewModel.uciContinuation(fromPly: 1, maxPlies: 0).isEmpty)
        #expect(viewModel.uciContinuation(fromPly: 99, maxPlies: 10).isEmpty)
    }
}
