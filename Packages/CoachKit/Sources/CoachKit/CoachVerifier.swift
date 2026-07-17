import ChessCore
import Foundation

/// Layer 2 of the Verified Coach design (PLAN.md): the hard gate. Parses
/// every generated response, extracts cited move lines and numeric claims,
/// and verifies each mechanically against known-good data. Pure ChessCore,
/// no engine, no network - the one fresh-verification hook takes an
/// `EngineToolExecutor?` and is only exercised when nothing else grounds a
/// cited line. Nothing unverified ever renders.
public enum CoachVerifier {

    // MARK: - Public types

    public struct Violation: Sendable, Equatable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    public enum Verdict: Sendable, Equatable {
        case verified(String)
        case violations([Violation])
    }

    /// One known-good engine line, in the vocabulary shared by `RankedLine`
    /// and `EngineToolResult`.
    public struct VerifiedLine: Sendable {
        public let scoreCentipawnsWhitePerspective: Int?
        public let mateInWhitePerspective: Int?
        public let principalVariationUCI: [String]

        public init(scoreCentipawnsWhitePerspective: Int?, mateInWhitePerspective: Int?, principalVariationUCI: [String]) {
            self.scoreCentipawnsWhitePerspective = scoreCentipawnsWhitePerspective
            self.mateInWhitePerspective = mateInWhitePerspective
            self.principalVariationUCI = principalVariationUCI
        }
    }

    /// One position a cited line may legally be replayed from: the moment's
    /// pre-move FEN, its post-move FEN, or (added as the tool loop runs) a
    /// fresh `EngineToolResult`'s resulting FEN.
    public struct Anchor: Sendable {
        public let fen: String
        public let lines: [VerifiedLine]

        public init(fen: String, lines: [VerifiedLine]) {
            self.fen = fen
            self.lines = lines
        }
    }

    /// Everything the verifier is allowed to trust for one response.
    public struct Context: Sendable {
        public var anchors: [Anchor]
        /// Every eval a numeric claim may match (payload pre/post-move
        /// evals, every anchor line's eval, every tool-result eval), in
        /// centipawns.
        public var knownEvalsCentipawns: [Int]
        public var knownMates: [Int]
        /// Every win-probability a percentage claim may match, already
        /// rounded to whole points the way `ReportText`/the payload render
        /// them.
        public var knownWinProbabilities: [Double]
        public var engineExecutor: EngineToolExecutor?

        public init(
            anchors: [Anchor],
            knownEvalsCentipawns: [Int] = [],
            knownMates: [Int] = [],
            knownWinProbabilities: [Double] = [],
            engineExecutor: EngineToolExecutor? = nil
        ) {
            self.anchors = anchors
            self.knownEvalsCentipawns = knownEvalsCentipawns
            self.knownMates = knownMates
            self.knownWinProbabilities = knownWinProbabilities
            self.engineExecutor = engineExecutor
        }
    }

    // MARK: - Verification

    public static func verify(text: String, context: Context) async -> Verdict {
        var violations: [Violation] = []
        var mutableContext = context
        var freshVerificationUsed = false

        for chain in citedLineChains(in: text) {
            if chain.tokens.count == 1, chain.isExemptBareSquare {
                continue
            }
            await verify(chain: chain, context: &mutableContext, freshVerificationUsed: &freshVerificationUsed, violations: &violations)
        }

        for violation in numericClaimViolations(in: text, context: mutableContext) {
            violations.append(violation)
        }

        if violations.isEmpty {
            return .verified(text)
        }
        return .violations(violations)
    }

    private static func verify(
        chain: TokenChain,
        context: inout Context,
        freshVerificationUsed: inout Bool,
        violations: inout [Violation]
    ) async {
        let rawTokens = chain.tokens.map(\.text)
        var legalSomewhere: (anchor: Anchor, uci: [String], replay: [ReplayedMove])?

        for anchor in context.anchors {
            guard let uci = legalUCILine(tokens: rawTokens, startingFEN: anchor.fen) else { continue }
            let replay = ChessGame.replayLine(fromUCI: uci, startingFEN: anchor.fen)
            guard replay.count == uci.count else { continue }
            if legalSomewhere == nil {
                legalSomewhere = (anchor, uci, replay)
            }
            if let matchedLine = anchor.lines.first(where: { $0.principalVariationUCI.starts(with: uci) }) {
                checkSuffixClaim(chain: chain, replay: replay, violations: &violations)
                appendEvalSource(matchedLine, context: &context)
                return
            }
            // Landing exactly on another known anchor's position (e.g. the
            // actual played move reaching the moment's post-move FEN) is
            // just as strong a grounding signal as a stored PV match - the
            // position itself is independently verified.
            if let landedAnchor = context.anchors.first(where: { $0.fen == replay.last?.resultingFEN }) {
                checkSuffixClaim(chain: chain, replay: replay, violations: &violations)
                if let rank1 = landedAnchor.lines.first {
                    appendEvalSource(rank1, context: &context)
                }
                return
            }
        }

        guard let legalSomewhere else {
            violations.append(Violation("cited line \"\(rawTokens.joined(separator: " "))\" is not a legal sequence of moves in any known position"))
            return
        }

        // Not a prefix of any known line - try fresh verification once.
        if !freshVerificationUsed, let executor = context.engineExecutor {
            freshVerificationUsed = true
            do {
                let result = try await executor.evaluate(fen: legalSomewhere.anchor.fen, movesUCI: legalSomewhere.uci)
                checkSuffixClaim(chain: chain, replay: legalSomewhere.replay, violations: &violations)
                context.anchors.append(Anchor(fen: result.resultingFEN, lines: [
                    VerifiedLine(
                        scoreCentipawnsWhitePerspective: result.scoreCentipawnsWhitePerspective,
                        mateInWhitePerspective: result.mateInWhitePerspective,
                        principalVariationUCI: result.principalVariationUCI
                    )
                ]))
                if let cp = result.scoreCentipawnsWhitePerspective {
                    context.knownEvalsCentipawns.append(cp)
                }
                if let mate = result.mateInWhitePerspective {
                    context.knownMates.append(mate)
                }
                return
            } catch {
                violations.append(Violation("cited line \"\(rawTokens.joined(separator: " "))\" could not be freshly verified: \(error)"))
                return
            }
        }

        violations.append(Violation("cited line \"\(rawTokens.joined(separator: " "))\" does not appear in the engine data for this position"))
    }

    private static func appendEvalSource(_ line: VerifiedLine, context: inout Context) {
        if let cp = line.scoreCentipawnsWhitePerspective {
            context.knownEvalsCentipawns.append(cp)
        }
        if let mate = line.mateInWhitePerspective {
            context.knownMates.append(mate)
        }
    }

    private static func checkSuffixClaim(chain: TokenChain, replay: [ReplayedMove], violations: inout [Violation]) {
        guard chain.tokens.count == replay.count else { return }
        for (token, move) in zip(chain.tokens, replay) {
            switch token.suffix {
            case "#":
                if !move.isCheckmate {
                    violations.append(Violation("\"\(token.text)\" claims checkmate but \(move.san) is not checkmate"))
                }
            case "+":
                if !move.isCheck {
                    violations.append(Violation("\"\(token.text)\" claims check but \(move.san) is \(move.isCheckmate ? "checkmate, not a plain check" : "not a check")"))
                }
            default:
                break
            }
        }
    }

    // MARK: - Legality replay (fact 15: SAN path for legality + UCI extraction only)

    static func legalUCILine(tokens: [String], startingFEN fen: String) -> [String]? {
        var game = ChessGame(startingFEN: fen)
        var index = game.startIndex
        var uci: [String] = []
        for token in tokens {
            let stripped = strippingDecorations(token)
            let newIndex: MoveIndex?
            if let uciMove = parseUCIToken(stripped) {
                newIndex = game.playMove(from: uciMove.from, to: uciMove.to, at: index, promotion: uciMove.promotion ?? .queen)
            } else {
                newIndex = game.playMove(san: stripped, at: index)
            }
            guard let newIndex, let detail = game.moveDetail(at: newIndex) else { return nil }
            uci.append(detail.uci)
            index = newIndex
        }
        return uci
    }

    private static func strippingDecorations(_ token: String) -> String {
        var result = token
        while let last = result.last, "+#!?".contains(last) {
            result.removeLast()
        }
        return result
    }

    private struct ParsedUCIMove {
        let from: SquareCoordinate
        let to: SquareCoordinate
        let promotion: PromotionKind?
    }

    private static func parseUCIToken(_ token: String) -> ParsedUCIMove? {
        let chars = Array(token)
        guard chars.count == 4 || chars.count == 5,
            ("a"..."h").contains(chars[0]), ("1"..."8").contains(chars[1]),
            ("a"..."h").contains(chars[2]), ("1"..."8").contains(chars[3])
        else { return nil }
        let from = SquareCoordinate(notation: String(chars[0...1]))
        let to = SquareCoordinate(notation: String(chars[2...3]))
        var promotion: PromotionKind?
        if chars.count == 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        }
        return ParsedUCIMove(from: from, to: to, promotion: promotion)
    }

    // MARK: - Numeric claims

    private static func numericClaimViolations(in text: String, context: Context) -> [Violation] {
        var violations: [Violation] = []

        for match in matches(of: evalPattern, in: text) {
            let raw = String(text[match])
            guard let pawns = Double(raw) else { continue }
            let cp = Int((pawns * 100).rounded())
            if !context.knownEvalsCentipawns.contains(where: { abs($0 - cp) <= 50 }) {
                violations.append(Violation("eval claim \"\(raw)\" does not match any verified eval"))
            }
        }

        for match in matches(of: matePattern, in: text) {
            let raw = String(text[match])
            let digits = raw.filter(\.isNumber)
            guard let n = Int(digits) else { continue }
            let signed = raw.hasPrefix("-") ? -n : n
            if !context.knownMates.contains(signed) && !context.knownMates.contains(-signed) {
                violations.append(Violation("mate claim \"\(raw)\" does not match any verified mate count"))
            }
        }

        for match in matches(of: mateInWordsPattern, in: text) {
            let raw = String(text[match])
            let digits = raw.filter(\.isNumber)
            guard let n = Int(digits) else { continue }
            if !context.knownMates.contains(n) && !context.knownMates.contains(-n) {
                violations.append(Violation("\"\(raw)\" does not match any verified mate count"))
            }
        }

        for match in matches(of: percentPattern, in: text) {
            let raw = String(text[match])
            guard let value = Double(raw.dropLast()) else { continue }
            if !context.knownWinProbabilities.contains(where: { abs($0 - value) <= 2 }) {
                violations.append(Violation("percentage claim \"\(raw)\" does not match any verified win probability"))
            }
        }

        return violations
    }

    // MARK: - Tokenization

    private struct MoveToken {
        let text: String
        let range: Range<String.Index>
        let suffix: Character?
    }

    private struct TokenChain {
        let tokens: [MoveToken]
        let hasLeadingNumberMarker: Bool

        /// True for any single bare-square token chain, numbered or not.
        /// Used by the chat precheck (TRAP 1: "what about c4?" reads like a
        /// pawn move but is usually a square reference).
        var isBareSquareToken: Bool {
            guard let only = tokens.first, tokens.count == 1 else { return false }
            return only.suffix == nil && bareSquarePattern.firstMatch(in: only.text, range: NSRange(only.text.startIndex..., in: only.text)) != nil
                && only.text.count == 2
        }

        /// True only for an *unnumbered* bare square: `verify()`'s own,
        /// narrower exemption from post-generation checking.
        var isExemptBareSquare: Bool {
            isBareSquareToken && !hasLeadingNumberMarker
        }
    }

    private static let sanPattern = try! NSRegularExpression(
        pattern: #"\b(?:O-O-O|O-O|0-0-0|0-0|[KQRBN][a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?|[a-h]x[a-h][1-8](?:=[QRBN])?|[a-h][1-8](?:=[QRBN])?)[+#]?\b"#
    )
    private static let uciPattern = try! NSRegularExpression(pattern: #"\b[a-h][1-8][a-h][1-8][qrbn]?\b"#)
    private static let numberMarkerPattern = try! NSRegularExpression(pattern: #"\d+(?:\.\.\.|\.)"#)
    private static let numberMarkerAtEndPattern = try! NSRegularExpression(pattern: #"\d+(?:\.\.\.|\.)\s*$"#)
    private static let bareSquarePattern = try! NSRegularExpression(pattern: #"^[a-h][1-8]$"#)
    private static let evalPattern = try! NSRegularExpression(pattern: #"[+-]?\d+\.\d+"#)
    private static let matePattern = try! NSRegularExpression(pattern: #"-?M\d+"#)
    private static let mateInWordsPattern = try! NSRegularExpression(pattern: #"mate in \d+"#, options: [.caseInsensitive])
    private static let percentPattern = try! NSRegularExpression(pattern: #"\d+%"#)

    private static func matches(of regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        let nsrange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsrange).compactMap { Range($0.range, in: text) }
    }

    private static func citedLineChains(in text: String) -> [TokenChain] {
        var ranges: [(range: Range<String.Index>, isUCI: Bool)] = []
        for range in matches(of: uciPattern, in: text) {
            ranges.append((range, true))
        }
        let uciRanges = Set(ranges.map { $0.range })
        for range in matches(of: sanPattern, in: text) {
            guard !uciRanges.contains(where: { $0.overlaps(range) }) else { continue }
            ranges.append((range, false))
        }
        ranges.sort { $0.range.lowerBound < $1.range.lowerBound }

        // The pattern's trailing `\b` can never actually match with a
        // `+`/`#` suffix in real prose: both are non-word characters, and
        // `\b` needs a word-character transition, so whatever follows the
        // suffix in real text (space, comma, `)`, `.`) is never a boundary.
        // The engine backtracks to excluding the suffix, which then sits
        // unconsumed in the text and breaks chain adjacency between cited
        // moves. Absorb an immediately-following `+`/`#` into the match
        // here rather than relying on the (structurally unsatisfiable)
        // in-pattern capture.
        var tokens: [MoveToken] = []
        for (range, isUCI) in ranges {
            var extendedRange = range
            var suffix: Character?
            if !isUCI, range.upperBound < text.endIndex {
                let next = text[range.upperBound]
                if next == "+" || next == "#" {
                    extendedRange = range.lowerBound..<text.index(after: range.upperBound)
                    suffix = next
                }
            }
            let raw = String(text[extendedRange])
            tokens.append(MoveToken(text: raw, range: extendedRange, suffix: suffix))
        }

        var chains: [TokenChain] = []
        var current: [MoveToken] = []
        var previousEnd: String.Index?

        func flush() {
            guard !current.isEmpty else { return }
            let leading = hasLeadingNumberMarker(before: current[0], in: text)
            chains.append(TokenChain(tokens: current, hasLeadingNumberMarker: leading))
            current = []
        }

        for token in tokens {
            if let previousEnd {
                let gap = text[previousEnd..<token.range.lowerBound]
                let trimmed = gap.trimmingCharacters(in: .whitespaces)
                let isAdjacent = trimmed.isEmpty || trimmed == ","
                let isNumberMarker = isWholeNumberMarker(trimmed)
                if isAdjacent || isNumberMarker {
                    current.append(token)
                } else {
                    flush()
                    current = [token]
                }
            } else {
                current = [token]
            }
            previousEnd = token.range.upperBound
        }
        flush()
        return chains
    }

    private static func isWholeNumberMarker(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let nsrange = NSRange(s.startIndex..., in: s)
        guard let match = numberMarkerPattern.firstMatch(in: s, range: nsrange) else { return false }
        return Range(match.range, in: s) == s.startIndex..<s.endIndex
    }

    private static func hasLeadingNumberMarker(before token: MoveToken, in text: String) -> Bool {
        let prefix = String(text[text.startIndex..<token.range.lowerBound])
        let nsrange = NSRange(prefix.startIndex..., in: prefix)
        return numberMarkerAtEndPattern.firstMatch(in: prefix, range: nsrange) != nil
    }

    // MARK: - Public tokenizer exposure (M7 chat precheck)

    /// One chain of adjacent move-shaped tokens extracted from free text,
    /// as `verify()` sees it internally, exposed for the chat precheck
    /// (`ProposedLineCheck`) to classify before any LLM call.
    public struct TokenChainInfo: Sendable, Equatable {
        public let tokens: [String]
        /// A single bare-square token ("c4", "d5"), numbered or not - reads
        /// like a pawn move but is usually a square reference (fact 4's
        /// TRAP 1).
        public let isBareSquareToken: Bool
        /// The chain is preceded by a move-number marker ("24...", "12.") -
        /// a reference to a move already played, not a proposal against the
        /// current position (fact 4's TRAP 2).
        public let hasLeadingNumberMarker: Bool
    }

    /// The same chain extraction `verify()` uses internally, exposed
    /// read-only. Behavior of `verify()` itself is unchanged.
    public static func moveTokenChains(in text: String) -> [TokenChainInfo] {
        citedLineChains(in: text).map { chain in
            TokenChainInfo(
                tokens: chain.tokens.map(\.text),
                isBareSquareToken: chain.isBareSquareToken,
                hasLeadingNumberMarker: chain.hasLeadingNumberMarker
            )
        }
    }
}
