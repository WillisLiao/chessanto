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
@Suite struct LiveGameSessionTests {
    @Test func userAsWhiteBasicTurnCycle() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .casual,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        #expect(session.status == .userTurn)
        #expect(session.userColor == .white)
        #expect(session.engineColor == .black)
        #expect(session.playedMovesSAN.isEmpty)

        let movePlayed = await session.playUserMove(uci: "e2e4")
        #expect(movePlayed)
        #expect(session.status == .userTurn)
        #expect(session.playedMovesSAN == ["e4", "e5"])
        #expect(session.playedMovesUCI == ["e2e4", "e7e5"])
        #expect(session.moveCount == 2)
        #expect(opponent.requestedStrengths.count == 1)
        #expect(opponent.requestedStrengths.first?.skillLevel == 4)
    }

    @Test func userAsBlackEnginePlaysFirstMoveOnStart() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e2e4"])
        let session = LiveGameSession(
            userSideSelection: .black,
            engineStrength: .intermediate,
            engineOpponent: opponent,
            store: store,
            fixedColor: .black
        )

        await session.start()
        #expect(session.status == .userTurn)
        #expect(session.userColor == .black)
        #expect(session.engineColor == .white)
        #expect(session.playedMovesSAN == ["e4"])
        #expect(session.playedMovesUCI == ["e2e4"])
        #expect(session.moveCount == 1)

        let replyPlayed = await session.playUserMove(uci: "e7e5")
        #expect(replyPlayed)
        #expect(session.playedMovesSAN == ["e4", "e5"])
    }

    @Test func userCheckmatesEngineCompletesAndPersistsGame() async throws {
        let store = try GameStore()
        // Scholar's mate sequence: 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5", "b8c6", "g8f6"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .advanced,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        await session.playUserMove(uci: "e2e4")
        await session.playUserMove(uci: "d1h5")
        await session.playUserMove(uci: "f1c4")
        let winningMove = await session.playUserMove(uci: "h5f7")

        #expect(winningMove)
        #expect(session.isGameOver)
        #expect(session.outcome == .checkmate(winner: .white))
        #expect(session.persistedRecord != nil)
        #expect(session.persistedRecord?.source == .vsEngine)
        #expect(session.persistedRecord?.result == "1-0")
        #expect(session.persistedRecord?.white == "Player")
        #expect(session.persistedRecord?.black == "Stockfish (Advanced)")

        let savedId = try #require(session.persistedRecord?.id)
        let loaded = try store.game(id: savedId)
        #expect(loaded?.source == .vsEngine)
        #expect(loaded?.result == "1-0")
        #expect(loaded?.pgn.contains("Qxf7#") == true)
    }

    @Test func engineCheckmatesUserCompletesAndPersistsGame() async throws {
        let store = try GameStore()
        // Fool's mate sequence: 1. f3 e5 2. g4 Qh4#
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5", "d8h4"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .beginner,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        await session.playUserMove(uci: "f2f3")
        await session.playUserMove(uci: "g2g4")

        #expect(session.isGameOver)
        #expect(session.outcome == .checkmate(winner: .black))
        #expect(session.persistedRecord != nil)
        #expect(session.persistedRecord?.result == "0-1")
    }

    @Test func userResignationCompletesAndPersistsGame() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .master,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        await session.playUserMove(uci: "e2e4")
        session.resign()

        #expect(session.isGameOver)
        #expect(session.outcome == .resignation(resignedBy: .white))
        #expect(session.persistedRecord != nil)
        #expect(session.persistedRecord?.result == "0-1")
        #expect(session.persistedRecord?.pgn.contains("Black won by resignation") == true)
    }

    @Test func threefoldRepetitionEndsGameInDraw() async throws {
        let store = try GameStore()
        // 1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8 (position repeated 3 times)
        let opponent = ScriptedEngineOpponent(sequence: ["g8f6", "f6g8", "g8f6", "f6g8"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .casual,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        await session.playUserMove(uci: "g1f3")
        await session.playUserMove(uci: "f3g1")
        await session.playUserMove(uci: "g1f3")
        await session.playUserMove(uci: "f3g1")

        #expect(session.isGameOver)
        #expect(session.outcome == .repetition)
        #expect(session.persistedRecord?.result == "1/2-1/2")
    }

    @Test func illegalUserMoveIsRejectedWithoutAdvancingState() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent()
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .casual,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        let illegalPlayed = await session.playUserMove(uci: "e2e5")
        #expect(!illegalPlayed)
        #expect(session.status == .userTurn)
        #expect(session.playedMovesSAN.isEmpty)
    }

    @Test func persistedGameReplaysInGameReplayViewModel() async throws {
        let store = try GameStore()
        let opponent = ScriptedEngineOpponent(sequence: ["e7e5", "b8c6", "g8f6"])
        let session = LiveGameSession(
            userSideSelection: .white,
            engineStrength: .master,
            engineOpponent: opponent,
            store: store,
            fixedColor: .white
        )

        await session.start()
        await session.playUserMove(uci: "e2e4")
        await session.playUserMove(uci: "d1h5")
        await session.playUserMove(uci: "f1c4")
        await session.playUserMove(uci: "h5f7")

        let record = try #require(session.persistedRecord)
        let replayViewModel = GameReplayViewModel(record: record, store: store)
        #expect(replayViewModel.loadError == nil)
        #expect(replayViewModel.moveIndices.count == 8) // Start position + 7 halfmoves
        #expect(replayViewModel.fens.count == 8)
        replayViewModel.jump(to: replayViewModel.moveIndices.last!)
        #expect(replayViewModel.sanAtCurrent == "Qxf7#")
    }
}
