import Testing
@testable import ChessCore

struct LegalMoveCountTests {
    @Test func startingPositionHasTwentyLegalMoves() {
        let startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        #expect(ChessGame.legalMoveCount(fen: startpos) == 20)
    }

    @Test func stalemateHasNoLegalMoves() {
        // Black to move, not in check, no legal move.
        #expect(ChessGame.legalMoveCount(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1") == 0)
    }

    @Test func singleReplyToCheckIsAForcedMove() {
        // White king on h1, in check down the open h-file from the rook on
        // h8. The g2 pawn cannot interpose (it moves up the g-file, not
        // into the check), so Kg1 is the only legal move.
        let fen = "7r/8/8/8/8/8/6P1/7K w - - 0 1"
        #expect(ChessGame.legalMoveCount(fen: fen) == 1)
    }

    @Test func blackToMoveIsCountedForBlack() {
        let startposBlack = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
        #expect(ChessGame.legalMoveCount(fen: startposBlack) == 20)
    }

    @Test func invalidFENReportsZeroRatherThanCrashing() {
        #expect(ChessGame.legalMoveCount(fen: "not a fen") == 0)
    }
}
