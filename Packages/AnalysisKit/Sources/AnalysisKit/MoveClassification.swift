public enum MoveClassification: String, CaseIterable, Sendable, Codable {
    case best
    /// Reserved for M5's sacrifice/theme detection; never assigned in M2.
    case brilliant
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder
    case missedWin
    /// Opening theory: the position was still in the bundled opening book,
    /// so the move reflects preparation rather than a choice made at the
    /// board. Graded moves in the book produce inaccuracy flags on
    /// mainline theory, which is both wrong and demoralising.
    case book
    /// The mover had exactly one legal move. Comparing a move to the
    /// engine's preference measures nothing when there was no alternative.
    case forced

    /// Whether this classification reflects a decision the player actually
    /// made, and so belongs in accuracy and in the error counts that drive
    /// key moments, practice cards, and the Player Brief.
    ///
    /// Book and forced moves are still shown - the player should see that
    /// the app knows they were theory or forced - but they must not move
    /// the numbers. Counting a forced recapture as `best` inflated both
    /// accuracy and the best-move count.
    public var isPlayerDecision: Bool {
        switch self {
        case .book, .forced: return false
        default: return true
        }
    }
}
