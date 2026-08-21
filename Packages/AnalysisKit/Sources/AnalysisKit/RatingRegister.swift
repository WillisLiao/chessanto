import Foundation

/// Adaptive rating register (PLAN.md's "Teaching depth"): three rendering/
/// prompt registers, resolved either directly from a fixed
/// `userProfile.ratingBand` or per-game from the user's numeric rating.
public enum RatingRegister: String, Sendable, Codable, CaseIterable {
    case beginner, intermediate, advanced

    /// `ratingBand` is `userProfile.ratingBand` verbatim ("beginner",
    /// "intermediate", "advanced", or "adaptive"). For "adaptive", `userRating`
    /// (the user's rating in *this* game, resolved by the caller from
    /// `GameRecord.whiteRating`/`blackRating` via `chessComUsername`) decides:
    /// <1200 beginner, 1200-1800 intermediate, >1800 advanced, unknown -> intermediate.
    public static func resolve(ratingBand: String, userRating: Int?) -> RatingRegister {
        switch ratingBand {
        case "beginner": return .beginner
        case "intermediate": return .intermediate
        case "advanced": return .advanced
        default:
            guard let userRating else { return .intermediate }
            if userRating < 1200 { return .beginner }
            if userRating <= 1800 { return .intermediate }
            return .advanced
        }
    }

    /// How many key moments `KeyMomentSelector` fills the report to, above
    /// whichever blunders/missedWins are required regardless of register.
    var keyMomentCap: Int {
        switch self {
        case .beginner: return 4
        case .intermediate: return 6
        case .advanced: return 8
        }
    }

    /// How many plies of a `BetterMoveFact`'s line `ReportText` renders.
    var betterLinePlyCap: Int {
        switch self {
        case .beginner: return 2
        case .intermediate: return 4
        case .advanced: return 6
        }
    }

    /// Whether `ReportText` speaks in win percentages (intermediate/advanced)
    /// or stays qualitative (beginner).
    var usesWinPercentages: Bool { self != .beginner }

    /// Whether `ReportText` appends a numeric evaluation label after a
    /// better-move line.
    var showsEvalLabel: Bool { self != .beginner }

    /// Whether `KeyMomentSelector` should prefer optional moments that carry
    /// a nameable consequence (punishment/missed mate/allowed mate) when
    /// filling to the cap.
    var prefersNameableConsequences: Bool { self == .beginner }
}
