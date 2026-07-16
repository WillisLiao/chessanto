import Foundation
import ChessCore
import Persistence

@MainActor
final class GameReplayViewModel: ObservableObject {
    @Published private(set) var position: BoardPosition = .empty
    @Published private(set) var moveIndices: [MoveIndex] = []
    @Published private(set) var currentIndex: MoveIndex
    @Published var loadError: String?

    private var chessGame: ChessGame?

    init(record: GameRecord) {
        do {
            let game = try ChessGame(pgn: record.pgn)
            self.chessGame = game
            self.currentIndex = game.startIndex
            self.moveIndices = [game.startIndex] + game.mainlineIndices
            refreshPosition()
        } catch {
            self.currentIndex = .start
            self.loadError = "Couldn't parse this game's PGN: \(error.localizedDescription)"
        }
    }

    var sanAtCurrent: String? {
        chessGame?.san(at: currentIndex)
    }

    func san(at index: MoveIndex) -> String? {
        chessGame?.san(at: index)
    }

    func jump(to index: MoveIndex) {
        currentIndex = index
        refreshPosition()
    }

    func stepForward() {
        guard let chessGame else { return }
        let next = chessGame.next(after: currentIndex)
        guard moveIndices.contains(next) else { return }
        jump(to: next)
    }

    func stepBackward() {
        guard let chessGame else { return }
        let previous = chessGame.previous(before: currentIndex)
        jump(to: previous)
    }

    var canStepForward: Bool {
        guard let chessGame else { return false }
        return moveIndices.contains(chessGame.next(after: currentIndex))
    }

    var canStepBackward: Bool {
        currentIndex != chessGame?.startIndex
    }

    private func refreshPosition() {
        guard let chessGame, let fen = chessGame.fen(at: currentIndex) else {
            position = .empty
            return
        }
        position = BoardPositionMapper.position(fromFEN: fen) ?? .empty
    }
}
