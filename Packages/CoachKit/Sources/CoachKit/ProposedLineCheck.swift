import ChessCore

/// Classifies a chat question's cited move chains BEFORE any LLM call, per
/// M7's precheck design decision. Pure ChessCore, executor-free: it
/// determines legal UCI lines or flags an illegal token; the actual engine
/// evaluation (for a legal proposal's cited eval) happens in `CoachChat`.
///
/// Three buckets, in priority order (fact 4's traps):
/// - a single bare-square token ("what about c4?") is a square reference,
///   never a move proposal - TRAP 1;
/// - a chain with a leading move-number marker ("was 24...Qd7 a blunder?")
///   references a move already played, not a proposal against the current
///   position - TRAP 2;
/// - everything else (piece moves, captures, castling, promotions, UCI) is
///   checked as a proposal from the current position, via the same
///   SAN-legality -> UCI-extraction -> `replayLine` re-replay sequence
///   `CoachVerifier` uses to ground cited lines (fact 15).
public enum ProposedLineCheck {
    public enum Classification: Sendable, Equatable {
        case squareReference
        case historyReference
        case legalProposal(uci: [String])
        case illegalProposal(rawTokens: [String])
    }

    public static func classify(chain: CoachVerifier.TokenChainInfo, currentFEN fen: String) -> Classification {
        if chain.isBareSquareToken {
            return .squareReference
        }
        if chain.hasLeadingNumberMarker {
            return .historyReference
        }
        guard let uci = CoachVerifier.legalUCILine(tokens: chain.tokens, startingFEN: fen) else {
            return .illegalProposal(rawTokens: chain.tokens)
        }
        let replay = ChessGame.replayLine(fromUCI: uci, startingFEN: fen)
        guard replay.count == uci.count else {
            return .illegalProposal(rawTokens: chain.tokens)
        }
        return .legalProposal(uci: uci)
    }

    /// Classifies every move-shaped chain in a chat question.
    public static func classify(text: String, currentFEN fen: String) -> [(chain: CoachVerifier.TokenChainInfo, classification: Classification)] {
        CoachVerifier.moveTokenChains(in: text).map { chain in
            (chain, classify(chain: chain, currentFEN: fen))
        }
    }
}
