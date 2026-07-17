import AnalysisKit
import ChessCore
import Foundation

/// Layer 1 (PLAN.md's Verified Coach): a compact, Codable snapshot of one
/// key moment (or the whole game) built entirely from `ReportInput`/
/// `GameReport` values already produced and audited by M5's pipeline - no
/// new chess computation happens here, only copying and SAN/eval
/// formatting. This is a quality aid for the LLM; `CoachVerifier` is the
/// actual gate.
public struct CoachRankedLinePayload: Codable, Sendable {
    public let rank: Int
    public let evalLabel: String
    public let scoreCentipawnsWhitePerspective: Int?
    public let mateInWhitePerspective: Int?
    public let principalVariationUCI: [String]
    public let principalVariationSAN: [String]
    public let depth: Int
}

public struct CoachFactsPayload: Codable, Sendable {
    public let betterMove: BetterMoveFact?
    public let punishment: PunishmentFact?
    public let missedMate: MissedMateFact?
    public let allowedMate: AllowedMateFact?
}

public struct CoachMomentPayload: Codable, Sendable {
    public let moveNumberLabel: String
    public let moverName: String
    public let moverIsWhite: Bool
    public let playedSAN: String
    public let playedUCI: String?
    public let classification: MoveClassification
    public let moverWinProbabilityBeforePercent: Double
    public let moverWinProbabilityAfterPercent: Double
    public let preMoveFEN: String
    public let postMoveFEN: String
    public let preMoveLines: [CoachRankedLinePayload]
    public let facts: CoachFactsPayload
}

public struct CoachSummaryPayload: Codable, Sendable {
    public let whiteName: String
    public let blackName: String
    public let result: String
    public let whiteAccuracy: Double
    public let blackAccuracy: Double
    public let whiteClassificationCounts: [ClassificationCount]
    public let blackClassificationCounts: [ClassificationCount]
    public let opening: OpeningFact?
    public let momentOneLiners: [String]
}

/// Adaptive rating register (PLAN.md's "Teaching depth"): three prompt
/// registers, resolved either directly from a fixed `userProfile.ratingBand`
/// or per-game from the user's numeric rating.
public enum RatingRegister: String, Sendable, Codable, CaseIterable {
    case beginner, intermediate, advanced

    /// `ratingBand` is `userProfile.ratingBand` verbatim ("beginner",
    /// "intermediate", "advanced", or "adaptive"). For "adaptive", `userRating`
    /// (the user's rating in *this* game, resolved by the caller from
    /// `GameRecord.whiteRating`/`blackRating` via `chessComUsername`) decides:
    /// <1200 beginner, 1200-1800 intermediate, >1800 advanced, unknown -> intermediate.
    public static func resolve(ratingBand: String, userRating: Int?) -> RatingRegister {
        switch ratingBand {
        case "beginner": return .beginner
        case "intermediate": return .intermediate
        case "advanced": return .advanced
        default:
            guard let userRating else { return .intermediate }
            if userRating < 1200 { return .beginner }
            if userRating <= 1800 { return .intermediate }
            return .advanced
        }
    }
}

public enum CoachPayloadBuilder {
    public static func momentPayload(_ moment: KeyMoment, input: ReportInput) -> CoachMomentPayload {
        let ply = input.plies[moment.ply]
        let preMoveRecord = input.plies[moment.ply - 1]
        let moverIsWhite = moment.evalSwing.moverIsWhite
        let lines = preMoveRecord.lines.map { linePayload($0, fen: preMoveRecord.fen) }
        return CoachMomentPayload(
            moveNumberLabel: moveNumberLabel(ply: moment.ply, moverIsWhite: moverIsWhite),
            moverName: input.playerName(isWhite: moverIsWhite),
            moverIsWhite: moverIsWhite,
            playedSAN: moment.evalSwing.playedSAN,
            playedUCI: ply.playedUCI,
            classification: moment.evalSwing.classification,
            moverWinProbabilityBeforePercent: moment.evalSwing.moverWinProbabilityBefore,
            moverWinProbabilityAfterPercent: moment.evalSwing.moverWinProbabilityAfter,
            preMoveFEN: preMoveRecord.fen,
            postMoveFEN: ply.fen,
            preMoveLines: lines,
            facts: CoachFactsPayload(
                betterMove: moment.betterMove,
                punishment: moment.punishment,
                missedMate: moment.missedMate,
                allowedMate: moment.allowedMate
            )
        )
    }

    public static func summaryPayload(_ report: GameReport) -> CoachSummaryPayload {
        CoachSummaryPayload(
            whiteName: report.whiteName,
            blackName: report.blackName,
            result: report.result,
            whiteAccuracy: report.whiteAccuracy,
            blackAccuracy: report.blackAccuracy,
            whiteClassificationCounts: report.whiteClassificationCounts,
            blackClassificationCounts: report.blackClassificationCounts,
            opening: report.opening,
            momentOneLiners: report.keyMoments.map { ReportText.momentSummary($0, report: report) }
        )
    }

    private static func linePayload(_ line: RankedLine, fen: String) -> CoachRankedLinePayload {
        CoachRankedLinePayload(
            rank: line.rank,
            evalLabel: EvalLabel.format(scoreCentipawns: line.scoreCentipawns, mateIn: line.mateIn),
            scoreCentipawnsWhitePerspective: line.scoreCentipawns,
            mateInWhitePerspective: line.mateIn,
            principalVariationUCI: line.principalVariationUCI,
            principalVariationSAN: ChessGame.sanLine(fromUCI: line.principalVariationUCI, startingFEN: fen),
            depth: line.depth
        )
    }

    private static func moveNumberLabel(ply: Int, moverIsWhite: Bool) -> String {
        let moveNumber = (ply + 1) / 2
        return moverIsWhite ? "\(moveNumber)." : "\(moveNumber)..."
    }
}
