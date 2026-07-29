import Foundation

public enum Accuracy {
    /// Per-move accuracy (Lichess formula) from the mover's win-probability
    /// drop (already clamped to >= 0 by the caller), clamped to 0...100.
    public static func perMove(drop: Double) -> Double {
        let raw = 103.1668 * exp(-0.04354 * drop) - 3.1669
        return min(100, max(0, raw))
    }

    /// The arithmetic mean of per-move accuracies.
    ///
    /// Kept only for callers that genuinely want a flat average. It is the
    /// wrong summary for a game: see `game(whiteWinPercents:...)`.
    public static func average(_ perMoveAccuracies: [Double]) -> Double {
        guard !perMoveAccuracies.isEmpty else { return 0 }
        return perMoveAccuracies.reduce(0, +) / Double(perMoveAccuracies.count)
    }

    /// Both players' game accuracy, following Lichess's
    /// `AccuracyPercent.gameAccuracy`.
    ///
    /// A flat arithmetic mean of per-move accuracies is a poor summary of a
    /// game, and it is also not the number the user sees anywhere else, so
    /// they will compare it against Lichess and chess.com and conclude this
    /// app is wrong. Two corrections apply, and the result is their mean:
    ///
    /// - **Volatility weighting.** A move played in a sharp position, where
    ///   the evaluation is swinging, says more about the player than one
    ///   played in a dead-drawn rook ending. Each move is weighted by the
    ///   standard deviation of white win probability over a window around
    ///   it, clamped to 0.5...12, so quiet stretches stop diluting the
    ///   score.
    /// - **Harmonic mean.** An arithmetic mean lets forty accurate moves
    ///   bury one catastrophe: a player who hangs their queen once in a
    ///   fifty-move game should not read 97%. A harmonic mean is dominated
    ///   by its smallest terms, which is what a review tool wants.
    ///
    /// - parameter whiteWinPercents: white win probability at each position,
    ///   index 0 = starting position, index `p` = after move `p`.
    /// - parameter moverIsWhite: whether White played move `p`, at index
    ///   `p - 1`.
    /// - parameter isScored: whether move `p` counts, at index `p - 1`.
    ///   Book and forced moves pass `false`: they still shape the game's
    ///   volatility, so they stay in the windows, but they were not
    ///   decisions and must not move the score.
    ///
    /// Returns `nil` when either side has no scored move to average.
    public static func game(
        whiteWinPercents: [Double],
        moverIsWhite: [Bool],
        isScored: [Bool]
    ) -> (white: Double, black: Double)? {
        let moveCount = whiteWinPercents.count - 1
        guard moveCount >= 1, moverIsWhite.count == moveCount, isScored.count == moveCount else {
            return nil
        }

        let weights = volatilityWeights(whiteWinPercents: whiteWinPercents)
        guard weights.count == moveCount else { return nil }

        var whiteTerms: [(accuracy: Double, weight: Double)] = []
        var blackTerms: [(accuracy: Double, weight: Double)] = []

        for index in 0..<moveCount {
            guard isScored[index] else { continue }
            let before = whiteWinPercents[index]
            let after = whiteWinPercents[index + 1]
            // Win probabilities are white-perspective, so Black's drop is
            // the rise in White's.
            let drop = moverIsWhite[index] ? before - after : after - before
            let term = (accuracy: perMove(drop: max(0, drop)), weight: weights[index])
            if moverIsWhite[index] {
                whiteTerms.append(term)
            } else {
                blackTerms.append(term)
            }
        }

        guard let white = combine(whiteTerms), let black = combine(blackTerms) else {
            return nil
        }
        return (white: white, black: black)
    }

    /// The mean of the weighted mean and the harmonic mean of one player's
    /// per-move accuracies.
    private static func combine(_ terms: [(accuracy: Double, weight: Double)]) -> Double? {
        guard !terms.isEmpty else { return nil }

        let weightTotal = terms.reduce(0) { $0 + $1.weight }
        guard weightTotal > 0 else { return nil }
        let weightedMean = terms.reduce(0) { $0 + $1.accuracy * $1.weight } / weightTotal

        // A single accuracy of exactly zero drives the harmonic mean to
        // zero rather than to a NaN, which is the intended behaviour: one
        // move that threw the game away should dominate.
        let reciprocalTotal = terms.reduce(0) { $0 + 1 / $1.accuracy }
        let harmonicMean = reciprocalTotal.isFinite && reciprocalTotal > 0
            ? Double(terms.count) / reciprocalTotal
            : 0

        return min(100, max(0, (weightedMean + harmonicMean) / 2))
    }

    /// One weight per move: the standard deviation of white win probability
    /// over a window around that move, clamped to 0.5...12.
    ///
    /// The first `windowSize - 2` moves all share the leading window, since
    /// there is no earlier context to slide over; the rest use a window
    /// sliding one position at a time. That yields exactly one weight per
    /// move.
    private static func volatilityWeights(whiteWinPercents: [Double]) -> [Double] {
        let positionCount = whiteWinPercents.count
        let moveCount = positionCount - 1
        guard moveCount >= 1 else { return [] }

        let windowSize = min(max(moveCount / 10, 2), 8)
        let leadingWindow = Array(whiteWinPercents.prefix(windowSize))
        let leadingCount = max(min(windowSize, positionCount) - 2, 0)

        var windows: [[Double]] = Array(repeating: leadingWindow, count: leadingCount)
        if positionCount >= windowSize {
            for start in 0...(positionCount - windowSize) {
                windows.append(Array(whiteWinPercents[start..<(start + windowSize)]))
            }
        } else {
            windows.append(whiteWinPercents)
        }

        let weights = windows.map { window in
            min(max(standardDeviation(window), 0.5), 12)
        }
        // Guard against an arithmetic surprise rather than trusting the
        // window bookkeeping to line up silently.
        guard weights.count >= moveCount else {
            return Array(repeating: 1, count: moveCount)
        }
        return Array(weights.prefix(moveCount))
    }

    /// Population standard deviation, matching Lichess's `Maths`.
    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
