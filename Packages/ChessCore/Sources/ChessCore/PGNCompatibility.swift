import ChessKit
import Foundation

/// Internal compatibility parser for PGN games.
///
/// Addresses upstream `chesskit-swift` parser limitations, such as
/// disambiguated piece captures (e.g., `Rfxe1`, `Nbxd7+`, `Ra1xe1`),
/// while preserving full compliance with PGN standards including
/// comments, NAGs, annotations, variations, castling, promotions,
/// checks, checkmates, and custom starting positions.
enum PGNCompatibility {

    public enum Error: Swift.Error, Equatable {
        case tooManyLineBreaks
        case invalidSetUpOrFEN
        case invalidTagFormat
        case mismatchedTagBrackets
        case tagStringNotFound
        case tagSymbolNotFound
        case unexpectedTagCharacter(String)
        case invalidAnnotation(String)
        case invalidMove(String)
        case unexpectedMoveTextToken
        case unpairedCommentDelimiter
        case unpairedVariationDelimiter
    }

    private struct MoveDTO: Codable {
        var result: Move.Result
        var piece: Piece
        var start: Square
        var end: Square
        var promotedPiece: Piece?
        var disambiguation: Move.Disambiguation?
        var checkState: Move.CheckState
        var assessment: Move.Assessment
        var comment: String
    }

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    private static func createMove(
        result: Move.Result,
        piece: Piece,
        start: Square,
        end: Square,
        promotedPiece: Piece? = nil,
        disambiguation: Move.Disambiguation? = nil,
        checkState: Move.CheckState = .none,
        assessment: Move.Assessment = .null,
        comment: String = ""
    ) -> Move {
        if disambiguation == nil && promotedPiece == nil {
            return Move(
                result: result,
                piece: piece,
                start: start,
                end: end,
                checkState: checkState,
                assessment: assessment,
                comment: comment
            )
        }

        let dto = MoveDTO(
            result: result,
            piece: piece,
            start: start,
            end: end,
            promotedPiece: promotedPiece,
            disambiguation: disambiguation,
            checkState: checkState,
            assessment: assessment,
            comment: comment
        )

        if let data = try? jsonEncoder.encode(dto),
           let move = try? jsonDecoder.decode(Move.self, from: data) {
            return move
        }

        return Move(
            result: result,
            piece: piece,
            start: start,
            end: end,
            checkState: checkState,
            assessment: assessment,
            comment: comment
        )
    }

    public static func parse(pgn: String) throws -> Game {
        let lines = pgn.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("%") }

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
        if tags.setUp == "1" {
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
                if !inComment {
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
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }

        if isGameResult(text) {
            return [.result(text)]
        }

        if text.hasPrefix("$") || text.hasPrefix("!") || text.hasPrefix("?") || text == "□" {
            return [.annotation(text)]
        }

        if let first = text.first, first.isWholeNumber {
            if text.contains(".") {
                return [.number(text)]
            }
        }

        // Check for attached annotation suffixes like "Nf3!", "Nc6?", "Bb5!?"
        let suffixes = ["!!", "??", "!?", "?!", "!", "?", "□"]
        for suffix in suffixes {
            if text.hasSuffix(suffix) && text.count > suffix.count {
                let sanPart = String(text.dropLast(suffix.count))
                return [.san(sanPart), .annotation(suffix)]
            }
        }

        return [.san(text)]
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
        let clean = san.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")

        if let firstChar = clean.first, let pieceKind = Piece.Kind(rawValue: String(firstChar)) {
            let body = clean.dropFirst()
            let isCapture = body.contains("x")

            if let end = extractTargetSquare(from: clean) {
                let endStr = end.notation
                var disambigStr = ""
                if isCapture {
                    if let xIdx = body.firstIndex(of: "x") {
                        disambigStr = String(body[body.startIndex..<xIdx])
                    }
                } else if let endRange = body.range(of: endStr, options: .backwards) {
                    disambigStr = String(body[body.startIndex..<endRange.lowerBound])
                }

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

                        if let piece = candidates.first {
                            let checkState: Move.CheckState = san.contains("#") ? .checkmate : (san.contains("+") ? .check : .none)
                            let result: Move.Result
                            if isCapture {
                                if let captured = position.piece(at: end) {
                                    result = .capture(captured)
                                } else {
                                    return nil
                                }
                            } else {
                                result = .move
                            }

                            return createMove(
                                result: result,
                                piece: piece,
                                start: piece.square,
                                end: end,
                                disambiguation: disambiguation,
                                checkState: checkState
                            )
                        }
                    }
                }
            }
        }

        return SANParser.parse(move: san, in: position)
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
