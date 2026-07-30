import ChessCore
import Foundation

/// The select-then-move state machine every interactive board runs.
///
/// Both interactive call sites (`GameReplayView` and
/// `PracticeSessionViewModel`) previously kept their own copy of this logic
/// and had already drifted apart. This is the single copy: a pure value type
/// that owns the selection and the pending promotion, decides what the next
/// click or drop means, and hands the caller a `Move` to execute. It never
/// touches a board, a store, or an engine, so it is exhaustively testable
/// without any of them.
struct BoardInteraction: Equatable {
    /// A promotion the learner has committed the squares of but not yet the
    /// piece. Carries the mover's color so the picker can show that side's
    /// own artwork.
    struct PendingPromotion: Equatable {
        let from: BoardSquare
        let to: BoardSquare
        let color: PieceColor
    }

    /// A move the caller should now play. `promotion` is non-`nil` only for a
    /// promotion, so a caller building engine UCI knows exactly when to
    /// append the fifth character.
    struct Move: Equatable {
        let from: BoardSquare
        let to: BoardSquare
        let promotion: PromotionKind?

        /// The engine's own notation for this move: four characters for an
        /// ordinary move, five for a promotion (`"b7b8q"`).
        var uci: String {
            from.algebraic + to.algebraic + (promotion?.uciSuffix ?? "")
        }
    }

    /// What a click or drop resolved to. `.awaitingPromotionPiece` means the
    /// squares are settled and the picker is now showing; no move is played
    /// until the piece is chosen.
    enum Resolution: Equatable {
        case none
        case play(Move)
        case awaitingPromotionPiece
    }

    /// The board's knowledge of the position, supplied per interaction so
    /// this type never holds a reference to a view model or a game.
    struct Context {
        let position: BoardPosition
        let legalDestinations: (BoardSquare) -> Set<BoardSquare>
        let isPromotion: (BoardSquare, BoardSquare) -> Bool

        init(
            position: BoardPosition,
            legalDestinations: @escaping (BoardSquare) -> Set<BoardSquare>,
            isPromotion: @escaping (BoardSquare, BoardSquare) -> Bool
        ) {
            self.position = position
            self.legalDestinations = legalDestinations
            self.isPromotion = isPromotion
        }
    }

    private(set) var selectedSquare: BoardSquare?
    private(set) var pendingPromotion: PendingPromotion?

    /// The destinations to highlight, or empty when nothing is selected.
    /// Computed by the caller's context rather than cached, so a position
    /// change can never leave a stale highlight behind.
    func legalDestinations(context: Context) -> Set<BoardSquare> {
        guard let selectedSquare else { return [] }
        return context.legalDestinations(selectedSquare)
    }

    /// A click on `square`, which either selects a piece, deselects the
    /// current one, retargets to a different piece, or completes a move.
    mutating func select(_ square: BoardSquare, context: Context) -> Resolution {
        guard pendingPromotion == nil else { return .awaitingPromotionPiece }

        guard let selectedSquare else {
            if context.position.pieces[square] != nil {
                self.selectedSquare = square
            }
            return .none
        }

        if square == selectedSquare {
            self.selectedSquare = nil
            return .none
        }

        if context.legalDestinations(selectedSquare).contains(square) {
            return commit(from: selectedSquare, to: square, context: context)
        }

        // Not a legal destination: treat a click on another piece as
        // retargeting rather than as a failed move, and a click on an empty
        // square as giving up on the selection.
        self.selectedSquare = context.position.pieces[square] != nil ? square : nil
        return .none
    }

    /// A drag that released over `square`. Unlike a click this never
    /// retargets: a drop onto an illegal square simply returns the piece,
    /// which is what a dragged piece landing nowhere should do.
    mutating func drop(from: BoardSquare, to: BoardSquare, context: Context) -> Resolution {
        guard pendingPromotion == nil else { return .awaitingPromotionPiece }
        guard context.legalDestinations(from).contains(to) else {
            selectedSquare = nil
            return .none
        }
        return commit(from: from, to: to, context: context)
    }

    /// Begins a drag by selecting its origin, so the legal-destination
    /// highlights appear while the piece is in hand.
    mutating func beginDrag(from square: BoardSquare, context: Context) {
        guard pendingPromotion == nil, context.position.pieces[square] != nil else { return }
        selectedSquare = square
    }

    /// Answers the promotion picker. Returns the now-complete move.
    mutating func choosePromotion(_ kind: PromotionKind) -> Resolution {
        guard let pendingPromotion else { return .none }
        self.pendingPromotion = nil
        selectedSquare = nil
        return .play(Move(from: pendingPromotion.from, to: pendingPromotion.to, promotion: kind))
    }

    /// Dismisses the promotion picker without playing anything. The pawn
    /// stays where it was and the card stays unanswered.
    mutating func cancelPromotion() {
        pendingPromotion = nil
        selectedSquare = nil
    }

    /// Clears everything - used when the position changes underneath the
    /// board (jumping plies, loading the next card, starting a preview).
    mutating func reset() {
        selectedSquare = nil
        pendingPromotion = nil
    }

    private mutating func commit(from: BoardSquare, to: BoardSquare, context: Context) -> Resolution {
        if context.isPromotion(from, to) {
            let color = context.position.pieces[from]?.color ?? .white
            selectedSquare = nil
            pendingPromotion = PendingPromotion(from: from, to: to, color: color)
            return .awaitingPromotionPiece
        }
        selectedSquare = nil
        return .play(Move(from: from, to: to, promotion: nil))
    }
}

extension PromotionKind {
    /// The fifth character of a promotion's UCI, matching what the engine
    /// itself emits in a principal variation.
    var uciSuffix: String {
        switch self {
        case .queen: return "q"
        case .rook: return "r"
        case .bishop: return "b"
        case .knight: return "n"
        }
    }

    /// The piece this promotes to, for rendering the picker.
    var displayKind: PieceKind {
        switch self {
        case .queen: return .queen
        case .rook: return .rook
        case .bishop: return .bishop
        case .knight: return .knight
        }
    }

    /// Queen first, then the underpromotions in descending value - the order
    /// every mainstream board uses, so muscle memory carries over.
    static let pickerOrder: [PromotionKind] = [.queen, .rook, .bishop, .knight]
}
