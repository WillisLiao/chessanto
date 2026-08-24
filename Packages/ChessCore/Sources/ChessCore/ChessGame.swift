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

public enum PieceKind: String, CaseIterable, Sendable, Codable {
    case pawn, knight, bishop, rook, queen, king
}

public enum PieceColor: String, CaseIterable, Sendable, Codable {
    case white, black

    public var opposite: PieceColor {
        self == .white ? .black : .white
    }
}

/// One structural absolute pin in a single position.
public struct AbsolutePin: Hashable, Sendable {
    public let pinningPieceKind: PieceKind
    public let pinningSquare: String
    public let pinnedPieceKind: PieceKind
    public let pinnedSquare: String
    public let pinnedColor: PieceColor
    public let kingSquare: String

    public init(
        pinningPieceKind: PieceKind,
        pinningSquare: String,
        pinnedPieceKind: PieceKind,
        pinnedSquare: String,
        pinnedColor: PieceColor,
        kingSquare: String
    ) {
        self.pinningPieceKind = pinningPieceKind
        self.pinningSquare = pinningSquare
        self.pinnedPieceKind = pinnedPieceKind
        self.pinnedSquare = pinnedSquare
        self.pinnedColor = pinnedColor
        self.kingSquare = kingSquare
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pinningPieceKind.rawValue)
        hasher.combine(pinningSquare)
        hasher.combine(pinnedPieceKind.rawValue)
        hasher.combine(pinnedSquare)
        hasher.combine(pinnedColor.rawValue)
        hasher.combine(kingSquare)
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
    /// Inventories structural absolute pins in a single position.
    ///
    /// Each candidate non-king piece is removed from a copied ChessKit
    /// position, then ChessKit's legal-move generator is asked which enemy
    /// rook, bishop, or queen can reach that piece's king. This deliberately
    /// keeps slider geometry and legality in ChessKit rather than duplicating
    /// ray traversal here.
    public static func absolutePins(in fen: String) -> [AbsolutePin] {
        guard let fields = strictFENFields(fen),
            fields[1] == "w" || fields[1] == "b",
            let halfmoveClock = Int(fields[4]), halfmoveClock >= 0,
            let fullmoveNumber = Int(fields[5]), fullmoveNumber > 0,
            let position = Position(fen: fen),
            let board = strictPieceBoard(fields[0]),
            board.whiteKings == 1,
            board.blackKings == 1
        else {
            return []
        }

        let kings = Dictionary(uniqueKeysWithValues: position.pieces.compactMap { piece -> (Piece.Color, Piece)? in
            guard piece.kind == .king else { return nil }
            return (piece.color, piece)
        })
        let originalBoard = Board(position: position)
        let sliders: Set<Piece.Kind> = [.rook, .bishop, .queen]
        var pins: [AbsolutePin] = []

        for candidate in position.pieces where candidate.kind != .king {
            guard let king = kings[candidate.color] else { return [] }
            guard let hypotheticalBoard = boardFieldRemovingPiece(
                from: fields[0], square: candidate.square.notation
            ) else { return [] }
            var hypotheticalFields = fields
            hypotheticalFields[0] = hypotheticalBoard
            guard let hypothetical = Position(fen: hypotheticalFields.joined(separator: " ")) else { return [] }
            let board = Board(position: hypothetical)

            for attacker in position.pieces where attacker.color != candidate.color && sliders.contains(attacker.kind) {
                guard originalBoard.legalMoves(forPieceAt: attacker.square).contains(candidate.square) else { continue }
                guard !originalBoard.legalMoves(forPieceAt: attacker.square).contains(king.square) else { continue }
                guard board.legalMoves(forPieceAt: attacker.square).contains(king.square) else { continue }
                pins.append(AbsolutePin(
                    pinningPieceKind: attacker.kind.asPieceKind,
                    pinningSquare: attacker.square.notation,
                    pinnedPieceKind: candidate.kind.asPieceKind,
                    pinnedSquare: candidate.square.notation,
                    pinnedColor: candidate.color.asPieceColor,
                    kingSquare: king.square.notation
                ))
            }
        }

        return pins.sorted {
            if $0.pinnedSquare != $1.pinnedSquare {
                return $0.pinnedSquare < $1.pinnedSquare
            }
            return $0.pinningSquare < $1.pinningSquare
        }
    }

    private struct StrictPieceBoard {
        let whiteKings: Int
        let blackKings: Int
    }

    private static func strictFENFields(_ fen: String) -> [String]? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6, validFENMetadata(fields) else { return nil }
        return fields
    }

    private static func validFENMetadata(_ fields: [String]) -> Bool {
        fields.count >= 4
            && validCastlingRights(fields[2])
            && validEnPassantField(fields[3])
    }

    private static func validCastlingRights(_ field: String) -> Bool {
        guard field != "-", !field.isEmpty else { return field == "-" }
        let order = Array("KQkq")
        var previous = -1
        for character in field {
            guard let index = order.firstIndex(of: character), index > previous else { return false }
            previous = index
        }
        return true
    }

    private static func validEnPassantField(_ field: String) -> Bool {
        if field == "-" { return true }
        let characters = Array(field)
        guard characters.count == 2,
            "abcdefgh".contains(characters[0]),
            characters[1] == "3" || characters[1] == "6"
        else {
            return false
        }
        return true
    }

    private static func strictPieceBoard(_ boardField: String) -> StrictPieceBoard? {
        let ranks = boardField.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }

        var whiteKings = 0
        var blackKings = 0
        for rank in ranks {
            var fileCount = 0
            for character in rank {
                if let emptySquares = character.wholeNumberValue,
                    (1...8).contains(emptySquares)
                {
                    fileCount += emptySquares
                    continue
                }

                guard "pnbrqkPNBRQK".contains(character) else { return nil }
                if character == "K" { whiteKings += 1 }
                if character == "k" { blackKings += 1 }
                fileCount += 1
            }
            guard fileCount == 8 else { return nil }
        }

        return StrictPieceBoard(whiteKings: whiteKings, blackKings: blackKings)
    }

    private static func boardFieldRemovingPiece(from boardField: String, square: String) -> String? {
        let ranks = boardField.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8,
            let file = "abcdefgh".firstIndex(of: square.first ?? "\0"),
            let rank = square.last?.wholeNumberValue,
            (1...8).contains(rank)
        else { return nil }

        var rows: [[Character?]] = []
        for rankString in ranks {
            var row: [Character?] = []
            for character in rankString {
                if let emptySquares = character.wholeNumberValue,
                    (1...8).contains(emptySquares)
                {
                    row.append(contentsOf: Array(repeating: nil, count: emptySquares))
                } else if "pnbrqkPNBRQK".contains(character) {
                    row.append(character)
                } else {
                    return nil
                }
            }
            guard row.count == 8 else { return nil }
            rows.append(row)
        }

        let fileIndex = "abcdefgh".distance(from: "abcdefgh".startIndex, to: file)
        let rowIndex = 8 - rank
        guard rows[rowIndex][fileIndex] != nil else { return nil }
        rows[rowIndex][fileIndex] = nil

        return rows.map { row in
            var result = ""
            var emptySquares = 0
            for square in row {
                if let piece = square {
                    if emptySquares > 0 {
                        result += String(emptySquares)
                        emptySquares = 0
                    }
                    result.append(piece)
                } else {
                    emptySquares += 1
                }
            }
            if emptySquares > 0 {
                result += String(emptySquares)
            }
            return result
        }.joined(separator: "/")
    }

    /// Enemy pieces currently reachable by the piece at `square` in `fen`.
    ///
    /// ChessKit's legal-move generator supplies the attack destinations, so
    /// this stays independent of the FEN's side-to-move field and does not
    /// duplicate chess movement geometry. Only occupied enemy destinations
    /// are returned, which excludes pawn pushes and empty squares.
    public static func attackedEnemySquares(from square: String, in fen: String) -> [(square: String, kind: PieceKind)] {
        guard let position = Position(fen: fen) else { return [] }
        let source = Square(square)
        guard source.notation == square, let piece = position.piece(at: source) else { return [] }

        let board = Board(position: position)
        return board
            .legalMoves(forPieceAt: source)
            .compactMap { destination in
                guard let target = position.piece(at: destination), target.color != piece.color else { return nil }
                return (square: destination.notation, kind: target.kind.asPieceKind)
            }
            .sorted { $0.square < $1.square }
    }

    /// Replays a line of UCI moves (e.g. an engine PV) from `fen`, stopping
    /// at the first move that fails to parse or play. Each returned move
    /// carries the exact board facts (SAN, check/mate flags, captures)
    /// produced by actually playing it, not by inspecting notation strings.
    ///
    /// - note: a pawn move onto the back rank must name its promotion piece
    /// (`"b7b8q"`, not `"b7b8"`). A bare square pair there is treated as
    /// unplayable and stops the replay, because the alternatives are both
    /// wrong: leaving the pawn on the back rank yields an illegal position,
    /// and assuming a queen invents a move the caller never named.
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
            } else if playedMove.piece.kind == .pawn,
                playedMove.end.rank.value == 1 || playedMove.end.rank.value == 8
            {
                break
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

    /// How many legal moves the side to move has in `fen`, counting each
    /// promotion of the same pawn to the same square once.
    ///
    /// A position with exactly one legal move gives its player no choice,
    /// so grading that move against the engine's preference measures
    /// nothing about the player. Returns 0 for an unparseable FEN, which
    /// callers should treat as "unknown", not as stalemate.
    public static func legalMoveCount(fen: String) -> Int {
        guard let position = Position(fen: fen) else { return 0 }
        let board = Board(position: position)
        let sideToMove: Piece.Color = fen.split(separator: " ").count > 1
            && fen.split(separator: " ")[1] == "b"
            ? .black : .white
        return position.pieces
            .filter { $0.color == sideToMove }
            .reduce(0) { total, piece in
                total + board.legalMoves(forPieceAt: piece.square).count
            }
    }

    /// Whether the side to move in `fen` has any legal move ending on
    /// `square` (given in algebraic notation, e.g. `"d2"`).
    ///
    /// Used to tell a free capture from an exchange: replay the capture,
    /// then ask whether the side that just lost the piece can take back on
    /// that square. If it cannot, the material is simply won.
    public static func hasLegalMove(fen: String, endingOn square: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        let board = Board(position: position)
        let sideToMove: Piece.Color = fen.split(separator: " ").count > 1
            && fen.split(separator: " ")[1] == "b"
            ? .black : .white
        let target = Square(square)
        return position.pieces
            .filter { $0.color == sideToMove }
            .contains { board.legalMoves(forPieceAt: $0.square).contains(target) }
    }

    /// Whether `fen` parses as a valid position - `ChessGame.init(startingFEN:)`
    /// silently falls back to the starting position on an invalid FEN, so
    /// callers that must distinguish "invalid" from "valid" (the coach's
    /// engine-tool argument validation) need this check first.
    public static func isValidFEN(_ fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard validFENMetadata(fields) else { return false }
        return Position(fen: fen) != nil
    }

    /// The first 4 space-separated fields of `fen` (board, side-to-move,
    /// castling rights, en-passant square) - the EPD used to key the opening
    /// book, since chesskit-generated FENs are internally consistent about
    /// omitting the en-passant square even when a capture is legal.
    public static func epd(fromFEN fen: String) -> String {
        fen.split(separator: " ", maxSplits: 4).prefix(4).joined(separator: " ")
    }
}
