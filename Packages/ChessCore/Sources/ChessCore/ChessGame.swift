import ChessKit
import Foundation

/// Facade over chesskit-swift so the rest of the app never imports
/// `ChessKit` directly. If the underlying library ever needs to be
/// swapped, only this package changes.
public struct ChessGame {
    public private(set) var game: Game
    private var customFENs: [MoveTree.Index: String] = [:]

    public init(startingFEN fen: String? = nil) {
        if let fen, let position = Position(fen: fen) {
            var tags = Game.Tags()
            if Chess960.isChess960(startingFEN: fen) {
                tags.setUp = "1"
                tags.fen = fen
                tags.other["Variant"] = "Chess960"
            }
            self.game = Game(startingWith: position, tags: tags)
            self.customFENs[self.game.startingIndex] = fen
        } else {
            self.game = Game()
        }
    }

    public init(chess960Index index: Int) {
        let fen = Chess960.startingFEN(index: index)
        self.init(startingFEN: fen)
    }

    public init(pgn: String) throws {
        let normalized = PGNCompatibility.normalize(pgn: pgn)
        // Variant/custom-start games and games containing disambiguated piece
        // moves must not go through upstream at all: upstream cannot express
        // variant geometry, and it can silently misparse disambiguation
        // (moving the wrong piece) without throwing, which the fallback would
        // never see.
        let needsCompatParser = pgn.contains("Variant") || pgn.contains("variant")
            || pgn.contains("SetUp \"1\"") || pgn.contains("Setup \"1\"")
            || PGNCompatibility.requiresFallback(for: pgn)
        if needsCompatParser {
            let parsed = try PGNCompatibility.parse(pgn: pgn)
            self.game = parsed.game
            self.customFENs = parsed.fens
        } else if let game = try? Game(pgn: normalized) {
            self.game = game
        } else {
            let parsed = try PGNCompatibility.parse(pgn: pgn)
            self.game = parsed.game
            self.customFENs = parsed.fens
        }
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
        customFENs[index.raw] ?? game.positions[index.raw]?.fen
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
        let startSquare = Square(square.notation)
        var moves = board
            .legalMoves(forPieceAt: startSquare)
            .map { SquareCoordinate(notation: $0.notation) }

        // If king, check Chess960 castling legality
        if let piece = position.piece(at: startSquare), piece.kind == .king, piece.color == position.sideToMove {
            let fenStr = fen(at: index) ?? position.fen
            let color = piece.color.asPieceColor
            let rank = (color == .white) ? 1 : 8
            if Chess960.canCastle(color: color, side: .kingside, in: fenStr) {
                let dest = SquareCoordinate(notation: "g\(rank)")
                if !moves.contains(dest) { moves.append(dest) }
                if let (r1, r8) = Chess960.backRanks(from: fenStr.split(separator: " ")[0].description) {
                    let rights = Chess960.CastlingRights.parse(from: fenStr.split(separator: " ")[2].description, rank1: r1, rank8: r8)
                    let rf = (color == .white) ? rights.whiteKingsideRookFile : rights.blackKingsideRookFile
                    if let rf {
                        let rookSq = SquareCoordinate(notation: Chess960.fileToSquare(rf, rank: rank))
                        if !moves.contains(rookSq) { moves.append(rookSq) }
                    }
                }
            }
            if Chess960.canCastle(color: color, side: .queenside, in: fenStr) {
                let dest = SquareCoordinate(notation: "c\(rank)")
                if !moves.contains(dest) { moves.append(dest) }
                if let (r1, r8) = Chess960.backRanks(from: fenStr.split(separator: " ")[0].description) {
                    let rights = Chess960.CastlingRights.parse(from: fenStr.split(separator: " ")[2].description, rank1: r1, rank8: r8)
                    let rf = (color == .white) ? rights.whiteQueensideRookFile : rights.blackQueensideRookFile
                    if let rf {
                        let rookSq = SquareCoordinate(notation: Chess960.fileToSquare(rf, rank: rank))
                        if !moves.contains(rookSq) { moves.append(rookSq) }
                    }
                }
            }
        }

        return moves
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
        let startSquare = Square(start.notation)
        let endSquare = Square(end.notation)
        let previousFEN = fen(at: index) ?? position.fen

        // Chess960 castling fallback below only fires when the native board
        // path cannot play the move (king/rooks off their standard squares).
        // Castle only on unambiguous intent: king onto its own rook, or a
        // multi-file king jump to the g/c file. A single-file step to the
        // g/c file stays a plain king move (Lichess convention).
        var board = Board(position: position)
        let nativelyPlayable = board.canMove(pieceAt: startSquare, to: endSquare)

        if !nativelyPlayable,
            let piece = position.piece(at: startSquare), piece.kind == .king, piece.color == position.sideToMove
        {
            let color = piece.color.asPieceColor
            let rank = (color == .white) ? 1 : 8
            let fileDelta = abs(endSquare.file.number - startSquare.file.number)
            let isKingsideAttempt = (end.notation == "g\(rank)" && fileDelta >= 2) || Self.isKingsideRook(endSquare, color: color, in: previousFEN)
            let isQueensideAttempt = (end.notation == "c\(rank)" && fileDelta >= 2) || Self.isQueensideRook(endSquare, color: color, in: previousFEN)
            let side: Chess960.CastlingSide? = {
                if isKingsideAttempt { return .kingside }
                if isQueensideAttempt { return .queenside }
                return nil
            }()

            if let side, let castled = Chess960.performCastle(color: color, side: side, in: previousFEN) {
                let kingEnd = Square(side == .kingside ? "g\(rank)" : "c\(rank)")
                let move = Move(result: .move, piece: piece, start: startSquare, end: kingEnd)
                let newIndex = game.make(move: move, from: index.raw)
                customFENs[newIndex] = castled.resultingFEN
                return MoveIndex(raw: newIndex)
            }
        }

        guard board.canMove(pieceAt: startSquare, to: endSquare),
            var move = board.move(pieceAt: startSquare, to: endSquare)
        else {
            return nil
        }
        if move.promotedPiece == nil, move.piece.kind == .pawn, endSquare.rank.value == 1 || endSquare.rank.value == 8 {
            move = board.completePromotion(of: move, to: promotion.kind)
        }
        let newIndex = game.make(move: move, from: index.raw)
        customFENs[newIndex] = Self.carryingCastlingRights(
            previousFEN: previousFEN,
            resultingFEN: board.position.fen,
            movingFrom: start.notation,
            movingTo: end.notation,
            movedPieceKind: move.piece.kind.asPieceKind,
            movedPieceColor: move.piece.color.asPieceColor
        )
        return MoveIndex(raw: newIndex)
    }

    /// Attempts to play a legal SAN move (e.g. `"Nf3"`) at the position for `index`.
    @discardableResult
    public mutating func playMove(san: String, at index: MoveIndex) -> MoveIndex? {
        guard let position = game.positions[index.raw] else { return nil }

        if san.hasPrefix("O-O") || san.hasPrefix("0-0") {
            let isQueenside = san.hasPrefix("O-O-O") || san.hasPrefix("0-0-0")
            let side: Chess960.CastlingSide = isQueenside ? .queenside : .kingside
            let color = position.sideToMove.asPieceColor
            let rank = (color == .white) ? 1 : 8
            let previousFEN = fen(at: index) ?? position.fen

            // Native path first: standard-chess castling stays entirely on
            // ChessKit rails so its internal board state stays consistent.
            var board = Board(position: position)
            let kingSquare = position.pieces.first { $0.kind == .king && $0.color == position.sideToMove }?.square
                ?? Square(isQueenside ? "c\(rank)" : "g\(rank)")
            let kingEnd = Square(isQueenside ? "c\(rank)" : "g\(rank)")
            if board.canMove(pieceAt: kingSquare, to: kingEnd),
                let native = board.move(pieceAt: kingSquare, to: kingEnd),
                case .castle = native.result
            {
                let newIndex = game.make(move: native, from: index.raw)
                customFENs[newIndex] = Self.carryingCastlingRights(
                    previousFEN: previousFEN,
                    resultingFEN: board.position.fen,
                    movingFrom: kingSquare.notation,
                    movingTo: kingEnd.notation,
                    movedPieceKind: .king,
                    movedPieceColor: color
                )
                return MoveIndex(raw: newIndex)
            }

            // Chess960 fallback: ChessKit cannot represent these castles.
            if let castled = Chess960.performCastle(color: color, side: side, in: previousFEN) {
                let kingStart = position.pieces.first { $0.kind == .king && $0.color == position.sideToMove }?.square ?? kingEnd
                let move = Move(result: .move, piece: Piece(.king, color: position.sideToMove, square: kingStart), start: kingStart, end: kingEnd)
                let newIndex = game.make(move: move, from: index.raw)
                customFENs[newIndex] = castled.resultingFEN
                return MoveIndex(raw: newIndex)
            }
            return nil
        }

        guard let move = PGNCompatibility.parseSAN(san, in: position) else { return nil }
        var board = Board(position: position)
        guard board.canMove(pieceAt: move.start, to: move.end),
            var playedMove = board.move(pieceAt: move.start, to: move.end)
        else {
            return nil
        }
        if let promotedPiece = move.promotedPiece {
            playedMove = board.completePromotion(of: playedMove, to: promotedPiece.kind)
        }
        let previousFEN = fen(at: index) ?? position.fen
        let newIndex = game.make(move: move, from: index.raw)
        customFENs[newIndex] = Self.carryingCastlingRights(
            previousFEN: previousFEN,
            resultingFEN: board.position.fen,
            movingFrom: playedMove.start.notation,
            movingTo: playedMove.end.notation,
            movedPieceKind: playedMove.piece.kind.asPieceKind,
            movedPieceColor: playedMove.piece.color.asPieceColor
        )
        return MoveIndex(raw: newIndex)
    }

    /// Attempts to play a legal UCI move (e.g. `"e2e4"`, `"e7e8q"`, `"e1g1"`) at the position for `index`.
    @discardableResult
    public mutating func playMove(uci: String, at index: MoveIndex) -> MoveIndex? {
        guard let position = game.positions[index.raw] else { return nil }
        let color: Piece.Color = position.fen.split(separator: " ").count > 1
            && position.fen.split(separator: " ")[1] == "b"
            ? .black : .white
        guard let parsedMove = EngineLANParser.parse(move: uci, for: color, in: position) else {
            return nil
        }
        var board = Board(position: position)
        guard board.canMove(pieceAt: parsedMove.start, to: parsedMove.end),
            var move = board.move(pieceAt: parsedMove.start, to: parsedMove.end)
        else {
            return nil
        }
        if let promotedPiece = parsedMove.promotedPiece {
            move = board.completePromotion(of: move, to: promotedPiece.kind)
        } else if move.promotedPiece == nil, move.piece.kind == .pawn,
            parsedMove.end.rank.value == 1 || parsedMove.end.rank.value == 8
        {
            return nil
        }
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
    var asPieceKind: PieceKind {
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
    var asPieceColor: PieceColor {
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
        guard field.count <= 4 else { return false }
        if field.allSatisfy({ "KQkq".contains($0) }) {
            let order = Array("KQkq")
            var previous = -1
            for character in field {
                guard let index = order.firstIndex(of: character), index > previous else { return false }
                previous = index
            }
            return true
        }

        // Shredder-FEN: uppercase file letters followed by lowercase file letters
        let validShredder = Set("ABCDEFGHabcdefgh")
        guard field.allSatisfy({ validShredder.contains($0) }) else { return false }
        var seen = Set<Character>()
        var seenLowercase = false
        for character in field {
            guard !seen.contains(character) else { return false }
            seen.insert(character)
            if character.isLowercase {
                seenLowercase = true
            } else if seenLowercase {
                return false
            }
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
        guard let initialPosition = Position(fen: fen) else { return [] }
        let source = Square(square)
        guard source.notation == square, let piece = initialPosition.piece(at: source) else { return [] }

        var fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return [] }
        fields[1] = piece.color == .white ? "w" : "b"
        let activeFEN = fields.joined(separator: " ")
        guard let position = Position(fen: activeFEN) else { return [] }

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
        guard let _ = Position(fen: fen) else { return [] }
        var currentFEN = fen
        var color: Piece.Color = fen.split(separator: " ", maxSplits: 2).count > 1
            && fen.split(separator: " ", maxSplits: 2)[1] == "b"
            ? .black : .white

        var replayed: [ReplayedMove] = []
        for uci in moves {
            guard uci.count >= 4 else { break }
            let startStr = String(uci.prefix(2))
            let endStr = String(uci.dropFirst(2).prefix(2))

            let currentPieceColor = color.asPieceColor
            let rank = (currentPieceColor == .white) ? 1 : 8
            let isKingsideUCI = Self.isKingsideCastleUCI(start: startStr, end: endStr, color: currentPieceColor, in: currentFEN)
            let isQueensideUCI = Self.isQueensideCastleUCI(start: startStr, end: endStr, color: currentPieceColor, in: currentFEN)

            if isKingsideUCI && Chess960.canCastle(color: currentPieceColor, side: .kingside, in: currentFEN) {
                guard let castled = Chess960.performCastle(color: currentPieceColor, side: .kingside, in: currentFEN) else { break }
                let endSq = "g\(rank)"
                replayed.append(ReplayedMove(
                    san: castled.san,
                    uci: uci,
                    movedPieceKind: .king,
                    movedPieceColor: currentPieceColor,
                    capturedPieceKind: nil,
                    isCheck: castled.san.contains("+"),
                    isCheckmate: castled.san.contains("#"),
                    endSquare: endSq,
                    resultingFEN: castled.resultingFEN
                ))
                currentFEN = castled.resultingFEN
                color = color.opposite
                continue
            } else if isQueensideUCI && Chess960.canCastle(color: currentPieceColor, side: .queenside, in: currentFEN) {
                guard let castled = Chess960.performCastle(color: currentPieceColor, side: .queenside, in: currentFEN) else { break }
                let endSq = "c\(rank)"
                replayed.append(ReplayedMove(
                    san: castled.san,
                    uci: uci,
                    movedPieceKind: .king,
                    movedPieceColor: currentPieceColor,
                    capturedPieceKind: nil,
                    isCheck: castled.san.contains("+"),
                    isCheckmate: castled.san.contains("#"),
                    endSquare: endSq,
                    resultingFEN: castled.resultingFEN
                ))
                currentFEN = castled.resultingFEN
                color = color.opposite
                continue
            }

            guard let currentPos = Position(fen: currentFEN) else { break }
            var board = Board(position: currentPos)
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
            let resultingRawFEN = board.position.fen
            let updatedFEN = Self.carryingCastlingRights(
                previousFEN: currentFEN,
                resultingFEN: resultingRawFEN,
                movingFrom: startStr,
                movingTo: endStr,
                movedPieceKind: playedMove.piece.kind.asPieceKind,
                movedPieceColor: currentPieceColor
            )
            replayed.append(playedMove.asReplayedMove(resultingFEN: updatedFEN))
            currentFEN = updatedFEN
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
        var total = position.pieces
            .filter { $0.color == sideToMove }
            .reduce(0) { total, piece in
                total + board.legalMoves(forPieceAt: piece.square).count
            }
        let color = sideToMove.asPieceColor
        if Chess960.canCastle(color: color, side: .kingside, in: fen) { total += 1 }
        if Chess960.canCastle(color: color, side: .queenside, in: fen) { total += 1 }
        return total
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
        let hasBoardMove = position.pieces
            .filter { $0.color == sideToMove }
            .contains { board.legalMoves(forPieceAt: $0.square).contains(target) }
        if hasBoardMove { return true }

        let color = sideToMove.asPieceColor
        let rank = (color == .white) ? 1 : 8
        if square == "g\(rank)" && Chess960.canCastle(color: color, side: .kingside, in: fen) { return true }
        if square == "c\(rank)" && Chess960.canCastle(color: color, side: .queenside, in: fen) { return true }
        return false
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
    /// described by `fen`.
    public static func isSquareAttacked(square: String, by color: PieceColor, in fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        let target = Square(square)
        let targetFile = target.file.number
        let targetRank = target.rank.value

        for piece in position.pieces where piece.color.asPieceColor == color {
            let pieceFile = piece.square.file.number
            let pieceRank = piece.square.rank.value
            let df = targetFile - pieceFile
            let dr = targetRank - pieceRank

            switch piece.kind {
            case .pawn:
                let forward = (color == .white) ? 1 : -1
                if dr == forward && abs(df) == 1 {
                    return true
                }
            case .knight:
                if (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1) {
                    return true
                }
            case .king:
                if max(abs(df), abs(dr)) == 1 {
                    return true
                }
            case .bishop:
                if abs(df) == abs(dr) && abs(df) > 0 {
                    if isRayClear(from: piece.square, to: target, in: position) {
                        return true
                    }
                }
            case .rook:
                if (df == 0 || dr == 0) && (df != 0 || dr != 0) {
                    if isRayClear(from: piece.square, to: target, in: position) {
                        return true
                    }
                }
            case .queen:
                if (abs(df) == abs(dr) && abs(df) > 0) || ((df == 0 || dr == 0) && (df != 0 || dr != 0)) {
                    if isRayClear(from: piece.square, to: target, in: position) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func isRayClear(from start: Square, to end: Square, in position: Position) -> Bool {
        let startFile = start.file.number
        let startRank = start.rank.value
        let endFile = end.file.number
        let endRank = end.rank.value

        let stepFile = (endFile - startFile).signum()
        let stepRank = (endRank - startRank).signum()

        var currentFile = startFile + stepFile
        var currentRank = startRank + stepRank

        while currentFile != endFile || currentRank != endRank {
            let sq = Square(Chess960.fileToSquare(currentFile - 1, rank: currentRank))
            if position.piece(at: sq) != nil {
                return false
            }
            currentFile += stepFile
            currentRank += stepRank
        }
        return true
    }

    /// The clock time in seconds for the move at `index`, parsed from
    /// `[%clk ...]` comments if present, or `nil`.
    public func clockSeconds(at index: MoveIndex) -> Int? {
        guard let comment = game.moves[index.raw]?.comment else { return nil }
        return Self.parseClockAnnotation(comment)
    }

    /// Parses `[%clk 1:23:45]` clock annotations from PGN comments and
    /// returns the clock time in seconds for each move. Returns nil for
    /// comments without a clock annotation.
    /// Format: `[%clk HH:MM:SS]`, `[%clk MM:SS]`, or fractional/decimal seconds.
    public static func parseClockAnnotation(_ comment: String) -> Int? {
        // Find [%clk ...] in the comment
        guard let clkRange = comment.range(of: "\\[%clk\\s+([^\\]]+)\\]", options: .regularExpression) else {
            return nil
        }
        let clkContent = String(comment[clkRange])
        // Extract the time string: HH:MM:SS, H:MM:SS, MM:SS, M:SS, or seconds
        guard let timeRange = clkContent.range(of: "\\d{1,2}:\\d{2}(?::\\d{2})?(?:\\.\\d+)?|\\d+(?:\\.\\d+)?", options: .regularExpression) else {
            return nil
        }
        let timeStr = String(clkContent[timeRange])
        if timeStr.contains(":") {
            let parts = timeStr.split(separator: ":").compactMap { Double($0) }
            switch parts.count {
            case 2: return Int(parts[0] * 60 + parts[1])
            case 3: return Int(parts[0] * 3600 + parts[1] * 60 + parts[2])
            default: return nil
            }
        } else if let seconds = Double(timeStr) {
            return Int(seconds)
        }
        return nil
    }

    /// ChessKit's FEN serialization drops non-standard (Shredder) castling
    /// rights, so after every normal move the rights field from the pre-move
    /// FEN - advanced via `Chess960.updateCastlingRights` - is spliced back
    /// into the resulting FEN. Returns `resultingFEN` untouched when the
    /// pre-move position has no castling rights.
    private static func carryingCastlingRights(
        previousFEN: String,
        resultingFEN: String,
        movingFrom startSquare: String,
        movingTo endSquare: String,
        movedPieceKind: PieceKind,
        movedPieceColor: PieceColor
    ) -> String {
        let previousFields = previousFEN.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard previousFields.count == 6, previousFields[2] != "-" else { return resultingFEN }

        let advanced = Chess960.updateCastlingRights(
            in: previousFEN,
            movingFrom: startSquare,
            movingTo: endSquare,
            movedPieceKind: movedPieceKind,
            movedPieceColor: movedPieceColor
        )
        guard let rights = advanced.split(separator: " ", omittingEmptySubsequences: true).dropFirst(2).first else {
            return resultingFEN
        }
        var fields = resultingFEN.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6 else { return resultingFEN }
        fields[2] = String(rights)
        return fields.joined(separator: " ")
    }

    private static func isKingsideRook(_ square: Square, color: PieceColor, in fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6, let (r1, r8) = Chess960.backRanks(from: fields[0]) else { return false }
        let rights = Chess960.CastlingRights.parse(from: fields[2], rank1: r1, rank8: r8)
        let rf = (color == .white) ? rights.whiteKingsideRookFile : rights.blackKingsideRookFile
        guard let rf else { return false }
        let rank = (color == .white) ? 1 : 8
        return square.notation == Chess960.fileToSquare(rf, rank: rank)
    }

    private static func isQueensideRook(_ square: Square, color: PieceColor, in fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6, let (r1, r8) = Chess960.backRanks(from: fields[0]) else { return false }
        let rights = Chess960.CastlingRights.parse(from: fields[2], rank1: r1, rank8: r8)
        let rf = (color == .white) ? rights.whiteQueensideRookFile : rights.blackQueensideRookFile
        guard let rf else { return false }
        let rank = (color == .white) ? 1 : 8
        return square.notation == Chess960.fileToSquare(rf, rank: rank)
    }

    private static func isKingsideCastleUCI(start: String, end: String, color: PieceColor, in fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6, let (r1, r8) = Chess960.backRanks(from: fields[0]) else { return false }
        let rankChars = (color == .white) ? r1 : r8
        let kingChar: Character = (color == .white) ? "K" : "k"
        guard let kf = rankChars.firstIndex(of: kingChar) else { return false }
        let rank = (color == .white) ? 1 : 8
        guard start == Chess960.fileToSquare(kf, rank: rank) else { return false }
        let startFile = start.first.map { Int($0.asciiValue! - Character("a").asciiValue!) } ?? 0
        if end == "g\(rank)", abs(6 - startFile) >= 2 { return true }
        return isKingsideRook(Square(end), color: color, in: fen)
    }

    private static func isQueensideCastleUCI(start: String, end: String, color: PieceColor, in fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6, let (r1, r8) = Chess960.backRanks(from: fields[0]) else { return false }
        let rankChars = (color == .white) ? r1 : r8
        let kingChar: Character = (color == .white) ? "K" : "k"
        guard let kf = rankChars.firstIndex(of: kingChar) else { return false }
        let rank = (color == .white) ? 1 : 8
        guard start == Chess960.fileToSquare(kf, rank: rank) else { return false }
        let startFile = start.first.map { Int($0.asciiValue! - Character("a").asciiValue!) } ?? 0
        if end == "c\(rank)", abs(2 - startFile) >= 2 { return true }
        return isQueensideRook(Square(end), color: color, in: fen)
    }

    /// The side to move in `fen` (.white or .black).
    public static func sideToMove(fen: String) -> PieceColor {
        let parts = fen.split(separator: " ")
        if parts.count > 1 && parts[1] == "b" {
            return .black
        }
        return .white
    }

    /// Whether the side to move in `fen` is currently in check.
    public static func isCheck(fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        let side = sideToMove(fen: fen)
        guard let king = position.pieces.first(where: { $0.kind == .king && $0.color.asPieceColor == side }) else {
            return false
        }
        return isSquareAttacked(square: king.square.notation, by: side.opposite, in: fen)
    }

    /// Whether the position in `fen` is checkmate for the side to move.
    public static func isCheckmate(fen: String) -> Bool {
        isCheck(fen: fen) && legalMoveCount(fen: fen) == 0
    }

    /// Whether the position in `fen` is stalemate for the side to move.
    public static func isStalemate(fen: String) -> Bool {
        !isCheck(fen: fen) && legalMoveCount(fen: fen) == 0
    }

    /// Whether the position in `fen` has reached the fifty-move rule draw
    /// (halfmove clock >= 100).
    public static func isFiftyMoveDraw(fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 5, let halfmoveClock = Int(fields[4]), halfmoveClock >= 100 else {
            return false
        }
        return true
    }

    /// Whether the position in `fen` is a draw by insufficient material
    /// (K vs K, KN vs K, KB vs K, KB vs KB with same-colored bishops).
    public static func hasInsufficientMaterial(fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        let pieces = position.pieces
        if pieces.contains(where: { $0.kind == .pawn || $0.kind == .rook || $0.kind == .queen }) {
            return false
        }
        let whiteKings = pieces.filter { $0.kind == .king && $0.color == .white }
        let blackKings = pieces.filter { $0.kind == .king && $0.color == .black }
        guard whiteKings.count == 1, blackKings.count == 1 else { return false }

        let nonKings = pieces.filter { $0.kind != .king }
        if nonKings.isEmpty { return true }
        if nonKings.count == 1 {
            let kind = nonKings[0].kind
            if kind == .knight || kind == .bishop { return true }
            return false
        }
        if nonKings.count == 2 {
            let whiteBishops = nonKings.filter { $0.kind == .bishop && $0.color == .white }
            let blackBishops = nonKings.filter { $0.kind == .bishop && $0.color == .black }
            if whiteBishops.count == 1 && blackBishops.count == 1 {
                let wSquare = whiteBishops[0].square
                let bSquare = blackBishops[0].square
                let wColor = (wSquare.file.number + wSquare.rank.value) % 2
                let bColor = (bSquare.file.number + bSquare.rank.value) % 2
                if wColor == bColor {
                    return true
                }
            }
            return false
        }
        return false
    }

    /// Whether the game history has reached a draw by threefold repetition.
    public static func isThreefoldRepetition(fens: [String]) -> Bool {
        var counts: [String: Int] = [:]
        for fen in fens {
            let key = epd(fromFEN: fen)
            let newCount = (counts[key] ?? 0) + 1
            if newCount >= 3 { return true }
            counts[key] = newCount
        }
        return false
    }

    /// Detects if the current position is game over by checkmate, stalemate,
    /// insufficient material, fifty-move rule, or threefold repetition.
    public static func detectOutcome(currentFEN: String, historyFENs: [String]) -> GameOutcome? {
        if isCheckmate(fen: currentFEN) {
            let side = sideToMove(fen: currentFEN)
            return .checkmate(winner: side.opposite)
        }
        if isStalemate(fen: currentFEN) {
            return .stalemate
        }
        if hasInsufficientMaterial(fen: currentFEN) {
            return .insufficientMaterial
        }
        if isFiftyMoveDraw(fen: currentFEN) {
            return .fiftyMoveRule
        }
        if isThreefoldRepetition(fens: historyFENs) {
            return .repetition
        }
        return nil
    }
}

// MARK: - Game Outcome & Player Side Selection

public enum GameOutcome: Hashable, Sendable, Codable {
    case checkmate(winner: PieceColor)
    case stalemate
    case repetition
    case fiftyMoveRule
    case insufficientMaterial
    case resignation(resignedBy: PieceColor)

    public var resultString: String {
        switch self {
        case .checkmate(let winner):
            return winner == .white ? "1-0" : "0-1"
        case .resignation(let resignedBy):
            return resignedBy == .white ? "0-1" : "1-0"
        case .stalemate, .repetition, .fiftyMoveRule, .insufficientMaterial:
            return "1/2-1/2"
        }
    }

    public var isDraw: Bool {
        switch self {
        case .stalemate, .repetition, .fiftyMoveRule, .insufficientMaterial:
            return true
        case .checkmate, .resignation:
            return false
        }
    }

    public var winner: PieceColor? {
        switch self {
        case .checkmate(let winner):
            return winner
        case .resignation(let resignedBy):
            return resignedBy.opposite
        case .stalemate, .repetition, .fiftyMoveRule, .insufficientMaterial:
            return nil
        }
    }

    public var terminationDescription: String {
        switch self {
        case .checkmate(let winner):
            return "\(winner == .white ? "White" : "Black") won by checkmate"
        case .resignation(let resignedBy):
            return "\(resignedBy == .white ? "Black" : "White") won by resignation"
        case .stalemate:
            return "Draw by stalemate"
        case .repetition:
            return "Draw by repetition"
        case .fiftyMoveRule:
            return "Draw by fifty-move rule"
        case .insufficientMaterial:
            return "Draw by insufficient material"
        }
    }
}

public enum PlayerSideSelection: String, CaseIterable, Sendable, Codable {
    case white
    case black
    case random

    public func resolveColor() -> PieceColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .random: return Bool.random() ? .white : .black
        }
    }
}
