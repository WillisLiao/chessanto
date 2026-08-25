import Foundation

/// Pure accessibility semantics for the chess board: what a square should
/// be called by VoiceOver, what changed on the last move, and how a
/// keyboard cursor steps between squares. Kept out of `BoardView` so every
/// string and coordinate decision here is unit-testable without a window.
///
/// The board is the app's one control whose meaning is purely visual, so
/// its assistive strategy has to be explicit: each of the 64 square
/// buttons speaks the piece standing on it plus its own address ("white
/// pawn e4"), its value carries the non-obvious visual states (selected,
/// legal destination, practice hint, last move), and after every move an
/// announcement names what just happened so a VoiceOver user does not have
/// to re-walk 64 squares to discover it.
enum BoardAccessibility {
    /// The button label for one square: piece first (that is what the user
    /// cares about), square second. An empty square is just its address.
    static func squareLabel(piece: DisplayPiece?, square: BoardSquare) -> String {
        guard let piece else { return square.algebraic }
        return "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) \(square.algebraic)"
    }

    /// The button value: the states sighted users get from highlight
    /// colors. Empty when the square carries no state.
    static func squareValue(
        isSelected: Bool,
        isLegalDestination: Bool,
        isHint: Bool,
        isLastMoveSquare: Bool
    ) -> String {
        var parts: [String] = []
        if isSelected { parts.append("selected") }
        if isLegalDestination { parts.append("legal destination") }
        if isHint { parts.append("practice hint") }
        if isLastMoveSquare { parts.append("last move") }
        return parts.joined(separator: ", ")
    }

    /// What VoiceOver announces after a move lands: the piece that arrived,
    /// where it came from, and where it now stands.
    static func moveAnnouncement(position: BoardPosition, lastMove: (from: BoardSquare, to: BoardSquare)) -> String {
        let pieceText = position.pieces[lastMove.to].map { "\($0.color.rawValue.capitalized) \($0.kind.rawValue) " } ?? ""
        return "\(pieceText)\(lastMove.from.algebraic) to \(lastMove.to.algebraic)"
    }

    /// One visual step from `square`. Directions are screen-relative (up is
    /// toward rank 8 on an unflipped board) and honor `flipped`, matching
    /// `BoardView`'s own row/column mapping exactly.
    static func neighbor(of square: BoardSquare, direction: CursorDirection, flipped: Bool) -> BoardSquare? {
        let col = flipped ? 7 - square.file : square.file
        let row = flipped ? square.rank : 7 - square.rank

        var newRow = row
        var newCol = col
        switch direction {
        case .up: newRow -= 1
        case .down: newRow += 1
        case .left: newCol -= 1
        case .right: newCol += 1
        }
        guard (0..<8).contains(newRow), (0..<8).contains(newCol) else { return nil }

        let file = flipped ? 7 - newCol : newCol
        let rank = flipped ? newRow : 7 - newRow
        return BoardSquare(file: file, rank: rank)
    }

    /// Where a fresh cursor starts: on the move that just landed when there
    /// is one, otherwise the king's knight square most first moves begin
    /// from. Purely a convenience default; arrows move it immediately.
    static func initialCursor(lastMove: (from: BoardSquare, to: BoardSquare)?) -> BoardSquare {
        lastMove?.to ?? BoardSquare(file: 4, rank: 1)
    }
}

enum CursorDirection {
    case up, down, left, right
}
