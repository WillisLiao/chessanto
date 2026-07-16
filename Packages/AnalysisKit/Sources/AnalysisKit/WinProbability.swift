import Foundation

/// Win-probability math over white-perspective engine evaluations
/// (Lichess's model). All inputs and outputs here are white-perspective;
/// callers flip to the mover's perspective with `moverWinProbability`.
public enum WinProbability {
    /// White's win probability (0...100) for a white-perspective centipawn score.
    public static func fromCentipawns(_ cp: Int) -> Double {
        50 + 50 * (2 / (1 + exp(-0.00368208 * Double(cp))) - 1)
    }

    /// White's win probability (0 or 100) for a white-perspective mate score.
    /// `mateIn > 0` means White delivers mate; `mateIn < 0` means White is mated.
    public static func fromMate(_ mateIn: Int) -> Double {
        mateIn > 0 ? 100 : 0
    }

    /// White's win probability for a rank-1 evaluation, preferring mate over cp.
    public static func whiteWinProbability(scoreCentipawns: Int?, mateIn: Int?) -> Double {
        if let mateIn {
            return fromMate(mateIn)
        }
        if let scoreCentipawns {
            return fromCentipawns(scoreCentipawns)
        }
        return 50
    }

    /// The mover's win probability, given White's win probability and whether
    /// White is the one to move.
    public static func moverWinProbability(whiteWinProbability: Double, whiteToMove: Bool) -> Double {
        whiteToMove ? whiteWinProbability : 100 - whiteWinProbability
    }
}
