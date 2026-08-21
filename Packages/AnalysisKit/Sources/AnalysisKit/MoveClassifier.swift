import ChessCore

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

/// The board facts a move cannot be fairly graded without: whether it was
/// still opening theory, and whether the player had any alternative.
///
/// Kept separate from the evaluations because it comes from replaying the
/// position rather than from the engine, and because a caller with neither
/// piece of information (an older stored analysis, a test) can still
/// classify by passing `.none`.
public struct ClassificationContext: Sendable, Equatable {
    /// The deepest ply still inside the opening book. Moves at or before
    /// this ply are theory. Zero means no book match.
    public let deepestBookPly: Int
    /// Plies (1-based, matching `playedUCIs[p - 1]`) where the mover had
    /// exactly one legal move.
    public let forcedPlies: Set<Int>
    /// Plies (1-based) that `BrilliancyDetector` found to be a genuine
    /// brilliancy: the engine's own top choice, a real sacrifice accepted
    /// on the board, the mover clearly winning after, and materially
    /// unique among the engine's own lines.
    public let brilliantPlies: Set<Int>

    public init(deepestBookPly: Int = 0, forcedPlies: Set<Int> = [], brilliantPlies: Set<Int> = []) {
        self.deepestBookPly = deepestBookPly
        self.forcedPlies = forcedPlies
        self.brilliantPlies = brilliantPlies
    }

    /// No book and no forced-move information: every move is graded.
    public static let none = ClassificationContext()

    /// Derives the context for a whole game from its own positions.
    ///
    /// Every consumer that classifies a game must go through this, so the
    /// desktop report and the phone companion cannot disagree about
    /// whether a given move was theory or forced - a move labelled "Book"
    /// on the Mac and "Best" on the phone is the same move being described
    /// two different ways.
    public static func forGame(input: ReportInput, openingBook: OpeningBook) -> ClassificationContext {
        let moveCount = input.plies.count - 1
        guard moveCount >= 1 else { return .none }

        let deepestBookPly = openingBook.lookup(fens: input.plies.map(\.fen))?.deepestBookPly ?? 0

        var forced: Set<Int> = []
        for p in 1...moveCount where ChessGame.legalMoveCount(fen: input.plies[p - 1].fen) == 1 {
            forced.insert(p)
        }

        var brilliant: Set<Int> = []
        for p in 1...moveCount where p > deepestBookPly && !forced.contains(p) {
            if BrilliancyDetector.isBrilliant(input: input, ply: p) { brilliant.insert(p) }
        }

        return ClassificationContext(deepestBookPly: deepestBookPly, forcedPlies: forced, brilliantPlies: brilliant)
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
    /// - parameter context: board facts that exempt a move from grading.
    public static func classify(
        positionEvaluations: [PlyEvaluation],
        playedUCIs: [String],
        whiteToMove: [Bool],
        context: ClassificationContext = .none
    ) -> [MoveClassification] {
        precondition(positionEvaluations.count == playedUCIs.count + 1)
        precondition(playedUCIs.count == whiteToMove.count)

        var results: [MoveClassification] = []
        results.reserveCapacity(playedUCIs.count)

        for p in stride(from: 1, through: playedUCIs.count, by: 1) {
            // Book is checked before forced: a theory move that happens to
            // be forced is still better described as theory.
            if p <= context.deepestBookPly {
                results.append(.book)
                continue
            }
            if context.forcedPlies.contains(p) {
                results.append(.forced)
                continue
            }
            if context.brilliantPlies.contains(p) {
                results.append(.brilliant)
                continue
            }

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
