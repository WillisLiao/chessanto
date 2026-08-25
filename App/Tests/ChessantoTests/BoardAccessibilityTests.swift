import Testing
@testable import Chessanto

struct BoardAccessibilityTests {
    private func sq(_ algebraic: String) -> BoardSquare {
        guard let square = BoardSquare(algebraic: algebraic) else {
            fatalError("bad test square \(algebraic)")
        }
        return square
    }

    @Test func emptySquareLabelIsJustTheAddress() {
        #expect(BoardAccessibility.squareLabel(piece: nil, square: sq("e4")) == "e4")
    }

    @Test func occupiedSquareLabelLeadsWithThePiece() {
        let pawn = DisplayPiece(color: .white, kind: .pawn)
        #expect(BoardAccessibility.squareLabel(piece: pawn, square: sq("e4")) == "White pawn e4")
        let queen = DisplayPiece(color: .black, kind: .queen)
        #expect(BoardAccessibility.squareLabel(piece: queen, square: sq("d8")) == "Black queen d8")
    }

    @Test func squareValueJoinsOnlyPresentStates() {
        #expect(
            BoardAccessibility.squareValue(isSelected: false, isLegalDestination: false, isHint: false, isLastMoveSquare: false)
                == ""
        )
        #expect(
            BoardAccessibility.squareValue(isSelected: true, isLegalDestination: false, isHint: false, isLastMoveSquare: false)
                == "selected"
        )
        #expect(
            BoardAccessibility.squareValue(isSelected: false, isLegalDestination: true, isHint: false, isLastMoveSquare: true)
                == "legal destination, last move"
        )
        #expect(
            BoardAccessibility.squareValue(isSelected: true, isLegalDestination: true, isHint: true, isLastMoveSquare: true)
                == "selected, legal destination, practice hint, last move"
        )
    }

    @Test func moveAnnouncementNamesPieceAndSquares() {
        var position = BoardPosition.empty
        position.pieces[sq("e4")] = DisplayPiece(color: .white, kind: .pawn)
        let text = BoardAccessibility.moveAnnouncement(position: position, lastMove: (sq("e2"), sq("e4")))
        #expect(text == "White pawn e2 to e4")
    }

    @Test func neighborWalksScreenRelativeWithoutFlip() {
        // e4 -> right is f4, up is e5.
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .right, flipped: false) == sq("f4"))
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .up, flipped: false) == sq("e5"))
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .left, flipped: false) == sq("d4"))
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .down, flipped: false) == sq("e3"))
    }

    @Test func neighborWalksScreenRelativeWhenFlipped() {
        // Flipped, e4 renders with e on the right side of the board and
        // rank 1 at the top, so screen-up from e4 must reach e3.
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .up, flipped: true) == sq("e3"))
        #expect(BoardAccessibility.neighbor(of: sq("e4"), direction: .left, flipped: true) == sq("f4"))
    }

    @Test func neighborStopsAtBoardEdges() {
        #expect(BoardAccessibility.neighbor(of: sq("a1"), direction: .down, flipped: false) == nil)
        #expect(BoardAccessibility.neighbor(of: sq("a1"), direction: .left, flipped: false) == nil)
        #expect(BoardAccessibility.neighbor(of: sq("h8"), direction: .up, flipped: false) == nil)
        #expect(BoardAccessibility.neighbor(of: sq("h8"), direction: .right, flipped: false) == nil)
        #expect(BoardAccessibility.neighbor(of: sq("h8"), direction: .down, flipped: true) == nil)
    }

    @Test func initialCursorPrefersTheLastMoveDestination() {
        #expect(BoardAccessibility.initialCursor(lastMove: (sq("g1"), sq("f3"))) == sq("f3"))
        #expect(BoardAccessibility.initialCursor(lastMove: nil) == sq("e2"))
    }
}
