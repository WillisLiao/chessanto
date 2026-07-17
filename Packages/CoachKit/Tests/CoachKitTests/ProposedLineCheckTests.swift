import ChessCore
import Testing

@testable import CoachKit

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

/// A real mid-game black-to-move position (Italian Game after
/// 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3), derived by replaying real moves
/// rather than hand-typing a FEN, so legality claims below are guaranteed
/// correct: black's g8-knight and c8-bishop haven't moved, so O-O is
/// blocked (g8 occupied) and no black knight can reach e4.
private func midGameBlackToMoveFEN() -> String {
    var game = ChessGame()
    var index = game.startIndex
    for san in ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3"] {
        index = game.playMove(san: san, at: index)!
    }
    return game.fen(at: index)!
}

/// The classic Scholar's-Mate-shape position where Qxf7 delivers
/// checkmate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? (Black ignores the threat).
private func qxf7MateFEN() -> String {
    var game = ChessGame()
    var index = game.startIndex
    for san in ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6"] {
        index = game.playMove(san: san, at: index)!
    }
    return game.fen(at: index)!
}

@Suite
struct ProposedLineCheckTests {

    // MARK: - Tokenizer exposure (fact 4's table, verbatim)

    @Test func moveTokenChainsExtractsSimplePieceMoves() {
        #expect(CoachVerifier.moveTokenChains(in: "what about Nf3?").map(\.tokens) == [["Nf3"]])
        #expect(CoachVerifier.moveTokenChains(in: "What if I played e4?").map(\.tokens) == [["e4"]])
        #expect(CoachVerifier.moveTokenChains(in: "should I castle O-O here?").map(\.tokens) == [["O-O"]])
    }

    @Test func moveTokenChainsExtractsTwoSeparateChains() {
        let chains = CoachVerifier.moveTokenChains(in: "what about Nf3 or Bc4?")
        #expect(chains.map(\.tokens) == [["Nf3"], ["Bc4"]])
    }

    @Test func moveTokenChainsStripsAnnotationSuffixes() {
        #expect(CoachVerifier.moveTokenChains(in: "why not Qxg5??").map(\.tokens) == [["Qxg5"]])
    }

    @Test func moveTokenChainsExtractsUCI() {
        #expect(CoachVerifier.moveTokenChains(in: "is e2e4 good here?").map(\.tokens) == [["e2e4"]])
    }

    @Test func moveTokenChainsExtractsPromotion() {
        #expect(CoachVerifier.moveTokenChains(in: "can I promote with e8=Q?").map(\.tokens) == [["e8=Q"]])
    }

    @Test func moveTokenChainsExtractsNothingFromOpenQuestion() {
        #expect(CoachVerifier.moveTokenChains(in: "how do I attack here?").isEmpty)
    }

    @Test func moveTokenChainsExtractsNothingFromLowercasePieceLetter() {
        #expect(CoachVerifier.moveTokenChains(in: "what about nf3?").isEmpty)
    }

    @Test func moveTokenChainsFlagsBareSquareTrap() {
        let takeOnD5 = CoachVerifier.moveTokenChains(in: "what if I take on d5?")
        #expect(takeOnD5.map(\.tokens) == [["d5"]])
        #expect(takeOnD5[0].isBareSquareToken)

        let knightOnC6 = CoachVerifier.moveTokenChains(in: "the knight on c6 looks strong")
        #expect(knightOnC6.map(\.tokens) == [["c6"]])
        #expect(knightOnC6[0].isBareSquareToken)
    }

    @Test func moveTokenChainsFlagsNumberedMoveAsHistoryReference() {
        let chains = CoachVerifier.moveTokenChains(in: "was 24...Qd7 really a blunder?")
        #expect(chains.map(\.tokens) == [["Qd7"]])
        #expect(chains[0].hasLeadingNumberMarker)
        #expect(!chains[0].isBareSquareToken)
    }

    // MARK: - Precheck classification: the three buckets

    @Test func classifyRoutesBareSquareToSquareReferenceRegardlessOfLegality() {
        let chain = CoachVerifier.moveTokenChains(in: "what if I take on d5?")[0]
        // d5 is a legal pawn move from the start position - still a square
        // reference, never a proposal (TRAP 1).
        #expect(ProposedLineCheck.classify(chain: chain, currentFEN: startFEN) == .squareReference)
    }

    @Test func classifyRoutesIllegalBareSquareToSquareReferenceToo() {
        let chain = CoachVerifier.moveTokenChains(in: "the knight on c6 looks strong")[0]
        // c6 is illegal as a pawn move from the start position - still a
        // square reference, must not short-circuit as illegal (TRAP 1).
        #expect(ProposedLineCheck.classify(chain: chain, currentFEN: startFEN) == .squareReference)
    }

    @Test func classifyRoutesNumberedMoveToHistoryReference() {
        let fen = midGameBlackToMoveFEN()
        let chain = CoachVerifier.moveTokenChains(in: "was 24...Qd7 really a blunder?")[0]
        #expect(ProposedLineCheck.classify(chain: chain, currentFEN: fen) == .historyReference)
    }

    @Test func classifyAcceptsLegalProposalsFromMidGamePosition() {
        // Single-square SAN (d6, a6) is indistinguishable from a bare square
        // reference (TRAP 1) and is always routed to .squareReference, even
        // when it happens to be a legal pawn move - so legal-proposal
        // coverage here uses multi-character SAN only.
        let fen = midGameBlackToMoveFEN()
        for san in ["Nd4", "Bb6", "Nf6", "Qe7"] {
            let chain = CoachVerifier.moveTokenChains(in: "what about \(san)?")[0]
            guard case .legalProposal = ProposedLineCheck.classify(chain: chain, currentFEN: fen) else {
                Issue.record("expected \(san) to be a legal proposal from the mid-game position")
                continue
            }
        }
    }

    @Test func classifyRejectsIllegalProposalsFromMidGamePosition() {
        let fen = midGameBlackToMoveFEN()
        for san in ["Nf3", "O-O", "Nxe4"] {
            let chain = CoachVerifier.moveTokenChains(in: "what about \(san)?")[0]
            guard case .illegalProposal = ProposedLineCheck.classify(chain: chain, currentFEN: fen) else {
                Issue.record("expected \(san) to be an illegal proposal from the mid-game position")
                continue
            }
        }
    }

    @Test func classifyAcceptsMultiMoveChain() {
        let fen = midGameBlackToMoveFEN()
        let chain = CoachVerifier.moveTokenChains(in: "what about Bb6 O-O d6?")[0]
        #expect(chain.tokens == ["Bb6", "O-O", "d6"])
        guard case .legalProposal(let uci) = ProposedLineCheck.classify(chain: chain, currentFEN: fen) else {
            Issue.record("expected a 3-ply legal proposal")
            return
        }
        #expect(uci.count == 3)
    }

    @Test func classifyAcceptsCheckmateProposalWithSuffixToleranceAndSuppliesCorrectSAN() {
        let fen = qxf7MateFEN()
        for question in ["is Qxf7 mate?", "is Qxf7# mate?", "is h5f7 mate?"] {
            let chain = CoachVerifier.moveTokenChains(in: question)[0]
            guard case .legalProposal(let uci) = ProposedLineCheck.classify(chain: chain, currentFEN: fen) else {
                Issue.record("expected \(question) to be a legal proposal")
                continue
            }
            let replay = ChessGame.replayLine(fromUCI: uci, startingFEN: fen)
            #expect(replay.count == 1)
            #expect(replay[0].san == "Qxf7#")
            #expect(replay[0].isCheckmate)
            #expect(!replay[0].isCheck)
        }
    }

    // MARK: - Existing verifier behavior is untouched

    @Test func verifierStillExemptsUnnumberedBareSquaresFromVerification() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "The knight on c6 is strong.", context: context)
        #expect(verdict == .verified("The knight on c6 is strong."))
    }

    @Test func verifierStillRejectsNumberedBareSquareThatIsIllegal() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "1. e5", context: context)
        guard case .violations = verdict else {
            Issue.record("expected 1. e5 (illegal from the start position) to be rejected, not exempted")
            return
        }
    }
}
