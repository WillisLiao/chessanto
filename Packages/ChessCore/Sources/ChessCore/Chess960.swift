import ChessKit
import Foundation

/// Pure, deterministic Chess960 (Fischer Random Chess) generator, validator,
/// FEN encoder/decoder, and castling legality engine.
public enum Chess960 {

    // MARK: - Starting Position Generation

    /// The combinations of 2 knight positions from 5 empty squares, in
    /// standard Scharnagl (lexicographical) order.
    private static let knightPairs: [(Int, Int)] = [
        (0, 1), (0, 2), (0, 3), (0, 4),
        (1, 2), (1, 3), (1, 4),
        (2, 3), (2, 4),
        (3, 4)
    ]

    /// Produces the 8-character uppercase back-rank arrangement for rank 1
    /// (e.g. `"RNBQKBNR"` for index 518, `"BBQNNRKR"` for index 0)
    /// given a standard Chess960 index in `0...959`.
    public static func backRank(index: Int) -> String {
        precondition((0...959).contains(index), "Chess960 index must be in 0...959, got \(index)")

        var squares = [Character?](repeating: nil, count: 8)

        // 1. Light-square bishop on b, d, f, or h (indices 1, 3, 5, 7)
        let n1 = index % 4
        let lightBishopFile = 2 * n1 + 1
        squares[lightBishopFile] = "B"

        var remainder = index / 4

        // 2. Dark-square bishop on a, c, e, or g (indices 0, 2, 4, 6)
        let n2 = remainder % 4
        let darkBishopFile = 2 * n2
        squares[darkBishopFile] = "B"

        remainder = remainder / 4

        // 3. Queen on the n3-th remaining empty square (0...5)
        let n3 = remainder % 6
        var emptyCount = 0
        for i in 0..<8 where squares[i] == nil {
            if emptyCount == n3 {
                squares[i] = "Q"
                break
            }
            emptyCount += 1
        }

        remainder = remainder / 6

        // 4. Knights on the remaining empty squares (0...9)
        let n4 = remainder
        let (k1, k2) = knightPairs[n4]
        var remainingIndices: [Int] = []
        for i in 0..<8 where squares[i] == nil {
            remainingIndices.append(i)
        }
        squares[remainingIndices[k1]] = "N"
        squares[remainingIndices[k2]] = "N"

        // 5. Remaining 3 empty squares are filled with R, K, R (in that order)
        let rookKingIndices = (0..<8).filter { squares[$0] == nil }
        squares[rookKingIndices[0]] = "R"
        squares[rookKingIndices[1]] = "K"
        squares[rookKingIndices[2]] = "R"

        return String(squares.compactMap { $0 })
    }

    /// Produces a deterministic back-rank string using a 64-bit seed.
    public static func backRank(seed: UInt64) -> String {
        let index = Int(seed % 960)
        return backRank(index: index)
    }

    /// Computes the standard Chess960 index (`0...959`) from an 8-character
    /// back-rank string, or returns `nil` if the arrangement is invalid.
    public static func index(of backRank: String) -> Int? {
        guard isValidBackRank(backRank) else { return nil }
        let chars = Array(backRank)

        // Find light-square bishop (files 1, 3, 5, 7)
        guard let lightBFile = chars.indices.first(where: { chars[$0] == "B" && $0 % 2 == 1 }) else { return nil }
        let n1 = lightBFile / 2

        // Find dark-square bishop (files 0, 2, 4, 6)
        guard let darkBFile = chars.indices.first(where: { chars[$0] == "B" && $0 % 2 == 0 }) else { return nil }
        let n2 = darkBFile / 2

        // Filter out bishops to get 6 remaining squares
        var remainingAfterBishops: [(file: Int, char: Character)] = []
        for (file, char) in chars.enumerated() where file != lightBFile && file != darkBFile {
            remainingAfterBishops.append((file, char))
        }
        guard remainingAfterBishops.count == 6 else { return nil }

        // Find queen position among the 6 remaining
        guard let queenPos = remainingAfterBishops.firstIndex(where: { $0.char == "Q" }) else { return nil }
        let n3 = queenPos

        // Filter out queen to get 5 remaining squares
        var remainingAfterQueen: [(file: Int, char: Character)] = []
        for (i, item) in remainingAfterBishops.enumerated() where i != queenPos {
            remainingAfterQueen.append(item)
        }
        guard remainingAfterQueen.count == 5 else { return nil }

        // Find knight positions among the 5 remaining
        let knightPositions = remainingAfterQueen.indices.filter { remainingAfterQueen[$0].char == "N" }
        guard knightPositions.count == 2 else { return nil }
        let pair = (knightPositions[0], knightPositions[1])
        guard let n4 = knightPairs.firstIndex(where: { $0 == pair }) else { return nil }

        // Verify remaining 3 squares are R, K, R
        let finalThree = remainingAfterQueen.indices.filter { $0 != pair.0 && $0 != pair.1 }.map { remainingAfterQueen[$0].char }
        guard finalThree == ["R", "K", "R"] else { return nil }

        return n1 + 4 * (n2 + 4 * (n3 + 6 * n4))
    }

    /// Validates that an 8-character back-rank string satisfies all Chess960
    /// requirements: 2 bishops on opposite-colored squares, king strictly
    /// between the 2 rooks, 2 knights, and 1 queen.
    public static func isValidBackRank(_ backRank: String) -> Bool {
        guard backRank.count == 8 else { return false }
        let chars = Array(backRank)

        var counts: [Character: Int] = [:]
        for c in chars {
            counts[c, default: 0] += 1
        }
        guard counts["B"] == 2, counts["R"] == 2, counts["N"] == 2, counts["Q"] == 1, counts["K"] == 1 else {
            return false
        }

        // Bishops on opposite colors
        let bishopIndices = chars.indices.filter { chars[$0] == "B" }
        guard bishopIndices.count == 2 else { return false }
        let isOppositeColors = (bishopIndices[0] % 2) != (bishopIndices[1] % 2)
        guard isOppositeColors else { return false }

        // King between rooks
        let rookIndices = chars.indices.filter { chars[$0] == "R" }
        guard let kingIndex = chars.indices.first(where: { chars[$0] == "K" }), rookIndices.count == 2 else {
            return false
        }
        guard rookIndices[0] < kingIndex && kingIndex < rookIndices[1] else {
            return false
        }

        return true
    }

    // MARK: - FEN Generation and Parsing

    /// Generates the standard 6-field starting FEN string for a Chess960 game.
    ///
    /// - Parameters:
    ///   - index: The Chess960 position index (0...959).
    ///   - useShredderFEN: If true, emits Shredder-FEN castling rights (e.g. `HAha`, `FHfh`),
    ///     which explicitly names the rook files. If false, emits traditional `KQkq`.
    public static func startingFEN(index: Int, useShredderFEN: Bool = true) -> String {
        let rank = backRank(index: index)
        return startingFEN(backRank: rank, useShredderFEN: useShredderFEN)
    }

    /// Generates a starting FEN string from a 64-bit seed.
    public static func startingFEN(seed: UInt64, useShredderFEN: Bool = true) -> String {
        let rank = backRank(seed: seed)
        return startingFEN(backRank: rank, useShredderFEN: useShredderFEN)
    }

    /// Generates a starting FEN string from a valid back-rank string.
    public static func startingFEN(backRank: String, useShredderFEN: Bool = true) -> String {
        precondition(isValidBackRank(backRank), "Invalid Chess960 back rank: \(backRank)")

        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let chars = Array(backRank)
        let rookIndices = chars.indices.filter { chars[$0] == "R" }

        let castling: String
        if useShredderFEN {
            let whiteRooks = rookIndices.map { files[$0].uppercased() }.joined()
            let blackRooks = rookIndices.map { files[$0].lowercased() }.joined()
            castling = "\(whiteRooks)\(blackRooks)"
        } else {
            castling = "KQkq"
        }

        let rank8 = backRank.lowercased()
        let rank1 = backRank.uppercased()
        return "\(rank8)/pppppppp/8/8/8/8/PPPPPPPP/\(rank1) w \(castling) - 0 1"
    }

    /// Whether `fen` describes a valid symmetric Chess960 starting position.
    public static func isChess960(startingFEN fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6 else { return false }
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard ranks.count == 8 else { return false }

        guard ranks[1] == "pppppppp", ranks[2] == "8", ranks[3] == "8", ranks[4] == "8", ranks[5] == "8", ranks[6] == "PPPPPPPP" else {
            return false
        }
        guard ranks[0] == ranks[7].lowercased() else { return false }
        return isValidBackRank(ranks[7])
    }

    // MARK: - Castling Rights and Legality

    public enum CastlingSide: Sendable, CaseIterable {
        case kingside   // O-O
        case queenside  // O-O-O
    }

    /// Castling rights associated with a position.
    public struct CastlingRights: Equatable, Hashable, Sendable {
        public var whiteKingsideRookFile: Int?
        public var whiteQueensideRookFile: Int?
        public var blackKingsideRookFile: Int?
        public var blackQueensideRookFile: Int?

        public init(
            whiteKingsideRookFile: Int? = nil,
            whiteQueensideRookFile: Int? = nil,
            blackKingsideRookFile: Int? = nil,
            blackQueensideRookFile: Int? = nil
        ) {
            self.whiteKingsideRookFile = whiteKingsideRookFile
            self.whiteQueensideRookFile = whiteQueensideRookFile
            self.blackKingsideRookFile = blackKingsideRookFile
            self.blackQueensideRookFile = blackQueensideRookFile
        }

        public var isEmpty: Bool {
            whiteKingsideRookFile == nil && whiteQueensideRookFile == nil &&
            blackKingsideRookFile == nil && blackQueensideRookFile == nil
        }

        /// Formats castling rights as Shredder-FEN (e.g. `HAha`, `FHfh`, `-`).
        public var shredderFEN: String {
            if isEmpty { return "-" }
            let files = ["A", "B", "C", "D", "E", "F", "G", "H"]
            var res = ""
            var whiteFiles: [Int] = []
            if let q = whiteQueensideRookFile { whiteFiles.append(q) }
            if let k = whiteKingsideRookFile { whiteFiles.append(k) }
            for f in whiteFiles.sorted() { res.append(files[f]) }

            var blackFiles: [Int] = []
            if let q = blackQueensideRookFile { blackFiles.append(q) }
            if let k = blackKingsideRookFile { blackFiles.append(k) }
            for f in blackFiles.sorted() { res.append(files[f].lowercased()) }

            return res.isEmpty ? "-" : res
        }

        /// Formats castling rights as traditional FEN (`KQkq` or `-`).
        public var traditionalFEN: String {
            if isEmpty { return "-" }
            var res = ""
            if whiteKingsideRookFile != nil { res.append("K") }
            if whiteQueensideRookFile != nil { res.append("Q") }
            if blackKingsideRookFile != nil { res.append("k") }
            if blackQueensideRookFile != nil { res.append("q") }
            return res.isEmpty ? "-" : res
        }

        /// Parses castling rights from a FEN castling field, given the piece placement.
        public static func parse(from castlingField: String, rank1: [Character], rank8: [Character]) -> CastlingRights {
            var rights = CastlingRights()
            guard castlingField != "-", !castlingField.isEmpty else { return rights }

            let whiteKingFile = rank1.firstIndex(of: "K") ?? 4
            let blackKingFile = rank8.firstIndex(of: "k") ?? 4

            let whiteRooks = rank1.enumerated().filter { $0.element == "R" }.map(\.offset)
            let blackRooks = rank8.enumerated().filter { $0.element == "r" }.map(\.offset)

            for char in castlingField {
                switch char {
                case "K":
                    // White kingside rook (rook with file > king)
                    if let f = whiteRooks.first(where: { $0 > whiteKingFile }) {
                        rights.whiteKingsideRookFile = f
                    } else if let last = whiteRooks.last {
                        rights.whiteKingsideRookFile = last
                    }
                case "Q":
                    // White queenside rook (rook with file < king)
                    if let f = whiteRooks.last(where: { $0 < whiteKingFile }) {
                        rights.whiteQueensideRookFile = f
                    } else if let first = whiteRooks.first {
                        rights.whiteQueensideRookFile = first
                    }
                case "k":
                    // Black kingside rook
                    if let f = blackRooks.first(where: { $0 > blackKingFile }) {
                        rights.blackKingsideRookFile = f
                    } else if let last = blackRooks.last {
                        rights.blackKingsideRookFile = last
                    }
                case "q":
                    // Black queenside rook
                    if let f = blackRooks.last(where: { $0 < blackKingFile }) {
                        rights.blackQueensideRookFile = f
                    } else if let first = blackRooks.first {
                        rights.blackQueensideRookFile = first
                    }
                case "A"..."H":
                    // Shredder-FEN uppercase file letter for White rook
                    let file = Int(char.asciiValue! - Character("A").asciiValue!)
                    if file > whiteKingFile {
                        rights.whiteKingsideRookFile = file
                    } else {
                        rights.whiteQueensideRookFile = file
                    }
                case "a"..."h":
                    // Shredder-FEN lowercase file letter for Black rook
                    let file = Int(char.asciiValue! - Character("a").asciiValue!)
                    if file > blackKingFile {
                        rights.blackKingsideRookFile = file
                    } else {
                        rights.blackQueensideRookFile = file
                    }
                default:
                    break
                }
            }

            return rights
        }
    }

    /// Extracts ranks 1 and 8 as character arrays from a FEN board field.
    public static func backRanks(from boardField: String) -> (rank1: [Character], rank8: [Character])? {
        let ranks = boardField.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard ranks.count == 8 else { return nil }

        func expandRank(_ rankStr: String) -> [Character] {
            var res: [Character] = []
            for c in rankStr {
                if let n = c.wholeNumberValue {
                    res.append(contentsOf: repeatElement(".", count: n))
                } else {
                    res.append(c)
                }
            }
            return res
        }

        let r8 = expandRank(ranks[0])
        let r1 = expandRank(ranks[7])
        guard r8.count == 8, r1.count == 8 else { return nil }
        return (rank1: r1, rank8: r8)
    }

    /// Checks whether castling is legal for `color` on `side` in `fen`.
    public static func canCastle(color: PieceColor, side: CastlingSide, in fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6 else { return false }
        guard let (rank1, rank8) = backRanks(from: fields[0]) else { return false }

        let rights = CastlingRights.parse(from: fields[2], rank1: rank1, rank8: rank8)
        let isWhite = (color == .white)
        let rankNum = isWhite ? 1 : 8
        let rankChars = isWhite ? rank1 : rank8

        let kingChar: Character = isWhite ? "K" : "k"
        let rookChar: Character = isWhite ? "R" : "r"

        guard let kingFile = rankChars.firstIndex(of: kingChar) else { return false }

        let rookFile: Int
        switch (isWhite, side) {
        case (true, .kingside):
            guard let rf = rights.whiteKingsideRookFile else { return false }
            rookFile = rf
        case (true, .queenside):
            guard let rf = rights.whiteQueensideRookFile else { return false }
            rookFile = rf
        case (false, .kingside):
            guard let rf = rights.blackKingsideRookFile else { return false }
            rookFile = rf
        case (false, .queenside):
            guard let rf = rights.blackQueensideRookFile else { return false }
            rookFile = rf
        }

        guard rookFile >= 0, rookFile < 8, rankChars[rookFile] == rookChar else { return false }

        let castledKingFile = (side == .kingside) ? 6 : 2
        let castledRookFile = (side == .kingside) ? 5 : 3

        // 1. King cannot be in check in the current position
        let kingSquare = fileToSquare(kingFile, rank: rankNum)
        guard !ChessGame.isSquareAttacked(square: kingSquare, by: color.opposite, in: fen) else {
            return false
        }

        let kingTransitFiles: [Int]
        if kingFile < castledKingFile {
            kingTransitFiles = Array((kingFile + 1)...castledKingFile)
        } else if kingFile > castledKingFile {
            kingTransitFiles = Array(castledKingFile..<kingFile)
        } else {
            kingTransitFiles = []
        }

        for file in kingTransitFiles {
            let sq = fileToSquare(file, rank: rankNum)
            guard !ChessGame.isSquareAttacked(square: sq, by: color.opposite, in: fen) else {
                return false
            }
        }

        let minFile = min(kingFile, castledKingFile, rookFile, castledRookFile)
        let maxFile = max(kingFile, castledKingFile, rookFile, castledRookFile)

        for file in minFile...maxFile {
            if file != kingFile && file != rookFile {
                if rankChars[file] != "." {
                    return false
                }
            }
        }

        return true
    }

    /// Performs castling in `fen` for `color` on `side`, returning the resulting
    /// FEN, SAN (e.g. `"O-O"` or `"O-O-O"` with check/mate suffix), and UCI.
    public static func performCastle(
        color: PieceColor,
        side: CastlingSide,
        in fen: String
    ) -> (resultingFEN: String, san: String, uci: String)? {
        guard canCastle(color: color, side: side, in: fen) else { return nil }

        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6 else { return nil }
        guard let (rank1, rank8) = backRanks(from: fields[0]) else { return nil }

        let rights = CastlingRights.parse(from: fields[2], rank1: rank1, rank8: rank8)
        let isWhite = (color == .white)
        let rankNum = isWhite ? 1 : 8
        var currentRank = isWhite ? rank1 : rank8

        let kingChar: Character = isWhite ? "K" : "k"
        let rookChar: Character = isWhite ? "R" : "r"

        guard let kingFile = currentRank.firstIndex(of: kingChar) else { return nil }

        let rookFile: Int = {
            switch (isWhite, side) {
            case (true, .kingside): return rights.whiteKingsideRookFile!
            case (true, .queenside): return rights.whiteQueensideRookFile!
            case (false, .kingside): return rights.blackKingsideRookFile!
            case (false, .queenside): return rights.blackQueensideRookFile!
            }
        }()

        let castledKingFile = (side == .kingside) ? 6 : 2 // g or c
        let castledRookFile = (side == .kingside) ? 5 : 3 // f or d

        // Clear king and rook from initial squares
        currentRank[kingFile] = "."
        currentRank[rookFile] = "."

        // Place king and rook on castled squares
        currentRank[castledKingFile] = kingChar
        currentRank[castledRookFile] = rookChar

        // Reconstruct board field
        let rawRanks = fields[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var updatedRanks = rawRanks

        func compressRank(_ rankChars: [Character]) -> String {
            var res = ""
            var empty = 0
            for c in rankChars {
                if c == "." {
                    empty += 1
                } else {
                    if empty > 0 {
                        res += String(empty)
                        empty = 0
                    }
                    res.append(c)
                }
            }
            if empty > 0 {
                res += String(empty)
            }
            return res
        }

        if isWhite {
            updatedRanks[7] = compressRank(currentRank)
        } else {
            updatedRanks[0] = compressRank(currentRank)
        }
        let newBoardField = updatedRanks.joined(separator: "/")

        // Update castling rights (invalidate all castling rights for this color)
        var updatedRights = rights
        if isWhite {
            updatedRights.whiteKingsideRookFile = nil
            updatedRights.whiteQueensideRookFile = nil
        } else {
            updatedRights.blackKingsideRookFile = nil
            updatedRights.blackQueensideRookFile = nil
        }
        let isTraditional = fields[2].allSatisfy { "KQkq-".contains($0) }
        let newCastlingField = isTraditional ? updatedRights.traditionalFEN : updatedRights.shredderFEN

        // Update clocks & side to move
        let newSideToMove = isWhite ? "b" : "w"
        let halfmove = (Int(fields[4]) ?? 0) + 1
        let fullmove = isWhite ? (Int(fields[5]) ?? 1) : (Int(fields[5]) ?? 1) + 1

        let newFEN = "\(newBoardField) \(newSideToMove) \(newCastlingField) - \(halfmove) \(fullmove)"

        // Determine check / checkmate on opponent
        let opponentKingChar: Character = isWhite ? "k" : "K"
        let opponentRank = isWhite ? rank8 : rank1
        let opponentKingSquare: String? = {
            if let f = opponentRank.firstIndex(of: opponentKingChar) {
                return fileToSquare(f, rank: isWhite ? 8 : 1)
            }
            return nil
        }()

        var checkSuffix = ""
        if let oppSq = opponentKingSquare, ChessGame.isSquareAttacked(square: oppSq, by: color, in: newFEN) {
            let oppMoves = ChessGame.legalMoveCount(fen: newFEN)
            checkSuffix = (oppMoves == 0) ? "#" : "+"
        }

        let san = (side == .kingside ? "O-O" : "O-O-O") + checkSuffix
        let uci = "\(fileToSquare(kingFile, rank: rankNum))\(fileToSquare(rookFile, rank: rankNum))"

        return (resultingFEN: newFEN, san: san, uci: uci)
    }

    /// Normalizes castling rights upon standard piece moves or captures.
    public static func updateCastlingRights(
        in fen: String,
        movingFrom startSquare: String,
        movingTo endSquare: String,
        movedPieceKind: PieceKind,
        movedPieceColor: PieceColor
    ) -> String {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6 else { return fen }
        guard let (rank1, rank8) = backRanks(from: fields[0]) else { return fen }

        var rights = CastlingRights.parse(from: fields[2], rank1: rank1, rank8: rank8)
        guard !rights.isEmpty else { return fen }

        guard let startFileChar = startSquare.first, let startRankNum = startSquare.last?.wholeNumberValue,
              let endFileChar = endSquare.first, let endRankNum = endSquare.last?.wholeNumberValue else {
            return fen
        }

        let startFile = Int(startFileChar.asciiValue! - Character("a").asciiValue!)
        let endFile = Int(endFileChar.asciiValue! - Character("a").asciiValue!)

        if movedPieceColor == .white {
            if movedPieceKind == .king {
                rights.whiteKingsideRookFile = nil
                rights.whiteQueensideRookFile = nil
            } else if startRankNum == 1 {
                if rights.whiteKingsideRookFile == startFile { rights.whiteKingsideRookFile = nil }
                if rights.whiteQueensideRookFile == startFile { rights.whiteQueensideRookFile = nil }
            }
        } else {
            if movedPieceKind == .king {
                rights.blackKingsideRookFile = nil
                rights.blackQueensideRookFile = nil
            } else if startRankNum == 8 {
                if rights.blackKingsideRookFile == startFile { rights.blackKingsideRookFile = nil }
                if rights.blackQueensideRookFile == startFile { rights.blackQueensideRookFile = nil }
            }
        }

        // Check if a rook on its starting square was captured
        if endRankNum == 1 {
            if rights.whiteKingsideRookFile == endFile { rights.whiteKingsideRookFile = nil }
            if rights.whiteQueensideRookFile == endFile { rights.whiteQueensideRookFile = nil }
        } else if endRankNum == 8 {
            if rights.blackKingsideRookFile == endFile { rights.blackKingsideRookFile = nil }
            if rights.blackQueensideRookFile == endFile { rights.blackQueensideRookFile = nil }
        }

        var updatedFields = fields
        let isTraditional = fields[2].allSatisfy { "KQkq-".contains($0) }
        updatedFields[2] = isTraditional ? rights.traditionalFEN : rights.shredderFEN
        return updatedFields.joined(separator: " ")
    }

    public static func fileToSquare(_ fileIndex: Int, rank: Int) -> String {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        return "\(files[fileIndex])\(rank)"
    }
}
