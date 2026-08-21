import ChessCore

/// Detects a genuinely brilliant mainline move: the engine's own top choice,
/// a real sacrifice that the opponent actually accepts on the board, with
/// the mover clearly winning afterward and no comparably good alternative.
///
/// Deliberately conservative: every condition is required, and any missing
/// or ambiguous data (no rank-2 line, no PV, a truncated replay) is a "no",
/// never a guess. This mirrors `ThemeDetector.punishment`'s discipline of
/// asking the board directly rather than inferring from a PV's length.
public enum BrilliancyDetector {
    private static let minimumSacrifice = 3 // pawn-equivalents
    private static let minimumWinProbabilityAfter = 75.0
    private static let minimumUniquenessMargin = 10.0

    public static func isBrilliant(input: ReportInput, ply p: Int) -> Bool {
        guard p >= 1, p < input.plies.count else { return false }
        let before = input.plies[p - 1]
        let after = input.plies[p]
        guard let playedUCI = after.playedUCI else { return false }

        // 1. The engine's own top choice.
        guard let beforeRank1 = before.rank1, beforeRank1.principalVariationUCI.first == playedUCI else {
            return false
        }

        let moverIsWhite = input.moverIsWhite(atPly: p)

        // 2. Still clearly winning immediately after the move.
        guard let afterRank1 = after.rank1 else { return false }
        let afterWhiteWinP = WinProbability.whiteWinProbability(
            scoreCentipawns: afterRank1.scoreCentipawns, mateIn: afterRank1.mateIn
        )
        let moverWinPAfter = WinProbability.moverWinProbability(whiteWinProbability: afterWhiteWinP, whiteToMove: moverIsWhite)
        guard moverWinPAfter >= minimumWinProbabilityAfter else { return false }

        // 3. A materially unique winning try: rank-2 must exist and be
        // clearly worse than rank-1 at the pre-move position.
        guard let beforeRank2 = before.lines.first(where: { $0.rank == 2 }) else { return false }
        let beforeRank1WhiteWinP = WinProbability.whiteWinProbability(
            scoreCentipawns: beforeRank1.scoreCentipawns, mateIn: beforeRank1.mateIn
        )
        let beforeRank2WhiteWinP = WinProbability.whiteWinProbability(
            scoreCentipawns: beforeRank2.scoreCentipawns, mateIn: beforeRank2.mateIn
        )
        let moverWinPRank1 = WinProbability.moverWinProbability(whiteWinProbability: beforeRank1WhiteWinP, whiteToMove: moverIsWhite)
        let moverWinPRank2 = WinProbability.moverWinProbability(whiteWinProbability: beforeRank2WhiteWinP, whiteToMove: moverIsWhite)
        guard moverWinPRank1 - moverWinPRank2 >= minimumUniquenessMargin else { return false }

        // 4. Not simply taking back on the square the opponent just captured on.
        if p >= 2, let previousPlayedUCI = before.playedUCI {
            let playedDestination = String(playedUCI.dropFirst(2).prefix(2))
            let previousDestination = String(previousPlayedUCI.dropFirst(2).prefix(2))
            if playedDestination == previousDestination { return false }
        }

        // 5. A real, accepted sacrifice measured on the board: replay the
        // engine's own predicted continuation from the pre-move position
        // (its first element is already `playedUCI`, per condition 1) and
        // require the material deficit to still hold once the line has
        // settled - the longest even-length prefix, where both sides have
        // had their say, exactly `ThemeDetector.punishment`'s rule and for
        // the same reason.
        //
        // An earlier version of this check looked only at k=2 and k=4 and
        // took the largest deficit seen at either point. That mislabeled a
        // real game: a rook offered on move 55 nets White a queen for a
        // rook once the exchange settles, but at k=4 - right after the
        // rook is taken and before the recapture - there is a transient
        // 6-point deficit that cleared the threshold. Reading only the
        // settled position (here, k=6) instead of a fixed early window
        // means a combination that wins material is never mistaken for one
        // that gives it away.
        let line = beforeRank1.principalVariationUCI
        let replayed = ChessGame.replayLine(fromUCI: line, startingFEN: before.fen)
        let settledLength = replayed.count - (replayed.count % 2)
        guard settledLength >= 2 else { return false }

        let preBalance = moverBalance(fen: before.fen, moverIsWhite: moverIsWhite)
        let settledBalance = moverBalance(fen: replayed[settledLength - 1].resultingFEN, moverIsWhite: moverIsWhite)
        let deficit = preBalance - settledBalance
        return deficit >= minimumSacrifice
    }

    private static func moverBalance(fen: String, moverIsWhite: Bool) -> Int {
        let material = ChessGame.material(fen: fen)
        return moverIsWhite ? material.white - material.black : material.black - material.white
    }
}
