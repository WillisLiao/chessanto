import Persistence
import Testing
@testable import Chessanto

@MainActor
struct GameReplayViewModelChatTests {
    @Test
    func pinnedChatSubjectDoesNotFollowBoardScrubbing() throws {
        let store = try GameStore()
        let record = GameRecord(
            source: .pgnImport,
            pgn: """
            [Event "Pin test"]
            [White "Alice"]
            [Black "Bob"]
            [Result "1-0"]

            1. e4 e5 2. Nf3 Nc6 1-0
            """,
            white: "Alice",
            black: "Bob",
            result: "1-0"
        )
        let viewModel = GameReplayViewModel(record: record, store: store)

        let pinnedIndex = viewModel.moveIndices[1]
        viewModel.jump(to: pinnedIndex)
        viewModel.pinChat(to: pinnedIndex)

        let pinnedFEN = viewModel.chatContext()?.currentFEN
        #expect(viewModel.isChatPinned)
        #expect(viewModel.chatSubjectGraphPly == 1)
        #expect(viewModel.chatPositionLabel == "Move 1. e4")
        #expect(viewModel.chatContext()?.mainlineMovesSAN == ["e4"])

        viewModel.jump(to: viewModel.moveIndices[4])

        #expect(viewModel.chatContext()?.currentFEN == pinnedFEN)
        #expect(viewModel.chatSubjectGraphPly == 1)
        #expect(viewModel.chatPositionLabel == "Move 1. e4")
        #expect(viewModel.chatContext()?.mainlineMovesSAN == ["e4"])

        viewModel.unpinChat()

        #expect(!viewModel.isChatPinned)
        #expect(viewModel.chatSubjectGraphPly == 4)
        #expect(viewModel.chatContext()?.currentFEN != pinnedFEN)
        #expect(viewModel.chatPositionLabel == "Move 2... Nc6")
        #expect(viewModel.chatContext()?.mainlineMovesSAN == ["e4", "e5", "Nf3", "Nc6"])
    }
}
