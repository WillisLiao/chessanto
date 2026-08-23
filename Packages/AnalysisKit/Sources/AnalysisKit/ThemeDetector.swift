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

    /// Structural characteristics of a played mainline move at ply `p` (1-based):
    /// - Whether it was a capture (and what kind of piece was taken)
    /// - Whether it delivered check or checkmate
    /// - Whether it moved an already-developed piece again in the opening (pre-move fullmove <= 10)
    /// - Whether the same piece moved twice before that side castled (pre-move fullmove <= 10)
    /// - Whether the queen first left its starting square before move five (moves 1-4 / plies 1-8)
    public static func moveQuality(input: ReportInput, ply p: Int) -> MoveQualityFact? {
        guard p >= 1, p < input.plies.count, let playedUCI = input.plies[p].playedUCI else {
            return nil
        }
        guard let tracking = trackMainline(input: input, upToPly: p),
            tracking.replayed.uci == playedUCI
        else {
            return nil
        }

        let replayed = tracking.replayed
        let movedPieceKind = tracking.pieceBeforeCurrentMove.kind
        let capturedPieceKind = replayed.capturedPieceKind
        let isCapture = (capturedPieceKind != nil)
        let isCheck = replayed.isCheck || replayed.isCheckmate
        let isCheckmate = replayed.isCheckmate

        let moveCountBeforeCurrentMove = tracking.pieceBeforeCurrentMove.moveCount
        let moverCastledBeforeCurrentMove = tracking.pieceBeforeCurrentMove.color == .white
            ? tracking.whiteCastledBeforePlyP
            : tracking.blackCastledBeforePlyP

        let isPiece = (movedPieceKind != .pawn && movedPieceKind != .king)
        let isOpeningPhase = tracking.preMoveFullmoveNumber <= 10
        let hasMovedBefore = (moveCountBeforeCurrentMove >= 1)

        let isRedevelopedPiece = isOpeningPhase && isPiece && hasMovedBefore
        let isMovedTwiceBeforeCastling = isOpeningPhase && isPiece && hasMovedBefore && !moverCastledBeforeCurrentMove

        let isEarlyQueenMove = movedPieceKind == .queen
            && tracking.pieceBeforeCurrentMove.isOriginalQueen
            && tracking.fromSquare == (tracking.pieceBeforeCurrentMove.color == .white ? "d1" : "d8")
            && tracking.preMoveFullmoveNumber < 5
            && moveCountBeforeCurrentMove == 0

        return MoveQualityFact(
            ply: p,
            movedPieceKind: movedPieceKind,
            isCapture: isCapture,
            capturedPieceKind: capturedPieceKind,
            isCheck: isCheck,
            isCheckmate: isCheckmate,
            isRedevelopedPiece: isRedevelopedPiece,
            isMovedTwiceBeforeCastling: isMovedTwiceBeforeCastling,
            isEarlyQueenMove: isEarlyQueenMove
        )
    }

    private struct MainlineTracking {
        let pieceBeforeCurrentMove: TrackedPiece
        let whiteCastledBeforePlyP: Bool
        let blackCastledBeforePlyP: Bool
        let fromSquare: String
        let preMoveFullmoveNumber: Int
        let replayed: ReplayedMove
    }

    private struct TrackedPiece: Equatable {
        var kind: PieceKind
        let color: PieceColor
        var moveCount: Int
        let isOriginalQueen: Bool
    }

    private struct ParsedUCI {
        let from: String
        let to: String
        let promotion: PieceKind?
    }

    private static func parseUCI(_ uci: String) -> ParsedUCI? {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5,
            ("a"..."h").contains(chars[0]), ("1"..."8").contains(chars[1]),
            ("a"..."h").contains(chars[2]), ("1"..."8").contains(chars[3])
        else {
            return nil
        }
        let promotion: PieceKind?
        if chars.count == 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        } else {
            promotion = nil
        }
        return ParsedUCI(from: String(chars[0...1]), to: String(chars[2...3]), promotion: promotion)
    }

    private static func fenFields(_ fen: String) -> [String]? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 6,
            let halfmoveClock = Int(fields[4]), halfmoveClock >= 0,
            let fullmoveNumber = Int(fields[5]), fullmoveNumber > 0
        else {
            return nil
        }
        return fields
    }

    private static func sideToMove(in fen: String) -> PieceColor? {
        guard let fields = fenFields(fen) else { return nil }
        switch fields[1] {
        case "w": return .white
        case "b": return .black
        default: return nil
        }
    }

    private static func fullmoveNumber(in fen: String) -> Int? {
        guard let fields = fenFields(fen), let number = Int(fields[5]), number > 0 else {
            return nil
        }
        return number
    }

    private static func positionMatches(
        replayedFEN: String,
        expectedFEN: String,
        allowingEnPassantHalfmoveCorrection: Bool
    ) -> Bool {
        guard let replayed = fenFields(replayedFEN), let expected = fenFields(expectedFEN),
            replayed[0...2] == expected[0...2],
            replayed[5] == expected[5]
        else {
            return false
        }

        let halfmoveMatches = replayed[4] == expected[4]
            || (allowingEnPassantHalfmoveCorrection && replayed[4] == "1" && expected[4] == "0")
        guard halfmoveMatches else { return false }

        // The persisted game rows historically store "-" after a double
        // pawn push even when ChessGame emits the transient target square.
        // Preserve strict validation for every other position field while
        // accepting that known storage normalization. ChessCore also reports
        // a halfmove clock of 1 for a real en-passant capture, while the
        // semantic FEN counter is 0; that exact correction is allowed only
        // for the tracked pawn diagonal capture onto an empty square.
        return replayed[3] == expected[3] || (expected[3] == "-" && replayed[3] != "-")
    }

    private static func parsePieceBoard(fen: String) -> [String: (kind: PieceKind, color: PieceColor)]? {
        guard let fields = fenFields(fen) else { return nil }
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }

        var board: [String: (kind: PieceKind, color: PieceColor)] = [:]
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for (rankIndex, rankString) in ranks.enumerated() {
            let rank = 8 - rankIndex
            var fileIndex = 0
            for character in rankString {
                if let emptySquares = character.wholeNumberValue {
                    guard (1...8).contains(emptySquares), fileIndex + emptySquares <= 8 else { return nil }
                    fileIndex += emptySquares
                    continue
                }

                let piece: (kind: PieceKind, color: PieceColor)
                switch character {
                case "P": piece = (.pawn, .white)
                case "N": piece = (.knight, .white)
                case "B": piece = (.bishop, .white)
                case "R": piece = (.rook, .white)
                case "Q": piece = (.queen, .white)
                case "K": piece = (.king, .white)
                case "p": piece = (.pawn, .black)
                case "n": piece = (.knight, .black)
                case "b": piece = (.bishop, .black)
                case "r": piece = (.rook, .black)
                case "q": piece = (.queen, .black)
                case "k": piece = (.king, .black)
                default: return nil
                }
                guard fileIndex < 8 else { return nil }
                board["\(files[fileIndex])\(rank)"] = piece
                fileIndex += 1
            }
            guard fileIndex == 8 else { return nil }
        }
        return board
    }

    private static func parseInitialBoard(fen: String) -> [String: TrackedPiece]? {
        guard let pieces = parsePieceBoard(fen: fen) else { return nil }
        var board: [String: TrackedPiece] = [:]
        for (square, piece) in pieces {
            board[square] = TrackedPiece(
                kind: piece.kind,
                color: piece.color,
                moveCount: 0,
                isOriginalQueen: piece.kind == .queen
                    && ((piece.color == .white && square == "d1") || (piece.color == .black && square == "d8"))
            )
        }
        return board
    }

    private static func boardMatchesFEN(_ board: [String: TrackedPiece], fen: String) -> Bool {
        guard let expected = parsePieceBoard(fen: fen), expected.count == board.count else { return false }
        for (square, piece) in expected {
            guard let tracked = board[square], tracked.kind == piece.kind, tracked.color == piece.color else {
                return false
            }
        }
        return true
    }

    private static func trackMainline(input: ReportInput, upToPly p: Int) -> MainlineTracking? {
        guard p >= 1, p < input.plies.count,
            let initialBoard = parseInitialBoard(fen: input.plies[0].fen),
            sideToMove(in: input.plies[0].fen) != nil,
            fullmoveNumber(in: input.plies[0].fen) != nil
        else {
            return nil
        }

        var board = initialBoard
        var whiteCastled = false
        var blackCastled = false

        for k in 1...p {
            guard let uci = input.plies[k].playedUCI, let parsed = parseUCI(uci) else { return nil }
            let preMoveFEN = input.plies[k - 1].fen
            let postMoveFEN = input.plies[k].fen
            guard let expectedColor = sideToMove(in: preMoveFEN),
                let preMoveFullmoveNumber = fullmoveNumber(in: preMoveFEN),
                input.moverIsWhite(atPly: k) == (expectedColor == .white),
                fenFields(postMoveFEN) != nil,
                fullmoveNumber(in: postMoveFEN) != nil,
                boardMatchesFEN(board, fen: preMoveFEN)
            else {
                return nil
            }
            let replayedMoves = ChessGame.replayLine(fromUCI: [uci], startingFEN: preMoveFEN)
            guard replayedMoves.count == 1,
                let replayed = replayedMoves.first,
                replayed.movedPieceColor == expectedColor,
                replayed.uci == uci,
                let source = board[parsed.from],
                source.color == expectedColor,
                source.kind == replayed.movedPieceKind
            else {
                return nil
            }

            let isEnPassantCapture = source.kind == .pawn
                && replayed.capturedPieceKind != nil
                && board[parsed.to] == nil
                && parsed.from.first != parsed.to.first
            guard positionMatches(
                replayedFEN: replayed.resultingFEN,
                expectedFEN: postMoveFEN,
                allowingEnPassantHalfmoveCorrection: isEnPassantCapture
            ) else {
                return nil
            }

            let sourceBeforeCurrentMove = source
            let whiteCastledBeforePlyP = whiteCastled
            let blackCastledBeforePlyP = blackCastled

            guard applyTrackedMove(
                board: &board,
                parsed: parsed,
                replayed: replayed,
                whiteCastled: &whiteCastled,
                blackCastled: &blackCastled
            ), boardMatchesFEN(board, fen: postMoveFEN) else {
                return nil
            }

            if k == p {
                return MainlineTracking(
                    pieceBeforeCurrentMove: sourceBeforeCurrentMove,
                    whiteCastledBeforePlyP: whiteCastledBeforePlyP,
                    blackCastledBeforePlyP: blackCastledBeforePlyP,
                    fromSquare: parsed.from,
                    preMoveFullmoveNumber: preMoveFullmoveNumber,
                    replayed: replayed
                )
            }
        }

        return nil
    }

    private static func applyTrackedMove(
        board: inout [String: TrackedPiece],
        parsed: ParsedUCI,
        replayed: ReplayedMove,
        whiteCastled: inout Bool,
        blackCastled: inout Bool
    ) -> Bool {
        guard var piece = board.removeValue(forKey: parsed.from) else { return false }

        if let capturedKind = replayed.capturedPieceKind {
            if let captured = board[parsed.to] {
                guard captured.kind == capturedKind, captured.color != piece.color else { return false }
                board.removeValue(forKey: parsed.to)
            } else {
                // The only legal capture onto an empty destination is a pawn's
                // diagonal en-passant capture. ChessGame has already verified
                // the move, so this branch only updates the identity map.
                guard piece.kind == .pawn,
                    parsed.from.first != parsed.to.first,
                    let capturedSquare = enPassantSquare(from: parsed.from, to: parsed.to),
                    let captured = board[capturedSquare],
                    captured.kind == .pawn,
                    captured.color != piece.color
                else {
                    return false
                }
                board.removeValue(forKey: capturedSquare)
            }
        } else {
            guard board[parsed.to] == nil else { return false }
        }

        piece.moveCount += 1
        if let promotion = parsed.promotion {
            guard piece.kind == .pawn else { return false }
            piece.kind = promotion
            piece.moveCount = 0
        }
        board[parsed.to] = piece

        let isKingSideCastle = replayed.san.hasPrefix("O-O") && !replayed.san.hasPrefix("O-O-O")
        let isQueenSideCastle = replayed.san.hasPrefix("O-O-O")
        guard isKingSideCastle || isQueenSideCastle || piece.kind != .king || !replayed.san.hasPrefix("O-") else {
            return false
        }
        if isKingSideCastle || isQueenSideCastle {
            let rookFrom: String
            let rookTo: String
            switch (piece.color, isKingSideCastle) {
            case (.white, true): rookFrom = "h1"; rookTo = "f1"
            case (.white, false): rookFrom = "a1"; rookTo = "d1"
            case (.black, true): rookFrom = "h8"; rookTo = "f8"
            case (.black, false): rookFrom = "a8"; rookTo = "d8"
            }
            guard var rook = board.removeValue(forKey: rookFrom), rook.kind == .rook, rook.color == piece.color, board[rookTo] == nil else {
                return false
            }
            rook.moveCount += 1
            board[rookTo] = rook
            if piece.color == .white {
                whiteCastled = true
            } else {
                blackCastled = true
            }
        }
        return true
    }

    private static func enPassantSquare(from: String, to: String) -> String? {
        guard let rank = from.last, let file = to.first else { return nil }
        return "\(file)\(rank)"
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
