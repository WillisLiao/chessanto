import Foundation

/// The arrows and circles a user draws on a position to think with.
///
/// **These are deliberately not persisted.** An annotation is a thought
/// about the position currently on the board, and it is cleared the moment
/// the board shows something else - which is what lichess and chess.com both
/// do, and what makes the feature self-contained. Persisting them would need
/// a position-keyed table, a lifecycle answer for what happens to them when
/// a game is re-analyzed or a variation is deleted, and UI to manage the
/// accumulated set. That is its own piece of work, not a side effect of
/// adding the drawing gesture.
struct BoardAnnotations: Equatable {
    struct Arrow: Hashable {
        let from: BoardSquare
        let to: BoardSquare
    }

    private(set) var arrows: Set<Arrow> = []
    private(set) var circles: Set<BoardSquare> = []

    var isEmpty: Bool { arrows.isEmpty && circles.isEmpty }

    /// Right-dragging between two squares draws an arrow; drawing the same
    /// arrow again erases it, which is the only undo the gesture needs.
    mutating func toggleArrow(from: BoardSquare, to: BoardSquare) {
        guard from != to else {
            toggleCircle(from)
            return
        }
        let arrow = Arrow(from: from, to: to)
        if arrows.contains(arrow) {
            arrows.remove(arrow)
        } else {
            arrows.insert(arrow)
        }
    }

    /// A right-click that goes nowhere marks the square instead.
    mutating func toggleCircle(_ square: BoardSquare) {
        if circles.contains(square) {
            circles.remove(square)
        } else {
            circles.insert(square)
        }
    }

    mutating func clear() {
        arrows.removeAll()
        circles.removeAll()
    }
}
