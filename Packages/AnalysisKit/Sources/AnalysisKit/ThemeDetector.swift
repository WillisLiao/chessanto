import ChessCore
import Foundation

/// Deterministic detectors that turn stored analysis + board replay into
/// typed Facts for one mainline move `p` (1-based). Every detector reads
/// only `ReportInput` and replays positions through `ChessGame` - no
/// free-composed chess claims, ever.
public enum ThemeDetector {
    /// The mover's win-probability swing across move `p`. Always producible
    /// once both plies are analyzed - the base fact for every key moment.
    public static func evalSwing(input: ReportInput, ply p: Int, classification: MoveClassification) -> EvalSwingFact? {
        guard p >= 1, p < input.plies.count,
            let before = input.plies[p - 1].rank1,
            let after = input.plies[p].rank1,
            let playedUCI = input.plies[p].playedUCI
        else { return nil }

        let moverIsWhite = input.moverIsWhite(atPly: p)
        let playedSAN = ChessGame.replayLine(fromUCI: [playedUCI], startingFEN: input.plies[p - 1].fen).first?.san
        guard let playedSAN else { return nil }

        let beforeWhiteWinP = WinProbability.whiteWinProbability(
            scoreCentipawns: before.scoreCentipawns, mateIn: before.mateIn
        )
        let afterWhiteWinP = WinProbability.whiteWinProbability(
            scoreCentipawns: after.scoreCentipawns, mateIn: after.mateIn
        )
        return EvalSwingFact(
            ply: p,
            moverIsWhite: moverIsWhite,
            playedSAN: playedSAN,
            moverWinProbabilityBefore: WinProbability.moverWinProbability(whiteWinProbability: beforeWhiteWinP, whiteToMove: moverIsWhite),
            moverWinProbabilityAfter: WinProbability.moverWinProbability(whiteWinProbability: afterWhiteWinP, whiteToMove: moverIsWhite),
            classification: classification
        )
    }

    /// The engine's preferred move at the pre-move position, if it differs
    /// from what was played.
    public static func betterMove(input: ReportInput, ply p: Int) -> BetterMoveFact? {
        guard p >= 1, p < input.plies.count else { return nil }
        let before = input.plies[p - 1]
        guard let rank1 = before.rank1, !rank1.principalVariationUCI.isEmpty else { return nil }
        guard rank1.principalVariationUCI.first != input.plies[p].playedUCI else { return nil }

        let pv = Array(rank1.principalVariationUCI.prefix(6))
        let replayed = ChessGame.replayLine(fromUCI: pv, startingFEN: before.fen)
        guard let bestMoveSAN = replayed.first?.san else { return nil }

        return BetterMoveFact(
            ply: p,
            bestMoveSAN: bestMoveSAN,
            lineSANs: replayed.map(\.san),
            preMoveScoreCentipawns: rank1.scoreCentipawns,
            preMoveMateIn: rank1.mateIn
        )
    }

    /// Fires when the post-move position's rank-1 PV starts with a capture
    /// that actually wins material.
    ///
    /// Two things this deliberately does not do, because it used to and
    /// they were wrong:
    ///
    /// A capture opening the PV is not by itself a punishment. Most
    /// captures are ordinary trades, and firing on all of them produced
    /// "This also left the pawn on d5 hanging: exd5." for an even pawn
    /// exchange. That false fact did not stay in the report either - it fed
    /// the "Material left en prise" practice theme, the Player Brief's
    /// "Loose pieces" motif, and the takeaway rule that triggers on two or
    /// more punishments, so a routine trade became evidence about how the
    /// player plays.
    ///
    /// Material is also not measured at the end of the stored PV. The PV
    /// starts with the opponent's move, so an odd-length line ends right
    /// after the opponent takes something and before the recapture, which
    /// reads as a free piece whenever the line happens to be truncated
    /// there.
    ///
    /// So the board is asked directly rather than inferred from the line's
    /// length: replay the capture, then see whether the side that just lost
    /// the piece can take back on that square. If it cannot, the piece was
    /// undefended and the material is simply won, however short the PV. If
    /// it can, this is an exchange, and it only counts once it has settled
    /// - measured over the longest even-length prefix, where both sides
    /// have had their say.
    ///
    /// A line ending in checkmate bypasses all of it. There is no recapture
    /// to wait for and the material is beside the point.
    public static func punishment(input: ReportInput, ply p: Int) -> PunishmentFact? {
        guard p >= 0, p < input.plies.count else { return nil }
        let postMove = input.plies[p]
        guard let rank1 = postMove.rank1, let playedUCI = postMove.playedUCI, !rank1.principalVariationUCI.isEmpty else {
            return nil
        }
        let replayed = ChessGame.replayLine(fromUCI: rank1.principalVariationUCI, startingFEN: postMove.fen)
        guard let refutingMove = replayed.first, let capturedKind = refutingMove.capturedPieceKind else {
            return nil
        }

        let moverIsWhite = input.moverIsWhite(atPly: p)
        let moverColor: PieceColor = moverIsWhite ? .white : .black
        let opponentColor = moverColor.opposite

        func balance(_ material: (white: Int, black: Int), favoring color: PieceColor) -> Int {
            let mine = color == .white ? material.white : material.black
            let theirs = color == .white ? material.black : material.white
            return mine - theirs
        }

        let netGainForOpponent: Int
        if replayed.last?.isCheckmate == true {
            netGainForOpponent = settledNetGain(
                replayed: replayed,
                plyCount: replayed.count,
                postMoveFEN: postMove.fen,
                opponentColor: opponentColor,
                balance: balance
            )
        } else if !ChessGame.hasLegalMove(
            fen: refutingMove.resultingFEN,
            endingOn: refutingMove.endSquare
        ) {
            // Nothing can take back: the captured piece was undefended, so
            // its full value is won regardless of how far the PV runs.
            netGainForOpponent = pieceValue(capturedKind)
        } else {
            let settledPlyCount = replayed.count - (replayed.count % 2)
            guard settledPlyCount >= 2 else { return nil }
            let gain = settledNetGain(
                replayed: replayed,
                plyCount: settledPlyCount,
                postMoveFEN: postMove.fen,
                opponentColor: opponentColor,
                balance: balance
            )
            guard gain > 0 else { return nil }
            netGainForOpponent = gain
        }

        let playedDestination = String(playedUCI.dropFirst(2).prefix(2))

        return PunishmentFact(
            ply: p,
            refutingSAN: refutingMove.san,
            capturedPieceKind: capturedKind,
            capturedSquare: refutingMove.endSquare,
            capturesJustMovedPiece: refutingMove.endSquare == playedDestination,
            netMaterialGainForOpponent: netGainForOpponent
        )
    }

    /// Material the opponent nets across the first `plyCount` moves of a
    /// replayed line, relative to the position the line starts from.
    private static func settledNetGain(
        replayed: [ReplayedMove],
        plyCount: Int,
        postMoveFEN: String,
        opponentColor: PieceColor,
        balance: ((white: Int, black: Int), PieceColor) -> Int
    ) -> Int {
        guard plyCount >= 1 else { return 0 }
        let settledFEN = replayed[plyCount - 1].resultingFEN
        return balance(ChessGame.material(fen: settledFEN), opponentColor)
            - balance(ChessGame.material(fen: postMoveFEN), opponentColor)
    }

    private static func pieceValue(_ kind: PieceKind) -> Int {
        switch kind {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// True when `record.mateIn` (white-perspective) is a forced mate that
    /// favors whichever side `whiteFavored` selects, excluding the
    /// terminal-mate sentinel (`|mateIn| == 99`, see verified fact 1).
    private static func isMateFor(whiteFavored: Bool, record: RankedLine?) -> Bool {
        guard let mateIn = record?.mateIn, !EvalLabel.isTerminalSentinel(mateIn: mateIn) else { return false }
        return whiteFavored ? mateIn > 0 : mateIn < 0
    }

    /// The pre-move position had a forced mate for the mover that the
    /// played move let slip.
    public static func missedMate(input: ReportInput, ply p: Int) -> MissedMateFact? {
        guard p >= 1, p < input.plies.count else { return nil }
        let before = input.plies[p - 1].rank1
        let after = input.plies[p].rank1
        let moverIsWhite = input.moverIsWhite(atPly: p)

        guard isMateFor(whiteFavored: moverIsWhite, record: before),
            !isMateFor(whiteFavored: moverIsWhite, record: after),
            let mateIn = before?.mateIn
        else { return nil }

        let n = abs(mateIn)
        let pv = before?.principalVariationUCI ?? []
        let replayed = ChessGame.replayLine(fromUCI: pv, startingFEN: input.plies[p - 1].fen)
        let verifiedLine: [String]?
        if let last = replayed.last, last.isCheckmate, replayed.count == 2 * n - 1 {
            verifiedLine = replayed.map(\.san)
        } else {
            verifiedLine = nil
        }
        return MissedMateFact(ply: p, mateInN: n, matingLineSANs: verifiedLine)
    }

    /// The converse: the played move allowed a forced mate for the
    /// opponent that wasn't there before.
    public static func allowedMate(input: ReportInput, ply p: Int) -> AllowedMateFact? {
        guard p >= 1, p < input.plies.count else { return nil }
        let before = input.plies[p - 1].rank1
        let after = input.plies[p].rank1
        let moverIsWhite = input.moverIsWhite(atPly: p)

        guard !isMateFor(whiteFavored: !moverIsWhite, record: before),
            isMateFor(whiteFavored: !moverIsWhite, record: after),
            let mateIn = after?.mateIn
        else { return nil }

        let n = abs(mateIn)
        let pv = after?.principalVariationUCI ?? []
        let replayed = ChessGame.replayLine(fromUCI: pv, startingFEN: input.plies[p].fen)
        let verifiedLine: [String]?
        if let last = replayed.last, last.isCheckmate, replayed.count == 2 * n - 1 {
            verifiedLine = replayed.map(\.san)
        } else {
            verifiedLine = nil
        }
        return AllowedMateFact(ply: p, mateInN: n, matingLineSANs: verifiedLine)
    }
}
