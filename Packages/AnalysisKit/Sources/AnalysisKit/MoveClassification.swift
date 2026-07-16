public enum MoveClassification: String, CaseIterable, Sendable {
    case best
    /// Reserved for M5's sacrifice/theme detection; never assigned in M2.
    case brilliant
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder
    case missedWin
}
