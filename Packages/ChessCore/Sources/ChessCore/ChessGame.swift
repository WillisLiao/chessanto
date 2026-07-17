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

    /// Every index in the tree (mainline and all variations), in no
    /// particular order.
    public var allIndices: [MoveIndex] {
        game.moves.indices.map(MoveIndex.init)
    }

    /// Whether `index` belongs to the mainline (variation 0).
    public func isMainline(_ index: MoveIndex) -> Bool {
        index.raw.variation == MoveTree.Index.mainVariation
    }

    /// The index immediately before `index` in whichever branch it belongs
    /// to, or `nil` if `index` is the start of the game.
    public func parent(of index: MoveIndex) -> MoveIndex? {
        let hist = history(upTo: index)
        guard hist.count >= 2 else { return nil }
        return hist[hist.count - 2]
    }

    /// Walks up from `index` to the nearest ancestor (including itself)
    /// that belongs to the mainline - "back to game" for a variation.
    public func mainlineAncestor(of index: MoveIndex) -> MoveIndex {
        var current = index
        while !isMainline(current), let parent = parent(of: current) {
            current = parent
        }
        return current
    }
}

// MARK: - Legal moves and playing moves

public struct SquareCoordinate: Hashable, Sendable {
    public let notation: String

    public init(notation: String) {
        self.notation = notation
    }
}

public enum PromotionKind: String, CaseIterable, Sendable {
    case queen, rook, bishop, knight

    var kind: Piece.Kind {
        switch self {
        case .queen: return .queen
        case .rook: return .rook
        case .bishop: return .bishop
        case .knight: return .knight
        }
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

    /// Whether the piece at `square` can legally reach the back rank and
    /// promote if moved to `end` - used by the board UI to decide whether
    /// to prompt for a promotion piece before calling `playMove`.
    public func isPromotion(from square: SquareCoordinate, to end: SquareCoordinate, at index: MoveIndex) -> Bool {
        guard let position = game.positions[index.raw] else { return false }
        let startSquare = Square(square.notation)
        guard let piece = position.piece(at: startSquare), piece.kind == .pawn else { return false }
        let endSquare = Square(end.notation)
        return endSquare.rank.value == 1 || endSquare.rank.value == 8
    }

    /// Attempts to play a legal move from `start` to `end` at the position for `index`.
    /// Pawn moves reaching the back rank auto-promote to `promotion` (default queen).
    /// Returns the new move index on success, or `nil` if the move is illegal.
    @discardableResult
    public mutating func playMove(
        from start: SquareCoordinate,
        to end: SquareCoordinate,
        at index: MoveIndex,
        promotion: PromotionKind = .queen
    ) -> MoveIndex? {
        guard let position = game.positions[index.raw] else { return nil }
        var board = Board(position: position)
        let startSquare = Square(start.notation)
        let endSquare = Square(end.notation)
        guard board.canMove(pieceAt: startSquare, to: endSquare),
            var move = board.move(pieceAt: startSquare, to: endSquare)
        else {
            return nil
        }
        if move.promotedPiece == nil, move.piece.kind == .pawn, endSquare.rank.value == 1 || endSquare.rank.value == 8 {
            move = board.completePromotion(of: move, to: promotion.kind)
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

// MARK: - Engine (UCI) bridging

extension ChessGame {
    /// The UCI/engine-LAN notation of the mainline move that produced the
    /// position at `index` (e.g. `"e2e4"`, `"e1g1"` for castling, `"e7e8q"`
    /// for a promotion), or `nil` if `index` has no move (the start index).
    public func uciMove(at index: MoveIndex) -> String? {
        game.moves[index.raw]?.lan
    }

    /// Converts a line of UCI moves (e.g. a PV from the engine) played from
    /// `fen` into their SAN representations, stopping at the first move that
    /// fails to parse or play.
    ///
    /// - note: `EngineLANParser` never sets check state, so the returned
    /// SANs never include `+`/`#`.
    public static func sanLine(fromUCI moves: [String], startingFEN fen: String) -> [String] {
        guard let position = Position(fen: fen) else { return [] }
        var board = Board(position: position)
        var color: Piece.Color = fen.split(separator: " ", maxSplits: 2).count > 1
            && fen.split(separator: " ", maxSplits: 2)[1] == "b"
            ? .black : .white

        var sans: [String] = []
        for uci in moves {
            guard let parsedMove = EngineLANParser.parse(move: uci, for: color, in: board.position) else {
                break
            }
            guard var playedMove = board.move(pieceAt: parsedMove.start, to: parsedMove.end) else {
                break
            }
            if let promotedPiece = parsedMove.promotedPiece {
                playedMove = board.completePromotion(of: playedMove, to: promotedPiece.kind)
            }
            sans.append(playedMove.san)
            color = color.opposite
        }
        return sans
    }
}
