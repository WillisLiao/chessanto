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

    public static func parse(pgn: String) throws -> Game {
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
    ) throws -> Game {
        let tokens = try tokenize(moveText: moveText)
        var game = Game(startingWith: startingPosition, tags: tags)

        guard !tokens.isEmpty else { return game }

        var currentMoveIndex = startingPosition.sideToMove == .white ? MoveTree.Index.minimum : MoveTree.Index.minimum.next
        var variationStack: [MoveTree.Index] = []

        var iterator = tokens.makeIterator()

        while let token = iterator.next() {
            switch token {
            case .number, .result:
                break

            case let .san(san):
                guard let position = game.positions[currentMoveIndex] else {
                    throw Error.invalidMove(san)
                }

                guard let move = parseSAN(san, in: position) else {
                    throw Error.invalidMove(san)
                }

                currentMoveIndex = game.make(move: move, from: currentMoveIndex)

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

        return game
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        return nsString.substring(with: match.range)
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

        // Resolve disambiguated piece-capture tokens that upstream SANParser drops:
        if let firstChar = clean.first, let pieceKind = Piece.Kind(rawValue: String(firstChar)) {
            let body = clean.dropFirst()
            if body.contains("x"), let end = extractTargetSquare(from: clean) {
                if let xIdx = body.firstIndex(of: "x") {
                    let disambigStr = String(body[body.startIndex..<xIdx])
                    if !disambigStr.isEmpty {
                        var disambiguation: Move.Disambiguation?
                        if disambigStr.count == 2 {
                            let sq = Square(disambigStr)
                            disambiguation = .bySquare(sq)
                        } else if disambigStr.count == 1 {
                            let char = disambigStr.first!
                            if ("a"..."h").contains(char), let file = Square.File(rawValue: disambigStr) {
                                disambiguation = .byFile(file)
                            } else if ("1"..."8").contains(char), let rankNum = Int(disambigStr) {
                                disambiguation = .byRank(Square.Rank(rankNum))
                            }
                        }

                        if let disambiguation {
                            let color = position.sideToMove
                            let board = Board(position: position)
                            let matchingPieces = position.pieces.filter {
                                $0.kind == pieceKind && $0.color == color && board.canMove(pieceAt: $0.square, to: end)
                            }

                            let candidates = matchingPieces.filter { piece in
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
                }
            }
        }

        // For all other tokens, delegate to upstream SANParser with normalized SAN
        return SANParser.parse(move: normalizedSAN, in: position)
    }

    private static func extractTargetSquare(from cleanSAN: String) -> Square? {
        let pattern = #"([a-h][1-8])(?!=)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = cleanSAN as NSString
        let matches = regex.matches(in: cleanSAN, range: NSRange(location: 0, length: nsString.length))
        guard let lastMatch = matches.last else { return nil }
        let squareStr = nsString.substring(with: lastMatch.range(at: 1))
        return Square(squareStr)
    }
}
