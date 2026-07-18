import ChessCore

/// A position evaluation from White's perspective, always in exactly one of
/// two forms - unlike a `(scoreCentipawns: Int?, mateIn: Int?)` pair, this
/// type cannot represent both or neither at once, which is what let F7 (a
/// forced mate compared against a nil `best` centipawn value) slip through.
enum WhitePerspectiveScore: Sendable, Equatable {
    case centipawns(Int)
    case mate(Int)

    /// Reads the persisted `(scoreCentipawns, mateIn)` pair from a
    /// `RankedLine`. Mate wins when both are present (matches
    /// `EngineScoreNormalizer`'s convention of always populating `mateIn`
    /// for a mate score); returns `nil` when both are absent.
    init?(scoreCentipawns: Int?, mateIn: Int?) {
        if let mateIn {
            self = .mate(mateIn)
        } else if let scoreCentipawns {
            self = .centipawns(scoreCentipawns)
        } else {
            return nil
        }
    }

    /// Reorients this White-perspective score to the mover's perspective:
    /// unchanged for White, negated (both the centipawn value and the mate
    /// distance) for Black. The single place the Black-to-move sign
    /// convention is applied.
    func oriented(forMover mover: ChessCore.PieceColor) -> WhitePerspectiveScore {
        guard mover == .black else { return self }
        switch self {
        case .centipawns(let value): return .centipawns(-value)
        case .mate(let value): return .mate(-value)
        }
    }
}

/// The training domain's request to evaluate an attempted move: the
/// position before the move and the move itself, as UCI.
struct TrainingPositionRequest: Sendable, Equatable {
    let preMoveFEN: String
    let attemptedMoveUCI: String
}
