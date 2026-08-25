import ChessKit
import Foundation

/// Internal compatibility parser for PGN games.
///
/// Invoked as a targeted fallback when upstream `ChessKit.Game(pgn:)` throws.
/// Resolves disambiguated piece-capture tokens (e.g., `Rfxe1`, `Nbxd7+`, `R1xe1`, `Ra1xe1`)
/// that upstream `SANParser` rejects due to an incomplete regex lookahead, while
/// preserving complete fidelity for comments, NAGs, annotations, variations,
/// castling, promotions, checks, and custom starting positions.
enum PGNCompatibility {

    public enum Error: Swift.Error, Equatable {
        case invalidSetUpOrFEN
        case invalidMove(String)
        case unpairedCommentDelimiter
        case unpairedVariationDelimiter
    }

    /// Normalizes PGN input text by standardizing line endings, stripping BOM,
    /// removing PGN % escape lines, stripping movetext semicolon comments, and
    /// standardizing 0-0 / 0-0-0 castling to O-O / O-O-O.
    public static func normalize(pgn: String) -> String {
        let text = pgn.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))

        let lines = text.components(separatedBy: "\n")
        var normalizedLines: [String] = []
        var inMoveText = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if inMoveText || !normalizedLines.isEmpty {
                    inMoveText = true
                    normalizedLines.append("")
                }
                continue
            }
            if trimmed.hasPrefix("%") {
                continue
            }
            if !inMoveText && trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                normalizedLines.append(trimmed)
            } else {
                inMoveText = true
                let withoutSemi: String
                if let semiIdx = line.firstIndex(of: ";") {
                    withoutSemi = String(line[..<semiIdx])
                } else {
                    withoutSemi = line
                }
                let normalizedMoveLine = withoutSemi
                    .replacingOccurrences(of: "0-0-0", with: "O-O-O")
                    .replacingOccurrences(of: "0-0", with: "O-O")
                normalizedLines.append(normalizedMoveLine)
            }
        }

        return normalizedLines.joined(separator: "\n")
    }

    public struct ParsedPGN {
        public let game: Game
        public let fens: [MoveTree.Index: String]
    }

    public static func parse(pgn: String) throws -> ParsedPGN {
        let normalized = normalize(pgn: pgn)
        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var tagLines: [String] = []
        var moveTextLines: [String] = []
        var inMoveText = false

        for line in lines {
            if line.isEmpty {
                if !tagLines.isEmpty {
                    inMoveText = true
                }
                continue
            }
            if !inMoveText && line.hasPrefix("[") && line.hasSuffix("]") {
                tagLines.append(line)
            } else {
                inMoveText = true
                moveTextLines.append(line)
            }
        }

        let tags = try parseTags(from: tagLines.joined(separator: "\n"))
        let startingPos = try startingPosition(from: tags)
        let moveText = moveTextLines.joined(separator: " ")
        return try parseMoveText(moveText, startingPosition: startingPos, tags: tags)
    }

    private static func startingPosition(from tags: Game.Tags) throws -> Position {
        if tags.setUp == "1" || (!tags.fen.isEmpty && tags.setUp != "0") {
            guard let position = Position(fen: tags.fen) else {
                throw Error.invalidSetUpOrFEN
            }
            return position
        } else if tags.setUp == "0" || (tags.setUp.isEmpty && tags.fen.isEmpty) {
            return .standard
        } else {
            throw Error.invalidSetUpOrFEN
        }
    }

    private static func parseTags(from tagString: String) throws -> Game.Tags {
        var tags = Game.Tags()
        guard !tagString.isEmpty else { return tags }

        let pattern = #"\[\s*([A-Za-z0-9_]+)\s+"([^"]*)"\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return tags }

        let nsString = tagString as NSString
        let matches = regex.matches(in: tagString, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let key = nsString.substring(with: match.range(at: 1))
            let value = nsString.substring(with: match.range(at: 2))

            switch key.lowercased() {
            case "event": tags.event = value
            case "site": tags.site = value
            case "date": tags.date = value
            case "round": tags.round = value
            case "white": tags.white = value
            case "black": tags.black = value
            case "result": tags.result = value
            case "annotator": tags.annotator = value
            case "plycount": tags.plyCount = value
            case "timecontrol": tags.timeControl = value
            case "time": tags.time = value
            case "termination": tags.termination = value
            case "mode": tags.mode = value
            case "fen": tags.fen = value
            case "setup": tags.setUp = value
            default: tags.other[key] = value
            }
        }

        return tags
    }

    private enum Token: Equatable {
        case number(String)
        case san(String)
        case annotation(String)
        case comment(String)
        case variationStart
        case variationEnd
        case result(String)
    }

    private static func tokenize(moveText: String) throws -> [Token] {
        var inlineMoveText = moveText.components(separatedBy: .newlines).joined(separator: " ")
        var resultToken: Token?

        let words = inlineMoveText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let lastWord = words.last, isGameResult(lastWord) {
            resultToken = .result(lastWord)
            let withoutLast = words.dropLast().joined(separator: " ")
            inlineMoveText = withoutLast
        }

        var tokens: [Token] = []
        var iterator = inlineMoveText.makeIterator()
        var currentToken = ""
        var inComment = false

        while let c = iterator.next() {
            if c == "{" {
                if !currentToken.isEmpty {
                    tokens.append(contentsOf: convertTokens(from: currentToken))
                    currentToken = ""
                }
                inComment = true
            } else if c == "}" {
                guard inComment else {
                    throw Error.unpairedCommentDelimiter
                }
                tokens.append(.comment(currentToken.trimmingCharacters(in: .whitespaces)))
                currentToken = ""
                inComment = false
            } else if inComment {
                currentToken.append(c)
            } else if c == "(" {
                if !currentToken.isEmpty {
                    tokens.append(contentsOf: convertTokens(from: currentToken))
                    currentToken = ""
                }
                tokens.append(.variationStart)
            } else if c == ")" {
                if !currentToken.isEmpty {
                    tokens.append(contentsOf: convertTokens(from: currentToken))
                    currentToken = ""
                }
                tokens.append(.variationEnd)
            } else if c.isWhitespace {
                if !currentToken.isEmpty {
                    tokens.append(contentsOf: convertTokens(from: currentToken))
                    currentToken = ""
                }
            } else {
                currentToken.append(c)
            }
        }

        if inComment {
            throw Error.unpairedCommentDelimiter
        }

        if !currentToken.isEmpty {
            tokens.append(contentsOf: convertTokens(from: currentToken))
        }

        if let resultToken {
            tokens.append(resultToken)
        }

        return tokens
    }

    private static func isGameResult(_ text: String) -> Bool {
        ["1-0", "0-1", "1/2-1/2", "*", "½-½"].contains(text)
    }

    private static func convertTokens(from raw: String) -> [Token] {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }

        if isGameResult(text) {
            return [.result(text)]
        }

        // Handle attached move numbers like "1.e4", "1...e5", "57.Rxc7", "1.0-0"
        if let match = firstMatchGroups(in: text, pattern: #"^(\d+\.{1,3})(.*)$"#), match.count == 2 {
            let numberPart = match[0]
            let remainder = match[1]
            if remainder.isEmpty {
                return [.number(numberPart)]
            } else {
                return [.number(numberPart)] + convertTokens(from: remainder)
            }
        }

        // Ignore standalone en passant annotations e.g. "e.p.", "ep"
        let lower = text.lowercased()
        if lower == "e.p." || lower == "ep" {
            return []
        }

        // Strip ep suffix e.g. "exd6ep" -> "exd6"
        if lower.hasSuffix("e.p.") && text.count > 4 {
            text = String(text.dropLast(4))
        } else if lower.hasSuffix("ep") && text.count > 3 {
            text = String(text.dropLast(2))
        }

        if text.hasPrefix("$") || text.hasPrefix("!") || text.hasPrefix("?") || text == "□" {
            return [.annotation(text)]
        }

        // Check for attached annotation suffixes like "Nf3!", "Nc6?", "Bb5!?", "Nf3+-", "Qd4="
        let suffixes = ["!!", "??", "!?", "?!", "!", "?", "□", "+-", "-+", "=+", "+/=", "+/-", "-+/=", "~=", "⩲", "⩱", "±", "∓", "⨁", "∞", "="]
        for suffix in suffixes {
            if text.hasSuffix(suffix) && text.count > suffix.count {
                let sanPart = String(text.dropLast(suffix.count))
                return [.san(sanPart), .annotation(suffix)]
            }
        }

        return [.san(text)]
    }

    private static func firstMatchGroups(in string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            groups.append(nsString.substring(with: match.range(at: i)))
        }
        return groups
    }

    private static func parseMoveText(
        _ moveText: String,
        startingPosition: Position,
        tags: Game.Tags
    ) throws -> ParsedPGN {
        let tokens = try tokenize(moveText: moveText)
        var game = Game(startingWith: startingPosition, tags: tags)

        guard !tokens.isEmpty else { return ParsedPGN(game: game, fens: [:]) }

        var currentMoveIndex = startingPosition.sideToMove == .white ? MoveTree.Index.minimum : MoveTree.Index.minimum.next
        var positionsByIndex: [MoveTree.Index: Position] = [currentMoveIndex: startingPosition]
        var fensByIndex: [MoveTree.Index: String] = [currentMoveIndex: tags.fen.isEmpty ? startingPosition.fen : tags.fen]
        var variationStack: [MoveTree.Index] = []

        var iterator = tokens.makeIterator()

        while let token = iterator.next() {
            switch token {
            case .number, .result:
                break

            case let .san(san):
                guard let currentPosition = positionsByIndex[currentMoveIndex] else {
                    throw Error.invalidMove(san)
                }
                let currentFEN = fensByIndex[currentMoveIndex] ?? currentPosition.fen

                if san.hasPrefix("O-O") || san.hasPrefix("0-0") {
                    let isQueenside = san.hasPrefix("O-O-O") || san.hasPrefix("0-0-0")
                    let side: Chess960.CastlingSide = isQueenside ? .queenside : .kingside
                    let color: PieceColor = (currentPosition.sideToMove == .white) ? .white : .black
                    if let castled = Chess960.performCastle(color: color, side: side, in: currentFEN),
                       let nextPos = Position(fen: castled.resultingFEN) {
                        let isWhite = (currentPosition.sideToMove == .white)
                        let kingRank = isWhite ? 1 : 8
                        let kingPiece = currentPosition.pieces.first { $0.kind == .king && $0.color == currentPosition.sideToMove }
                        let kingStart = kingPiece?.square ?? Square(isQueenside ? "c\(kingRank)" : "g\(kingRank)")
                        let kingEnd = Square(isQueenside ? "c\(kingRank)" : "g\(kingRank)")
                        let template = SANParser.parse(move: isQueenside ? "O-O-O" : "O-O", in: (isWhite ? Position.standard : Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")!))
                        let moveResult = template?.result ?? .move
                        let move = Move(result: moveResult, piece: kingPiece ?? Piece(.king, color: currentPosition.sideToMove, square: kingStart), start: kingStart, end: kingEnd)
                        currentMoveIndex = game.make(move: move, from: currentMoveIndex)
                        positionsByIndex[currentMoveIndex] = nextPos
                        fensByIndex[currentMoveIndex] = castled.resultingFEN
                        continue
                    }
                    if let move = parseSAN(san, in: currentPosition) {
                        var board = Board(position: currentPosition)
                        if let played = board.move(pieceAt: move.start, to: move.end) {
                            currentMoveIndex = game.make(move: played, from: currentMoveIndex)
                            positionsByIndex[currentMoveIndex] = board.position
                            fensByIndex[currentMoveIndex] = board.position.fen
                            continue
                        }
                    }
                    throw Error.invalidMove(san)
                }

                guard let move = parseSAN(san, in: currentPosition) else {
                    throw Error.invalidMove(san)
                }

                var board = Board(position: currentPosition)
                guard var playedMove = board.move(pieceAt: move.start, to: move.end) else {
                    throw Error.invalidMove(san)
                }
                if let promotedPiece = move.promotedPiece {
                    playedMove = board.completePromotion(of: playedMove, to: promotedPiece.kind)
                }
                let nextPos = board.position
                let updatedWithRights = Chess960.updateCastlingRights(
                    in: currentFEN,
                    movingFrom: playedMove.start.notation,
                    movingTo: playedMove.end.notation,
                    movedPieceKind: playedMove.piece.kind.asPieceKind,
                    movedPieceColor: playedMove.piece.color.asPieceColor
                )
                let rightsField = updatedWithRights.split(separator: " ", omittingEmptySubsequences: true)[2]
                var nextFENFields = nextPos.fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                if nextFENFields.count == 6 {
                    nextFENFields[2] = String(rightsField)
                }
                let nextFullFEN = nextFENFields.joined(separator: " ")
                currentMoveIndex = game.make(move: move, from: currentMoveIndex)
                positionsByIndex[currentMoveIndex] = nextPos
                fensByIndex[currentMoveIndex] = nextFullFEN

            case let .annotation(annotation):
                if let rawValue = firstMatch(in: annotation, pattern: #"^\$\d{2,3}$"#),
                   let assessment = Position.Assessment(rawValue: rawValue) {
                    game.annotate(positionAt: currentMoveIndex, assessment: assessment)
                    continue
                }

                var moveAssessment: Move.Assessment?
                if let notation = firstMatch(in: annotation, pattern: #"^[!?□]{1,2}$"#) {
                    moveAssessment = Move.Assessment(notation: notation)
                } else if let rawValue = firstMatch(in: annotation, pattern: #"^\$\d$"#) {
                    moveAssessment = Move.Assessment(rawValue: rawValue)
                }

                if let moveAssessment {
                    game.annotate(moveAt: currentMoveIndex, assessment: moveAssessment)
                }

            case let .comment(comment):
                game.annotate(moveAt: currentMoveIndex, comment: comment)

            case .variationStart:
                variationStack.append(currentMoveIndex)
                currentMoveIndex = currentMoveIndex.previous

            case .variationEnd:
                guard let popped = variationStack.popLast() else {
                    throw Error.unpairedVariationDelimiter
                }
                currentMoveIndex = popped
            }
        }

        return ParsedPGN(game: game, fens: fensByIndex)
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        return nsString.substring(with: match.range)
    }

    /// Whether the move text contains a piece move with an explicit
    /// disambiguator (`Rhxf1`, `Nbd7`, `R1d1`, `Qh4e1`). Upstream `Game(pgn:)`
    /// must not be trusted for these games: it silently drops the
    /// disambiguator on captures and moves the wrong piece, or rejects the
    /// token outright, so route the whole game through the compatibility
    /// parser instead of waiting for it to throw.
    public static func requiresFallback(for pgn: String) -> Bool {
        let moveTextLines = pgn.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
        let pattern = #"[PNBRQK][a-h1-8]{1,2}x?[a-h][1-8]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        for line in moveTextLines {
            let nsString = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                // The match must start at a token boundary so tag values and
                // ordinary SAN such as "e4" or "exd5" never qualify.
                let loc = match.range.location
                if loc > 0 {
                    let prev = nsString.substring(with: NSRange(location: loc - 1, length: 1))
                    let isBoundary = prev.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                        || prev == "." || prev == "(" || prev == ")"
                    if !isBoundary {
                        continue
                    }
                }
                return true
            }
        }
        return false
    }

    public static func parseSAN(_ san: String, in position: Position) -> Move? {
        var normalizedSAN = san
            .replacingOccurrences(of: "0-0-0", with: "O-O-O")
            .replacingOccurrences(of: "0-0", with: "O-O")
            .replacingOccurrences(of: "++", with: "+")
            .replacingOccurrences(of: "(Q)", with: "=Q")
            .replacingOccurrences(of: "(R)", with: "=R")
            .replacingOccurrences(of: "(B)", with: "=B")
            .replacingOccurrences(of: "(N)", with: "=N")
            .replacingOccurrences(of: "/Q", with: "=Q")
            .replacingOccurrences(of: "/R", with: "=R")
            .replacingOccurrences(of: "/B", with: "=B")
            .replacingOccurrences(of: "/N", with: "=N")

        // Handle promotion without equals e.g. "e8Q", "exd8N"
        if let groups = firstMatchGroups(in: normalizedSAN, pattern: #"^[a-h](?:x[a-h])?[18]([QRBNqrbn])(?:\+|#)?$"#),
           let pieceChar = groups.first {
            if !normalizedSAN.contains("=") {
                if let pieceRange = normalizedSAN.range(of: pieceChar, options: .backwards) {
                    normalizedSAN.replaceSubrange(pieceRange, with: "=\(pieceChar.uppercased())")
                }
            }
        }

        let clean = normalizedSAN.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")

        // Resolve explicitly disambiguated piece moves that upstream SANParser
        // mishandles: it silently drops the disambiguator on captures ("Rhxf1"
        // moves the wrong rook) and rejects rank/square disambiguation outright.
        // Token shape: <piece> [disambiguator] ["x"] <destination square>.
        if let firstChar = clean.first, let pieceKind = Piece.Kind(rawValue: String(firstChar)), clean.count >= 3,
            let end = square(from: String(clean.suffix(2))) {
            let prefix = clean.dropFirst().dropLast(2)
            var disambigStr = String(prefix)
            if disambigStr.hasSuffix("x") {
                disambigStr.removeLast()
            }

            if !disambigStr.isEmpty, let disambiguation = disambiguation(from: disambigStr) {
                let color = position.sideToMove
                let board = Board(position: position)
                let candidates = position.pieces.filter {
                    $0.kind == pieceKind && $0.color == color && board.canMove(pieceAt: $0.square, to: end)
                }
                .filter { piece in
                    switch disambiguation {
                    case let .byFile(file):
                        return piece.square.file == file
                    case let .byRank(rank):
                        return piece.square.rank == rank
                    case let .bySquare(sq):
                        return piece.square == sq
                    }
                }

                // Require exactly one legal source candidate after applying the SAN disambiguator
                guard candidates.count == 1, let candidate = candidates.first else {
                    return nil
                }

                var playBoard = Board(position: position)
                return playBoard.move(pieceAt: candidate.square, to: end)
            }
        }

        // En passant: a pawn capture onto an empty square. Upstream cannot
        // resolve this during replay because replayed positions carry no en
        // passant state (Game.make bypasses Board's en-passant bookkeeping),
        // so build the capture manually from board geometry.
        if let firstChar = clean.first, firstChar.isLowercase,
            Square.File(rawValue: String(firstChar)) != nil,
            let xIdx = clean.firstIndex(of: "x") {
            let afterX = clean.index(after: xIdx)
            let destNotation = String(clean.suffix(2))
            if let end = square(from: destNotation), clean.distance(from: afterX, to: clean.endIndex) == 2 {
                let srcFile = Square.File(rawValue: String(firstChar))!
                let color = position.sideToMove
                let victimRankOffset = color == .white ? -1 : 1
                let landingRank = color == .white ? 6 : 3
                if end.rank.value == landingRank,
                    let srcSquare = square(from: "\(srcFile.rawValue)\(end.rank.value + victimRankOffset)"),
                    let victimSquare = square(from: "\(end.file.rawValue)\(end.rank.value + victimRankOffset)"),
                    position.piece(at: end) == nil,
                    var pawn = position.piece(at: srcSquare), pawn.kind == .pawn, pawn.color == color,
                    let victim = position.piece(at: victimSquare), victim.kind == .pawn, victim.color != color {
                    pawn.square = end
                    return Move(result: .capture(victim), piece: pawn, start: srcSquare, end: end, checkState: .none)
                }
            }
        }

        // For all other tokens, delegate to upstream SANParser with normalized
        // SAN; retry without check/mate suffixes because upstream's patterns
        // reject them on some shapes (castling in particular: "O-O-O+").
        return SANParser.parse(move: normalizedSAN, in: position)
            ?? (normalizedSAN != clean ? SANParser.parse(move: clean, in: position) : nil)
    }

    /// Strict square parser. `Square(_ notation:)` clamps invalid input
    /// instead of failing, so malformed tokens must be rejected here first.
    private static func square(from notation: String) -> Square? {
        guard notation.count == 2,
            let fileChar = notation.first, ("a"..."h").contains(fileChar),
            let rankChar = notation.last, ("1"..."8").contains(rankChar) else {
            return nil
        }
        return Square(notation)
    }

    private static func disambiguation(from str: String) -> Move.Disambiguation? {
        if str.count == 2, let sq = square(from: str) {
            return .bySquare(sq)
        }
        if str.count == 1, let char = str.first {
            if ("a"..."h").contains(char), let file = Square.File(rawValue: str) {
                return .byFile(file)
            }
            if ("1"..."8").contains(char), let rankNum = Int(str) {
                return .byRank(Square.Rank(rankNum))
            }
        }
        return nil
    }
}
