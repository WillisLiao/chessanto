import Foundation
import Testing
import ChessCore
import EngineKit
import Persistence
@testable import Chessanto

private final class ScriptedEngineOpponent: EngineOpponent, @unchecked Sendable {
    private var scriptedReplies: [String: String]
    private var moveSequence: [String]
    private(set) var requestedStrengths: [EngineStrength] = []

    init(repliesByFEN: [String: String] = [:], sequence: [String] = []) {
        self.scriptedReplies = repliesByFEN
        self.moveSequence = sequence
    }

    func generateMove(in fen: String, strength: EngineStrength) async throws -> String {
        requestedStrengths.append(strength)
        if !moveSequence.isEmpty {
            return moveSequence.removeFirst()
        }
        let boardFEN = fen.split(separator: " ").first.map(String.init) ?? fen
        if let reply = scriptedReplies[fen] ?? scriptedReplies[boardFEN] {
            return reply
        }
        throw EngineSearchError.noAnalysis
    }
}

@MainActor
@Suite struct PlayVsEngineViewModelTests {
    @Test func initialSetupDefaults() async throws {
        let viewModel = PlayVsEngineViewModel()
        #expect(viewModel.stage == .setup)
        #expect(viewModel.selectedSide == .white)
        #expect(viewModel.selectedStrength == .intermediate)
        #expect(!viewModel.isGameActive)
        #expect(!viewModel.isGameOver)
        #expect(viewModel.session == nil)
        #expect(viewModel.playedMovesSAN.isEmpty)
    }

    @Test func startGameAsWhiteEntersPlayingStageAndSetsBoardOrientation() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .casual)

        await viewModel.startGame(
            store: store,
            engineOpponent: opponent,
            fixedColor: ChessCore.PieceColor.white
        )

        #expect(viewModel.stage == .playing)
        #expect(viewModel.isGameActive)
        #expect(!viewModel.isFlipped)
        #expect(viewModel.isUserTurn)
        #expect(!viewModel.isEngineThinking)
        #expect(viewModel.userColor == ChessCore.PieceColor.white)
        #expect(viewModel.engineColor == ChessCore.PieceColor.black)

        let e2 = try #require(BoardSquare(algebraic: "e2"))
        await viewModel.handleSquareTapped(e2)
        #expect(viewModel.selectedSquare == e2)
        #expect(viewModel.legalDestinations.contains(BoardSquare(algebraic: "e4")!))

        let e4 = try #require(BoardSquare(algebraic: "e4"))
        await viewModel.handleSquareTapped(e4)

        #expect(viewModel.playedMovesSAN == ["e4", "e5"])
        #expect(viewModel.selectedSquare == nil)
        #expect(viewModel.lastMove?.from == BoardSquare(algebraic: "e7"))
        #expect(viewModel.lastMove?.to == BoardSquare(algebraic: "e5"))
    }

    @Test func startGameAsBlackFlipsBoardAndAllowsEngineFirstMove() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e2e4"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .black, selectedStrength: .intermediate)

        await viewModel.startGame(
            store: store,
            engineOpponent: opponent,
            fixedColor: ChessCore.PieceColor.black
        )

        #expect(viewModel.stage == .playing)
        #expect(viewModel.isFlipped)
        #expect(viewModel.userColor == ChessCore.PieceColor.black)
        #expect(viewModel.engineColor == ChessCore.PieceColor.white)
        #expect(viewModel.playedMovesSAN == ["e4"])
        #expect(viewModel.isUserTurn)
    }

    @Test func dragAndDropPlaysMove() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .casual)

        await viewModel.startGame(store: store, engineOpponent: opponent, fixedColor: ChessCore.PieceColor.white)

        let e2 = try #require(BoardSquare(algebraic: "e2"))
        let e4 = try #require(BoardSquare(algebraic: "e4"))

        viewModel.handleDragStarted(e2)
        #expect(viewModel.selectedSquare == e2)

        await viewModel.handleDrop(from: e2, to: e4)
        #expect(viewModel.playedMovesSAN == ["e4", "e5"])
    }

    @Test func resignationCompletesGameAndPersistsRecord() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .advanced)

        await viewModel.startGame(store: store, engineOpponent: opponent, fixedColor: ChessCore.PieceColor.white)
        let e2 = try #require(BoardSquare(algebraic: "e2"))
        let e4 = try #require(BoardSquare(algebraic: "e4"))
        await viewModel.handleDrop(from: e2, to: e4)

        viewModel.resign()

        #expect(viewModel.isGameOver)
        #expect(viewModel.stage == .completed(.resignation(resignedBy: ChessCore.PieceColor.white)))
        #expect(viewModel.persistedRecord != nil)
        #expect(viewModel.persistedRecord?.result == "0-1")

        let savedId = try #require(viewModel.persistedRecord?.id)
        let savedGame = try store.game(id: savedId)
        #expect(savedGame?.source == .vsEngine)
    }

    @Test func drawClaimWithoutRepetitionShowsAlert() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .casual)

        await viewModel.startGame(store: store, engineOpponent: opponent, fixedColor: ChessCore.PieceColor.white)
        #expect(!viewModel.canClaimDraw)

        viewModel.claimDraw()
        #expect(viewModel.isDrawClaimAlertPresented)
        #expect(viewModel.drawClaimAlertMessage != nil)
        #expect(!viewModel.isGameOver)
    }

    @Test func threefoldRepetitionCompletesGameAutomatically() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["g8f6", "f6g8", "g8f6", "f6g8"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .casual)

        await viewModel.startGame(store: store, engineOpponent: opponent, fixedColor: ChessCore.PieceColor.white)

        let g1 = try #require(BoardSquare(algebraic: "g1"))
        let f3 = try #require(BoardSquare(algebraic: "f3"))

        await viewModel.handleDrop(from: g1, to: f3)
        await viewModel.handleDrop(from: f3, to: g1)
        await viewModel.handleDrop(from: g1, to: f3)
        await viewModel.handleDrop(from: f3, to: g1)

        #expect(viewModel.isGameOver)
        #expect(viewModel.stage == .completed(.repetition))
        #expect(viewModel.outcome == .repetition)
        #expect(viewModel.persistedRecord?.result == "1/2-1/2")
    }

    @Test func checkmateCompletesGameAndAllowsReset() async throws {
        let store = try GameStore()
        // Scholar's mate: 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5", "b8c6", "g8f6"])
        let viewModel = PlayVsEngineViewModel(selectedSide: .white, selectedStrength: .master)

        await viewModel.startGame(store: store, engineOpponent: opponent, fixedColor: ChessCore.PieceColor.white)

        await viewModel.handleDrop(from: BoardSquare(algebraic: "e2")!, to: BoardSquare(algebraic: "e4")!)
        await viewModel.handleDrop(from: BoardSquare(algebraic: "d1")!, to: BoardSquare(algebraic: "h5")!)
        await viewModel.handleDrop(from: BoardSquare(algebraic: "f1")!, to: BoardSquare(algebraic: "c4")!)
        await viewModel.handleDrop(from: BoardSquare(algebraic: "h5")!, to: BoardSquare(algebraic: "f7")!)

        #expect(viewModel.isGameOver)
        #expect(viewModel.outcome == .checkmate(winner: .white))
        #expect(viewModel.persistedRecord != nil)
        #expect(viewModel.persistedRecord?.result == "1-0")

        viewModel.resetToSetup()
        #expect(viewModel.stage == .setup)
        #expect(viewModel.session == nil)
        #expect(viewModel.playedMovesSAN.isEmpty)
    }

    @Test func toggleFlipFlipsOrientation() async throws {
        let viewModel = PlayVsEngineViewModel()
        #expect(!viewModel.isFlipped)
        viewModel.toggleFlip()
        #expect(viewModel.isFlipped)
        viewModel.toggleFlip()
        #expect(!viewModel.isFlipped)
    }
}
