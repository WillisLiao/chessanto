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

    /// Fires when the post-move position's rank-1 PV starts with a capture.
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

        let postMaterial = ChessGame.material(fen: postMove.fen)
        let finalFEN = replayed.last?.resultingFEN ?? postMove.fen
        let finalMaterial = ChessGame.material(fen: finalFEN)

        func balance(_ material: (white: Int, black: Int), favoring color: PieceColor) -> Int {
            let mine = color == .white ? material.white : material.black
            let theirs = color == .white ? material.black : material.white
            return mine - theirs
        }

        let netGainForOpponent = balance(finalMaterial, favoring: opponentColor) - balance(postMaterial, favoring: opponentColor)
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
