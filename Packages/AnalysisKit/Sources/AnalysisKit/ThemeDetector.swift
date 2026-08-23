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

    /// Detects a fork only when the moved piece attacks the required valuable
    /// targets and the stored post-move line proves one target is actually
    /// won. Geometry alone is deliberately insufficient: the line must have
    /// an opponent response, the same piece's capture of an original target,
    /// and one reply after that capture, with a settled gain for the mover.
    public static func fork(input: ReportInput, ply p: Int) -> ForkFact? {
        guard p >= 1, p < input.plies.count else { return nil }
        let preMove = input.plies[p - 1]
        let postMove = input.plies[p]
        guard let playedUCI = postMove.playedUCI,
            let played = ChessGame.replayLine(fromUCI: [playedUCI], startingFEN: preMove.fen).first
        else { return nil }

        let playedDestination = String(playedUCI.dropFirst(2).prefix(2))
        guard played.endSquare == playedDestination else { return nil }

        // Use the replayed result rather than trusting a possibly stale FEN
        // record; this is the position the played move actually produced.
        let postForkFEN = played.resultingFEN
        let forkingPieceKind = forkPieceKind(played: played, playedUCI: playedUCI)
        let targets = ChessGame.attackedEnemySquares(from: playedDestination, in: postForkFEN)
            .filter { $0.kind == .king || ($0.kind != .pawn && pieceValue($0.kind) >= 3) }
            .map { ForkTarget(square: $0.square, kind: $0.kind) }
            .sorted {
                let lhsValue = pieceValue($0.kind)
                let rhsValue = pieceValue($1.kind)
                if lhsValue != rhsValue { return lhsValue > rhsValue }
                return $0.square < $1.square
            }
        let nonKingTargets = targets.filter { $0.kind != .king && $0.kind != .pawn && pieceValue($0.kind) >= 3 }
        let forksKing = targets.contains { $0.kind == .king }
        guard nonKingTargets.count >= 2 || (forksKing && !nonKingTargets.isEmpty) else { return nil }

        // Mate facts explain the same ply more directly and take precedence.
        guard missedMate(input: input, ply: p) == nil,
            allowedMate(input: input, ply: p) == nil
        else { return nil }

        guard let rank1 = postMove.rank1, !rank1.principalVariationUCI.isEmpty else { return nil }
        let replayed = ChessGame.replayLine(fromUCI: rank1.principalVariationUCI, startingFEN: postForkFEN)
        guard replayed.count == rank1.principalVariationUCI.count, replayed.count >= 3 else { return nil }

        let moverColor = played.movedPieceColor
        let opponentColor = moverColor.opposite
        let response = replayed[0]
        let capture = replayed[1]
        let reply = replayed[2]
        guard response.movedPieceColor == opponentColor,
            capture.movedPieceColor == moverColor,
            reply.movedPieceColor == opponentColor,
            capture.movedPieceKind == forkingPieceKind,
            String(capture.uci.prefix(2)) == playedDestination,
            let capturedKind = capture.capturedPieceKind,
            let wonTarget = nonKingTargets.first(where: {
                $0.square == capture.endSquare && $0.kind == capturedKind
            })
        else { return nil }

        let beforeMaterial = ChessGame.material(fen: postForkFEN)
        let settledMaterial = ChessGame.material(fen: reply.resultingFEN)
        func balance(_ material: (white: Int, black: Int)) -> Int {
            moverColor == .white ? material.white - material.black : material.black - material.white
        }
        let netGain = balance(settledMaterial) - balance(beforeMaterial)
        guard netGain >= 1 else { return nil }

        return ForkFact(
            ply: p,
            forkingPieceKind: forkingPieceKind,
            destinationSquare: playedDestination,
            targets: targets,
            wonTarget: wonTarget,
            netMaterialGain: netGain
        )
    }

    private static func forkPieceKind(played: ReplayedMove, playedUCI: String) -> PieceKind {
        guard played.movedPieceKind == .pawn, playedUCI.count == 5 else { return played.movedPieceKind }
        switch playedUCI.last {
        case "q": return .queen
        case "r": return .rook
        case "b": return .bishop
        case "n": return .knight
        default: return played.movedPieceKind
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

    /// Fires when the opponent had a concrete threat in the pre-move position
    /// (a capture winning material or an immediate checkmate) that the played
    /// move failed to address, and the opponent executed that threat on the
    /// very next move.
    ///
    /// The operational path asks the board directly rather than inferring from
    /// an engine evaluation or line length:
    ///
    /// 1. We inspect what the opponent actually played on the move immediately
    ///    following the mover's move (`input.plies[p + 1].playedUCI`, if it exists).
    ///    If the game ended or no follow-up move exists, there is no executed
    ///    threat to verify, so we return `nil`.
    ///
    /// 2. We replay the opponent's played move from the post-move position
    ///    (`input.plies[p].fen`) to determine what it achieved: either delivering
    ///    checkmate or capturing a target piece.
    ///
    /// 3. We ask whether that exact same move was already available and winning
    ///    for the opponent one move earlier - in the pre-move position
    ///    (`input.plies[p - 1].fen`) with the side-to-move switched to the opponent.
    ///    Replaying the opponent's move from that pre-move position confirms that:
    ///    - The move was already legal (the line of attack was not opened by the
    ///      mover's move, the attacking piece was not unpinned by the mover, and
    ///      the target piece was already standing on the target square).
    ///    - If the threat was checkmate, it was already checkmate before the move.
    ///    - If the threat was a capture, it targeted the same piece on the same square.
    ///
    /// 4. For captures, we verify that the capture was materially winning both
    ///    before and after the mover's move:
    ///    - An undefended piece is won in full.
    ///    - A defended piece attacked by a lesser-valued piece nets the difference
    ///      in piece values (e.g. Bishop takes Queen on a defended square nets +6).
    ///    - If the mover's move defended the target piece or captured the attacker,
    ///      or if it was an equal exchange (e.g. Bishop takes defended Bishop),
    ///      no material is won and the detector returns `nil`.
    ///
    /// This ensures we only report threats that were genuinely sitting on the board
    /// before the move, ignored by the player, and carried out by the opponent.
    public static func ignoredThreat(input: ReportInput, ply p: Int) -> IgnoredThreatFact? {
        guard p >= 1, p + 1 < input.plies.count else { return nil }
        let preMove = input.plies[p - 1]
        let postMove = input.plies[p]
        let opponentPly = input.plies[p + 1]

        guard let opponentUCI = opponentPly.playedUCI else { return nil }

        let moverIsWhite = input.moverIsWhite(atPly: p)
        let opponentColor: PieceColor = moverIsWhite ? .black : .white

        // 1. Replay the opponent's played move from the post-move position.
        guard let postOpponentMove = ChessGame.replayLine(fromUCI: [opponentUCI], startingFEN: postMove.fen).first else {
            return nil
        }

        // 2. The opponent's move must be a concrete threat execution: either checkmate or a capture.
        let isCheckmate = postOpponentMove.isCheckmate
        let capturedKind = postOpponentMove.capturedPieceKind
        guard isCheckmate || capturedKind != nil else { return nil }

        // 3. Switch active color in pre-move FEN to test if the opponent could already play this move.
        let preMoveOpponentFEN = switchActiveColor(preMove.fen, to: opponentColor)
        guard let preOpponentMove = ChessGame.replayLine(fromUCI: [opponentUCI], startingFEN: preMoveOpponentFEN).first else {
            return nil
        }

        // 4. If checkmate, it must have been an immediate checkmate in the pre-move position as well.
        if isCheckmate {
            guard preOpponentMove.isCheckmate else { return nil }
            return IgnoredThreatFact(
                ply: p,
                threatenedSAN: postOpponentMove.san,
                capturedPieceKind: capturedKind,
                capturedSquare: capturedKind != nil ? postOpponentMove.endSquare : nil,
                netMaterialGainForOpponent: 0,
                isCheckmate: true
            )
        }

        // 5. If a capture, it must have captured the same piece kind on the same square in pre-move.
        guard let targetKind = capturedKind,
            preOpponentMove.capturedPieceKind == targetKind,
            preOpponentMove.endSquare == postOpponentMove.endSquare
        else { return nil }

        let targetSquare = postOpponentMove.endSquare
        let attackerKind = postOpponentMove.movedPieceKind
        let targetValue = pieceValue(targetKind)
        let attackerValue = pieceValue(attackerKind)

        // 6. Calculate whether the capture was materially winning in pre-move.
        let preCanRecapture = ChessGame.hasLegalMove(fen: preOpponentMove.resultingFEN, endingOn: targetSquare)
        let preGain: Int
        if !preCanRecapture {
            preGain = targetValue
        } else if targetValue > attackerValue {
            preGain = targetValue - attackerValue
        } else {
            return nil
        }

        // 7. Calculate whether the capture was still materially winning in post-move.
        let postCanRecapture = ChessGame.hasLegalMove(fen: postOpponentMove.resultingFEN, endingOn: targetSquare)
        let postGain: Int
        if !postCanRecapture {
            postGain = targetValue
        } else if targetValue > attackerValue {
            postGain = targetValue - attackerValue
        } else {
            return nil
        }

        let netGain = min(preGain, postGain)
        guard netGain > 0 else { return nil }

        return IgnoredThreatFact(
            ply: p,
            threatenedSAN: postOpponentMove.san,
            capturedPieceKind: targetKind,
            capturedSquare: targetSquare,
            netMaterialGainForOpponent: netGain,
            isCheckmate: false
        )
    }

    private static func switchActiveColor(_ fen: String, to color: PieceColor) -> String {
        var parts = fen.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return fen }
        parts[1] = color == .white ? "w" : "b"
        if parts.count >= 4 {
            parts[3] = "-"
        }
        return parts.joined(separator: " ")
    }
}
