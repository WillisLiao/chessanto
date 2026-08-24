import Testing
@testable import ChessCore

@Suite struct GameEndTests {
    @Test func playMoveUCIAppliesLegalMove() {
        var game = ChessGame()
        let start = game.startIndex
        let afterE4 = game.playMove(uci: "e2e4", at: start)
        #expect(afterE4 != nil)
        #expect(game.san(at: afterE4!) == "e4")
        #expect(game.fen(at: afterE4!) == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")

        let afterE5 = game.playMove(uci: "e7e5", at: afterE4!)
        #expect(afterE5 != nil)
        #expect(game.san(at: afterE5!) == "e5")
    }

    @Test func playMoveUCIHandlesPromotionAndUnderpromotion() {
        var game = ChessGame(startingFEN: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        let start = game.startIndex

        // Underpromotion to knight
        var knightGame = game
        let knightIndex = knightGame.playMove(uci: "a7a8n", at: start)
        #expect(knightIndex != nil)
        #expect(knightGame.san(at: knightIndex!) == "a8=N")

        // Promotion to queen with check
        var queenGame = game
        let queenIndex = queenGame.playMove(uci: "a7a8q", at: start)
        #expect(queenIndex != nil)
        #expect(queenGame.san(at: queenIndex!) == "a8=Q+")

        // Unpromoted pawn to back rank rejected
        var invalidGame = game
        let invalidIndex = invalidGame.playMove(uci: "a7a8", at: start)
        #expect(invalidIndex == nil)
    }

    @Test func playMoveUCIRejectsIllegalMove() {
        var game = ChessGame()
        let start = game.startIndex
        let result = game.playMove(uci: "e2e5", at: start)
        #expect(result == nil)
    }

    @Test func checkmateDetectionForWhiteAndBlack() {
        // Scholar's mate: White wins
        let scholarsMateFEN = "r1bqkb1r/pppp1Qpp/2n5/4p3/2B1n3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
        #expect(ChessGame.isCheck(fen: scholarsMateFEN))
        #expect(ChessGame.isCheckmate(fen: scholarsMateFEN))
        #expect(!ChessGame.isStalemate(fen: scholarsMateFEN))
        #expect(ChessGame.detectOutcome(currentFEN: scholarsMateFEN, historyFENs: [scholarsMateFEN]) == .checkmate(winner: .white))

        // Fool's mate: Black wins (1. f3 e5 2. g4 Qh4#)
        let foolsMateFEN = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
        #expect(ChessGame.isCheck(fen: foolsMateFEN))
        #expect(ChessGame.isCheckmate(fen: foolsMateFEN))
        #expect(!ChessGame.isStalemate(fen: foolsMateFEN))
        #expect(ChessGame.detectOutcome(currentFEN: foolsMateFEN, historyFENs: [foolsMateFEN]) == .checkmate(winner: .black))
    }

    @Test func stalemateDetection() {
        // Classic stalemate position: Black king on a8 has no legal moves, White king on a6, White queen on c7
        let stalemateFEN = "k7/2Q5/K7/8/8/8/8/8 b - - 0 1"
        #expect(!ChessGame.isCheck(fen: stalemateFEN))
        #expect(!ChessGame.isCheckmate(fen: stalemateFEN))
        #expect(ChessGame.isStalemate(fen: stalemateFEN))
        #expect(ChessGame.detectOutcome(currentFEN: stalemateFEN, historyFENs: [stalemateFEN]) == .stalemate)
    }

    @Test func insufficientMaterialDetection() {
        // King vs King
        let kvk = "8/8/8/4k3/8/8/4K3/8 w - - 0 1"
        #expect(ChessGame.hasInsufficientMaterial(fen: kvk))

        // King + Knight vs King
        let knvk = "8/8/8/4k3/8/8/4KN2/8 w - - 0 1"
        #expect(ChessGame.hasInsufficientMaterial(fen: knvk))

        // King + Bishop vs King
        let kbvk = "8/8/8/4k3/8/8/4KB2/8 w - - 0 1"
        #expect(ChessGame.hasInsufficientMaterial(fen: kbvk))

        // King + Bishop vs King + Bishop (same square color, e.g. c1=dark, f8=dark)
        // c1: file 3, rank 1 -> (3+1)%2 = 0 (dark)
        // f8: file 6, rank 8 -> (6+8)%2 = 0 (dark)
        let kbvkbSameColor = "5b2/8/8/4k3/8/8/8/2B1K3 w - - 0 1"
        #expect(ChessGame.hasInsufficientMaterial(fen: kbvkbSameColor))

        // King + Bishop vs King + Bishop (opposite square colors, e.g. c1=dark, c8=light)
        // c8: file 3, rank 8 -> (3+8)%2 = 1 (light)
        let kbvkbOppositeColor = "2b5/8/8/4k3/8/8/8/2B1K3 w - - 0 1"
        #expect(!ChessGame.hasInsufficientMaterial(fen: kbvkbOppositeColor))

        // King + Rook vs King (sufficient)
        let krvk = "8/8/8/4k3/8/8/4KR2/8 w - - 0 1"
        #expect(!ChessGame.hasInsufficientMaterial(fen: krvk))

        // King + Pawn vs King (sufficient)
        let kpvk = "8/8/8/4k3/8/8/4KP2/8 w - - 0 1"
        #expect(!ChessGame.hasInsufficientMaterial(fen: kpvk))
    }

    @Test func fiftyMoveDrawDetection() {
        let normalFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        #expect(!ChessGame.isFiftyMoveDraw(fen: normalFEN))

        let ninetyNineFEN = "8/8/8/4k3/8/8/4K1P1/8 w - - 99 60"
        #expect(!ChessGame.isFiftyMoveDraw(fen: ninetyNineFEN))

        let hundredFEN = "8/8/8/4k3/8/8/4K1P1/8 w - - 100 60"
        #expect(ChessGame.isFiftyMoveDraw(fen: hundredFEN))
        #expect(ChessGame.detectOutcome(currentFEN: hundredFEN, historyFENs: [hundredFEN]) == .fiftyMoveRule)
    }

    @Test func threefoldRepetitionDetection() {
        let fen1 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let fen2 = "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1"
        let fen3 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 2 2"
        let fen4 = "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 3 2"
        let fen5 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 4 3"

        // Position 1 appears 3 times (fen1, fen3, fen5)
        let history = [fen1, fen2, fen3, fen4, fen5]
        #expect(ChessGame.isThreefoldRepetition(fens: history))
        #expect(!ChessGame.isThreefoldRepetition(fens: [fen1, fen2, fen3, fen4]))
    }

    @Test func gameOutcomeProperties() {
        let whiteWins = GameOutcome.checkmate(winner: .white)
        #expect(whiteWins.resultString == "1-0")
        #expect(whiteWins.winner == .white)
        #expect(!whiteWins.isDraw)
        #expect(whiteWins.terminationDescription == "White won by checkmate")

        let blackWins = GameOutcome.checkmate(winner: .black)
        #expect(blackWins.resultString == "0-1")
        #expect(blackWins.winner == .black)
        #expect(!blackWins.isDraw)
        #expect(blackWins.terminationDescription == "Black won by checkmate")

        let userResignsAsWhite = GameOutcome.resignation(resignedBy: .white)
        #expect(userResignsAsWhite.resultString == "0-1")
        #expect(userResignsAsWhite.winner == .black)
        #expect(!userResignsAsWhite.isDraw)
        #expect(userResignsAsWhite.terminationDescription == "Black won by resignation")

        let draw = GameOutcome.stalemate
        #expect(draw.resultString == "1/2-1/2")
        #expect(draw.winner == nil)
        #expect(draw.isDraw)
        #expect(draw.terminationDescription == "Draw by stalemate")
    }

    @Test func playerSideSelection() {
        #expect(PlayerSideSelection.white.resolveColor() == .white)
        #expect(PlayerSideSelection.black.resolveColor() == .black)
        let randomChoice = PlayerSideSelection.random.resolveColor()
        #expect(randomChoice == .white || randomChoice == .black)
    }
}
