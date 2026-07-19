import Testing
@testable import Chessanto

struct MoveNotationFormatterTests {
    @Test
    func standardStylePreservesCanonicalSAN() {
        let formatter = MoveNotationFormatter(style: .standard)

        #expect(formatter.move("Nf3").visual == "Nf3")
        #expect(formatter.move("O-O-O#").visual == "O-O-O#")
        #expect(formatter.move("e8=Q+").visual == "e8=Q+")
    }

    @Test
    func pieceNameStyleExpandsTheCommonMoveShapes() {
        let formatter = MoveNotationFormatter(style: .pieceNames)

        #expect(formatter.move("Nf3").visual == "Knight f3")
        #expect(formatter.move("Nxf3+").visual == "Knight takes f3, check")
        #expect(formatter.move("Nbd2").visual == "Knight b to d2")
        #expect(formatter.move("R1e2").visual == "Rook 1 to e2")
        #expect(formatter.move("Nb1d2").visual == "Knight b1 to d2")
        #expect(formatter.move("e4").visual == "Pawn e4")
        #expect(formatter.move("exd5").visual == "e-pawn takes d5")
        #expect(formatter.move("e8=Q+").visual == "Pawn e8, promotes to Queen, check")
        #expect(formatter.move("O-O").visual == "Castle kingside")
        #expect(formatter.move("O-O-O#").visual == "Castle queenside, checkmate")
    }

    @Test
    func annotationsArePreservedAfterTheReadableMove() {
        let formatter = MoveNotationFormatter(style: .pieceNames)

        #expect(formatter.move("Qxf7#!!").visual == "Queen takes f7, checkmate !!")
        #expect(formatter.move("b1=N?!").visual == "Pawn b1, promotes to Knight ?!")
    }

    @Test
    func malformedInputFallsBackWithoutCrashingOrDisappearing() {
        let formatter = MoveNotationFormatter(style: .pieceNames)

        #expect(formatter.move("not-a-move").visual == "not-a-move")
        #expect(formatter.move("").visual == "")
    }

    @Test
    func proseTransformsOnlyCompleteSANShapedTokens() {
        let formatter = MoveNotationFormatter(style: .pieceNames)
        let source = "5. Nf3?! was loose. Better was **Nc3**; Qxe4+ followed. The pawn on e4 was weak."

        #expect(
            formatter.text(source)
                == "5. Knight f3 ?! was loose. Better was **Knight c3**; Queen takes e4, check followed. The pawn on e4 was weak."
        )
    }

    @Test
    func accessibilityIsSemanticInBothVisualStyles() {
        let standard = MoveNotationFormatter(style: .standard)
        let named = MoveNotationFormatter(style: .pieceNames)

        #expect(standard.move("Nxf3+").spoken == "Knight captures f 3, check")
        #expect(named.move("Nxf3+").spoken == "Knight captures f 3, check")
        #expect(standard.move("O-O-O#").spoken == "Castle queenside, checkmate")
    }

    @Test
    func lineFormatsEveryMoveWithoutMutatingTheInput() {
        let formatter = MoveNotationFormatter(style: .pieceNames)
        let canonical = ["e4", "e5", "Nf3"]

        #expect(formatter.line(canonical) == "Pawn e4 Pawn e5 Knight f3")
        #expect(canonical == ["e4", "e5", "Nf3"])
    }
}
