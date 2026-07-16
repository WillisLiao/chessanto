/// A rank-1 (best-line) engine evaluation for one position, white-perspective.
public struct PlyEvaluation: Sendable {
    public let scoreCentipawns: Int?
    public let mateIn: Int?
    public let bestMoveUCI: String?

    public init(scoreCentipawns: Int?, mateIn: Int?, bestMoveUCI: String?) {
        self.scoreCentipawns = scoreCentipawns
        self.mateIn = mateIn
        self.bestMoveUCI = bestMoveUCI
    }
}

public enum MoveClassifier {
    /// Classifies mainline moves 1...N.
    ///
    /// - parameter positionEvaluations: rank-1 evaluation at each position,
    ///   index 0 = starting position, index `p` = position after move `p`
    ///   (length N + 1).
    /// - parameter playedUCIs: the UCI of each played move, `playedUCIs[p - 1]`
    ///   is move `p` (length N).
    /// - parameter whiteToMove: whether White is the mover of move `p`,
    ///   `whiteToMove[p - 1]` (length N).
    public static func classify(
        positionEvaluations: [PlyEvaluation],
        playedUCIs: [String],
        whiteToMove: [Bool]
    ) -> [MoveClassification] {
        precondition(positionEvaluations.count == playedUCIs.count + 1)
        precondition(playedUCIs.count == whiteToMove.count)

        var results: [MoveClassification] = []
        results.reserveCapacity(playedUCIs.count)

        for p in stride(from: 1, through: playedUCIs.count, by: 1) {
            let before = positionEvaluations[p - 1]
            let after = positionEvaluations[p]
            let moverIsWhite = whiteToMove[p - 1]

            let beforeWhiteWinP = WinProbability.whiteWinProbability(
                scoreCentipawns: before.scoreCentipawns, mateIn: before.mateIn
            )
            let afterWhiteWinP = WinProbability.whiteWinProbability(
                scoreCentipawns: after.scoreCentipawns, mateIn: after.mateIn
            )
            let moverBeforeWinP = WinProbability.moverWinProbability(
                whiteWinProbability: beforeWhiteWinP, whiteToMove: moverIsWhite
            )
            let moverAfterWinP = WinProbability.moverWinProbability(
                whiteWinProbability: afterWhiteWinP, whiteToMove: moverIsWhite
            )
            let drop = max(0, moverBeforeWinP - moverAfterWinP)

            let isBest = before.bestMoveUCI == playedUCIs[p - 1]

            let beforeWasMateForMover: Bool = {
                guard let mateIn = before.mateIn else { return false }
                return moverIsWhite ? mateIn > 0 : mateIn < 0
            }()

            if isBest {
                results.append(.best)
            } else if (moverBeforeWinP >= 90 || beforeWasMateForMover) && moverAfterWinP <= 70 {
                results.append(.missedWin)
            } else if drop < 2 {
                results.append(.excellent)
            } else if drop < 10 {
                results.append(.good)
            } else if drop < 20 {
                results.append(.inaccuracy)
            } else if drop < 30 {
                results.append(.mistake)
            } else {
                results.append(.blunder)
            }
        }

        return results
    }
}
