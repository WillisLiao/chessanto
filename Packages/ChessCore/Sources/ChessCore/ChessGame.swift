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
        guard fields.count == 6, validFENMetadata(fields), validFENCounters(fields) else { return nil }
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

    private static func validFENCounters(_ fields: [String]) -> Bool {
        guard fields.count >= 6 else { return true }
        return validUnsignedDecimal(fields[4]) && validUnsignedDecimal(fields[5])
    }

    private static func validUnsignedDecimal(_ field: String) -> Bool {
        !field.isEmpty && field.allSatisfy { "0123456789".contains($0) }
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
        guard validFENMetadata(fields), validFENCounters(fields) else { return false }
        return Position(fen: fen) != nil
    }

    /// The first 4 space-separated fields of `fen` (board, side-to-move,
    /// castling rights, en-passant square) - the EPD used to key the opening
    /// book, since chesskit-generated FENs are internally consistent about
    /// omitting the en-passant square even when a capture is legal.
    public static func epd(fromFEN fen: String) -> String {
        fen.split(separator: " ", maxSplits: 4).prefix(4).joined(separator: " ")
    }

    /// One structural skewer in a single position.
    /// A skewer is the inverse of a pin: a slider attacks a more valuable
    /// piece in front of a less valuable piece on the same line. When the
    /// valuable piece moves, the piece behind is exposed.
    public struct Skewer: Hashable, Sendable {
        public let attackingPieceKind: PieceKind
        public let attackingSquare: String
        public let frontPieceKind: PieceKind
        public let frontSquare: String
        public let backPieceKind: PieceKind
        public let backSquare: String
        public let frontColor: PieceColor

        public init(
            attackingPieceKind: PieceKind,
            attackingSquare: String,
            frontPieceKind: PieceKind,
            frontSquare: String,
            backPieceKind: PieceKind,
            backSquare: String,
            frontColor: PieceColor
        ) {
            self.attackingPieceKind = attackingPieceKind
            self.attackingSquare = attackingSquare
            self.frontPieceKind = frontPieceKind
            self.frontSquare = frontSquare
            self.backPieceKind = backPieceKind
            self.backSquare = backSquare
            self.frontColor = frontColor
        }
    }

    /// Inventories structural skewers in a single position.
    /// A skewer exists when a slider (R/B/Q) attacks a more valuable piece
    /// that, if it moves, exposes a less valuable piece behind it on the same
    /// ray. The king is the most valuable piece; queen next; then rook; then
    /// minor pieces. Pawns are never skewer targets.
    /// Uses ChessKit's legal-move generator, keeping geometry in ChessKit.
    public static func skewers(in fen: String) -> [Skewer] {
        guard let position = Position(fen: fen) else { return [] }
        let board = Board(position: position)
        let sliders: Set<Piece.Kind> = [.rook, .bishop, .queen]

        func pieceValue(_ kind: PieceKind) -> Int {
            switch kind {
            case .pawn: return 1
            case .knight, .bishop: return 3
            case .rook: return 5
            case .queen: return 9
            case .king: return 100
            }
        }

        var result: [Skewer] = []
        for attacker in position.pieces where sliders.contains(attacker.kind) {
            let attackedSquares = board.legalMoves(forPieceAt: attacker.square)
                .map { $0.notation }
                .sorted()
            guard attackedSquares.count >= 2 else { continue }

            for i in 0..<(attackedSquares.count - 1) {
                let frontSquare = attackedSquares[i]
                guard let frontPiece = position.piece(at: Square(frontSquare)),
                    frontPiece.color != attacker.color,
                    frontPiece.kind != .pawn
                else { continue }

                for j in (i + 1)..<attackedSquares.count {
                    let backSquare = attackedSquares[j]
                    guard let backPiece = position.piece(at: Square(backSquare)),
                        backPiece.color != attacker.color,
                        backPiece.kind != .pawn
                    else { continue }

                    let frontValue = pieceValue(frontPiece.kind.asPieceKind)
                    let backValue = pieceValue(backPiece.kind.asPieceKind)
                    guard frontValue > backValue else { continue }

                    if isCollinear(from: attacker.square.notation, through: frontSquare, to: backSquare) {
                        result.append(Skewer(
                            attackingPieceKind: attacker.kind.asPieceKind,
                            attackingSquare: attacker.square.notation,
                            frontPieceKind: frontPiece.kind.asPieceKind,
                            frontSquare: frontSquare,
                            backPieceKind: backPiece.kind.asPieceKind,
                            backSquare: backSquare,
                            frontColor: frontPiece.color.asPieceColor
                        ))
                    }
                }
            }
        }
        return result.sorted { $0.attackingSquare < $1.attackingSquare }
    }

    /// True when three squares lie on a single straight line (rank, file, or
    /// diagonal), with the first square on the outside and the other two in
    /// order along the same ray.
    private static func isCollinear(from a: String, through b: String, to c: String) -> Bool {
        guard let aFile = a.first, let aRank = a.last,
            let bFile = b.first, let bRank = b.last,
            let cFile = c.first, let cRank = c.last
        else { return false }
        let aF = fileIndex(aFile), bF = fileIndex(bFile), cF = fileIndex(cFile)
        guard let aR = Int(String(aRank)), let bR = Int(String(bRank)), let cR = Int(String(cRank)) else {
            return false
        }
        let df1 = bF - aF, dr1 = bR - aR
        let df2 = cF - aF, dr2 = cR - aR
        // Must be on the same ray from a
        guard (df1 == 0 && df2 == 0) || (dr1 == 0 && dr2 == 0) || (abs(df1) == abs(dr1) && abs(df2) == abs(dr2)) else {
            return false
        }
        // b must be between a and c (shorter distance to a)
        let distAB = df1 * df1 + dr1 * dr1
        let distAC = df2 * df2 + dr2 * dr2
        return distAB < distAC
    }

    private static func fileIndex(_ c: Character) -> Int {
        Int(c.asciiValue ?? 0) - Int(Character("a").asciiValue ?? 0)
    }

    /// Whether the king of `color` is on the back rank (rank 1 for White,
    /// rank 8 for Black) with no flight squares available - the classic
    /// back-rank weakness that makes a back-rank mate possible.
    public static func hasBackRankWeakness(fen: String, for color: PieceColor) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        guard let king = position.pieces.first(where: { $0.kind == .king && $0.color.asPieceColor == color }) else {
            return false
        }
        let backRank = color == .white ? 1 : 8
        guard king.square.rank.value == backRank else { return false }

        let board = Board(position: position)
        let escapeMoves = board.legalMoves(forPieceAt: king.square)
            .map { $0.notation }
        let allOnBackRank = escapeMoves.allSatisfy { move in
            move.last == Character(String(backRank))
        }
        guard allOnBackRank || escapeMoves.isEmpty else { return false }

        let kingFileNum = king.square.file.number
        let forwardRank = color == .white ? backRank + 1 : backRank - 1
        let pawnShieldSquares: [Int] = [kingFileNum - 1, kingFileNum, kingFileNum + 1]
        var hasPawnShield = false
        for fileNum in pawnShieldSquares where (1...8).contains(fileNum) {
            let fileChar = fileToChar(fileNum)
            let squareStr = "\(fileChar)\(forwardRank)"
            if let p = position.piece(at: Square(squareStr)),
                p.kind == .pawn && p.color.asPieceColor == color {
                hasPawnShield = true
            }
        }
        return hasPawnShield || escapeMoves.isEmpty
    }

    private static func fileToChar(_ index: Int) -> Character {
        let a = Int(Character("a").asciiValue ?? 97)
        return Character(UnicodeScalar(a + index - 1) ?? UnicodeScalar(97))
    }

    /// A piece is trapped when it has very few legal moves and most of them
    /// are to attacked squares where the piece would be lost. Returns the
    /// squares of pieces (excluding pawns and kings) that have no safe move
    /// (a move to a square not attacked by any enemy piece).
    public static func trappedPieces(in fen: String) -> [(square: String, kind: PieceKind)] {
        guard let position = Position(fen: fen) else { return [] }
        let board = Board(position: position)
        let sideToMove: Piece.Color = fen.split(separator: " ").count > 1
            && fen.split(separator: " ")[1] == "b"
            ? .black : .white
        let sideToMoveExternal: PieceColor = sideToMove.asPieceColor

        var result: [(String, PieceKind)] = []
        for piece in position.pieces where piece.color == sideToMove
            && piece.kind != .pawn && piece.kind != .king
        {
            let moves = board.legalMoves(forPieceAt: piece.square)
            guard !moves.isEmpty else { continue }

            let hasSafeMove = moves.contains { destination in
                let destSquare = destination.notation
                guard let target = position.piece(at: destination) else {
                    return !isSquareAttacked(square: destSquare, by: sideToMoveExternal.opposite, in: fen)
                }
                return target.color != sideToMove
                    && !isSquareAttacked(square: destSquare, by: sideToMoveExternal.opposite, in: fen)
            }
            if !hasSafeMove {
                result.append((piece.square.notation, piece.kind.asPieceKind))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    /// Whether `square` is attacked by any piece of `color` in the position
    /// described by `fen`. Uses ChessKit's legal-move generator.
    public static func isSquareAttacked(square: String, by color: PieceColor, in fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        let board = Board(position: position)
        let target = Square(square)
        return position.pieces
            .filter { $0.color.asPieceColor == color }
            .contains { board.legalMoves(forPieceAt: $0.square).contains(target) }
    }

    /// Parses `[%clk 1:23:45]` clock annotations from PGN comments and
    /// returns the clock time in seconds for each move. Returns nil for
    /// comments without a clock annotation.
    /// Format: `[%clk HH:MM:SS]` or `[%clk MM:SS]`.
    public static func parseClockAnnotation(_ comment: String) -> Int? {
        // Find [%clk ...] in the comment
        guard let clkRange = comment.range(of: "\\[%clk\\s+([^\\]]+)\\]", options: .regularExpression) else {
            return nil
        }
        let clkContent = String(comment[clkRange])
        // Extract the time string
        guard let timeRange = clkContent.range(of: "\\d{1,2}:\\d{2}(?::\\d{2})?", options: .regularExpression) else {
            return nil
        }
        let timeStr = String(clkContent[timeRange])
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}
