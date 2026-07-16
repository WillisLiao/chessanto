import ChessKit

/// Facade over chesskit-swift so the rest of the app never imports
/// `ChessKit` directly. If the underlying library ever needs to be
/// swapped, only this package changes.
public struct ChessGame {
    public private(set) var game: Game

    public init(startingFEN fen: String? = nil) {
        if let fen, let position = Position(fen: fen) {
            self.game = Game(startingWith: position)
        } else {
            self.game = Game()
        }
    }

    public init(pgn: String) throws {
        self.game = try Game(pgn: pgn)
    }

    public var pgnString: String {
        game.pgn
    }

    public var tags: [String: String] {
        var result = [String: String]()
        for tag in game.tags.all where !tag.wrappedValue.isEmpty {
            result[tag.name] = tag.wrappedValue
        }
        for (key, value) in game.tags.other {
            result[key] = value
        }
        return result
    }
}

// MARK: - Move index navigation

public struct MoveIndex: Hashable, Sendable {
    let raw: MoveTree.Index

    public static let start = MoveIndex(raw: .minimum)
}

extension ChessGame {
    public var startIndex: MoveIndex {
        MoveIndex(raw: game.startingIndex)
    }

    /// All move indices in the mainline, in play order.
    public var mainlineIndices: [MoveIndex] {
        game.moves.indices
            .filter { $0.variation == MoveTree.Index.mainVariation }
            .sorted()
            .map(MoveIndex.init)
    }

    public func fen(at index: MoveIndex) -> String? {
        game.positions[index.raw]?.fen
    }

    public func san(at index: MoveIndex) -> String? {
        game.moves[index.raw]?.san
    }

    public func next(after index: MoveIndex) -> MoveIndex {
        MoveIndex(raw: index.raw.next)
    }

    public func previous(before index: MoveIndex) -> MoveIndex {
        MoveIndex(raw: index.raw.previous)
    }

    public func history(upTo index: MoveIndex) -> [MoveIndex] {
        game.moves.history(for: index.raw).map(MoveIndex.init)
    }
}

// MARK: - Legal moves and playing moves

public struct SquareCoordinate: Hashable, Sendable {
    public let notation: String

    public init(notation: String) {
        self.notation = notation
    }
}

extension ChessGame {
    /// Legal destination squares for the piece at `square` in the position at `index`.
    public func legalMoves(from square: SquareCoordinate, at index: MoveIndex) -> [SquareCoordinate] {
        guard let position = game.positions[index.raw] else { return [] }
        let board = Board(position: position)
        return board
            .legalMoves(forPieceAt: Square(square.notation))
            .map { SquareCoordinate(notation: $0.notation) }
    }

    /// Attempts to play a legal move from `start` to `end` at the position for `index`.
    /// Returns the new move index on success, or `nil` if the move is illegal.
    @discardableResult
    public mutating func playMove(
        from start: SquareCoordinate,
        to end: SquareCoordinate,
        at index: MoveIndex
    ) -> MoveIndex? {
        guard let position = game.positions[index.raw] else { return nil }
        var board = Board(position: position)
        let startSquare = Square(start.notation)
        let endSquare = Square(end.notation)
        guard board.canMove(pieceAt: startSquare, to: endSquare),
            let move = board.move(pieceAt: startSquare, to: endSquare)
        else {
            return nil
        }
        let newIndex = game.make(move: move, from: index.raw)
        return MoveIndex(raw: newIndex)
    }

    /// Attempts to play a legal SAN move (e.g. `"Nf3"`) at the position for `index`.
    @discardableResult
    public mutating func playMove(san: String, at index: MoveIndex) -> MoveIndex? {
        guard let position = game.positions[index.raw],
            let move = Move(san: san, position: position)
        else {
            return nil
        }
        let board = Board(position: position)
        guard board.canMove(pieceAt: move.start, to: move.end) else { return nil }
        let newIndex = game.make(move: move, from: index.raw)
        return MoveIndex(raw: newIndex)
    }
}
