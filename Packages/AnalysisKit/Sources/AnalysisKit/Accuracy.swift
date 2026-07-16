import Foundation

public enum Accuracy {
    /// Per-move accuracy (Lichess formula) from the mover's win-probability
    /// drop (already clamped to >= 0 by the caller), clamped to 0...100.
    public static func perMove(drop: Double) -> Double {
        let raw = 103.1668 * exp(-0.04354 * drop) - 3.1669
        return min(100, max(0, raw))
    }

    /// A player's game accuracy: the arithmetic mean of their per-move accuracies.
    public static func average(_ perMoveAccuracies: [Double]) -> Double {
        guard !perMoveAccuracies.isEmpty else { return 0 }
        return perMoveAccuracies.reduce(0, +) / Double(perMoveAccuracies.count)
    }
}
