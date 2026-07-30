import Testing
@testable import Chessanto

struct BoardAnnotationsTests {
    private func square(_ algebraic: String) -> BoardSquare {
        BoardSquare(algebraic: algebraic)!
    }

    @Test
    func startsEmpty() {
        #expect(BoardAnnotations().isEmpty)
    }

    @Test
    func draggingBetweenTwoSquaresDrawsAnArrow() {
        var annotations = BoardAnnotations()
        annotations.toggleArrow(from: square("e2"), to: square("e4"))

        #expect(annotations.arrows == [BoardAnnotations.Arrow(from: square("e2"), to: square("e4"))])
        #expect(annotations.circles.isEmpty)
    }

    @Test
    func drawingTheSameArrowTwiceErasesIt() {
        var annotations = BoardAnnotations()
        annotations.toggleArrow(from: square("e2"), to: square("e4"))
        annotations.toggleArrow(from: square("e2"), to: square("e4"))

        #expect(annotations.isEmpty)
    }

    @Test
    func arrowDirectionMatters() {
        var annotations = BoardAnnotations()
        annotations.toggleArrow(from: square("e2"), to: square("e4"))
        annotations.toggleArrow(from: square("e4"), to: square("e2"))

        #expect(annotations.arrows.count == 2)
    }

    /// A right-click that never leaves the square is not a zero-length
    /// arrow, it is a mark on that square.
    @Test
    func draggingWithinOneSquareCirclesItInstead() {
        var annotations = BoardAnnotations()
        annotations.toggleArrow(from: square("d5"), to: square("d5"))

        #expect(annotations.circles == [square("d5")])
        #expect(annotations.arrows.isEmpty)
    }

    @Test
    func circlingTheSameSquareTwiceErasesIt() {
        var annotations = BoardAnnotations()
        annotations.toggleCircle(square("d5"))
        annotations.toggleCircle(square("d5"))

        #expect(annotations.isEmpty)
    }

    @Test
    func clearRemovesEverything() {
        var annotations = BoardAnnotations()
        annotations.toggleArrow(from: square("e2"), to: square("e4"))
        annotations.toggleCircle(square("d5"))
        annotations.clear()

        #expect(annotations.isEmpty)
    }
}
