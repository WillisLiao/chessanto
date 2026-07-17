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
    /// - note: the SAN comes from replaying each move on a live `Board`, so
    /// it does include `+`/`#` when the resulting position is a check/mate.
    public static func sanLine(fromUCI moves: [String], startingFEN fen: String) -> [String] {
        replayLine(fromUCI: moves, startingFEN: fen).map(\.san)
    }
}

// MARK: - Replay primitives

/// A single move replayed from a UCI/engine line or read from the mainline,
/// carrying only plain typed fields (never leaking `ChessKit` types) so
/// higher layers (coaching facts, templates) can depend on it without
/// importing `ChessKit`.
public struct ReplayedMove: Hashable, Sendable {
    public let san: String
    public let uci: String
    public let movedPieceKind: PieceKind
    public let movedPieceColor: PieceColor
    public let capturedPieceKind: PieceKind?
    public let isCheck: Bool
    public let isCheckmate: Bool
    public let endSquare: String
    public let resultingFEN: String
}

public enum PieceKind: String, CaseIterable, Sendable {
    case pawn, knight, bishop, rook, queen, king
}

public enum PieceColor: String, CaseIterable, Sendable {
    case white, black

    public var opposite: PieceColor {
        self == .white ? .black : .white
    }
}

extension Piece.Kind {
    fileprivate var asPieceKind: PieceKind {
        switch self {
        case .pawn: return .pawn
        case .knight: return .knight
        case .bishop: return .bishop
        case .rook: return .rook
        case .queen: return .queen
        case .king: return .king
        }
    }
}

extension Piece.Color {
    fileprivate var asPieceColor: PieceColor {
        self == .white ? .white : .black
    }
}

extension Move {
    fileprivate func asReplayedMove(resultingFEN: String) -> ReplayedMove {
        var capturedKind: PieceKind?
        if case .capture(let captured) = result {
            capturedKind = captured.kind.asPieceKind
        }
        return ReplayedMove(
            san: san,
            uci: lan,
            movedPieceKind: piece.kind.asPieceKind,
            movedPieceColor: piece.color.asPieceColor,
            capturedPieceKind: capturedKind,
            isCheck: checkState == .check,
            isCheckmate: checkState == .checkmate,
            endSquare: end.notation,
            resultingFEN: resultingFEN
        )
    }
}

extension ChessGame {
    /// Replays a line of UCI moves (e.g. an engine PV) from `fen`, stopping
    /// at the first move that fails to parse or play. Each returned move
    /// carries the exact board facts (SAN, check/mate flags, captures)
    /// produced by actually playing it, not by inspecting notation strings.
    public static func replayLine(fromUCI moves: [String], startingFEN fen: String) -> [ReplayedMove] {
        guard let position = Position(fen: fen) else { return [] }
        var board = Board(position: position)
        var color: Piece.Color = fen.split(separator: " ", maxSplits: 2).count > 1
            && fen.split(separator: " ", maxSplits: 2)[1] == "b"
            ? .black : .white

        var replayed: [ReplayedMove] = []
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
            replayed.append(playedMove.asReplayedMove(resultingFEN: board.position.fen))
            color = color.opposite
        }
        return replayed
    }

    /// The full replayed-move detail for a played mainline (or variation)
    /// move at `index`, or `nil` for the start index.
    public func moveDetail(at index: MoveIndex) -> ReplayedMove? {
        guard let move = game.moves[index.raw], let position = game.positions[index.raw] else {
            return nil
        }
        return move.asReplayedMove(resultingFEN: position.fen)
    }

    /// Total material value (pawn=1, knight/bishop=3, rook=5, queen=9; king
    /// excluded) for each side in the position described by `fen`.
    public static func material(fen: String) -> (white: Int, black: Int) {
        guard let position = Position(fen: fen) else { return (0, 0) }
        var white = 0
        var black = 0
        for piece in position.pieces {
            let value: Int
            switch piece.kind {
            case .pawn: value = 1
            case .knight, .bishop: value = 3
            case .rook: value = 5
            case .queen: value = 9
            case .king: value = 0
            }
            if piece.color == .white {
                white += value
            } else {
                black += value
            }
        }
        return (white, black)
    }

    /// The first 4 space-separated fields of `fen` (board, side-to-move,
    /// castling rights, en-passant square) - the EPD used to key the opening
    /// book, since chesskit-generated FENs are internally consistent about
    /// omitting the en-passant square even when a capture is legal.
    public static func epd(fromFEN fen: String) -> String {
        fen.split(separator: " ", maxSplits: 4).prefix(4).joined(separator: " ")
    }
}
