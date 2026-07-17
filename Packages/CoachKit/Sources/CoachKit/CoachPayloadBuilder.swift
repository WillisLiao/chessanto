import AnalysisKit
import ChessCore
import Foundation

/// Layer 1 (PLAN.md's Verified Coach): a compact, Codable snapshot of one
/// key moment (or the whole game) built entirely from `ReportInput`/
/// `GameReport` values already produced and audited by M5's pipeline - no
/// new chess computation happens here, only copying and SAN/eval
/// formatting. This is a quality aid for the LLM; `CoachVerifier` is the
/// actual gate.
public struct CoachRankedLinePayload: Codable, Sendable, Equatable {
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

/// Plain-value input to `CoachPayloadBuilder.chatPayload`, assembled by the
/// app's view model each turn (M7). Contains no chess computation itself -
/// `mainlineMovesSAN`/`variationMovesSAN` come from `ChessGame.history(upTo:)`
/// (fact 6), `currentPositionLines` from either the cached analysis for the
/// displayed ply or `CoachChat`'s seed evaluation when there is none.
public struct CoachChatContext: Sendable {
    public let currentFEN: String
    public let isMainlinePosition: Bool
    /// SAN of every mainline move up to the current position (if mainline)
    /// or up to the variation's branch point (if not), ply 1 first.
    public let mainlineMovesSAN: [String]
    /// The ply the variation branches from (0 = start position). Only
    /// meaningful when `isMainlinePosition` is false.
    public let variationBranchPly: Int
    /// SAN of the variation moves from `variationBranchPly` to the current
    /// position. Empty when `isMainlinePosition` is true.
    public let variationMovesSAN: [String]
    public let currentPositionLines: [RankedLine]
    public let keyMomentOneLiner: String?
    /// The current key moment's mover win probability before/after, when
    /// the displayed ply is one of the report's key moments - not part of
    /// the serialized payload (`keyMomentOneLiner` already states them in
    /// prose), only used to seed `CoachVerifier.Context.knownWinProbabilities`
    /// so the model is allowed to echo the numbers in the one-liner.
    public let keyMomentWinProbabilityBeforePercent: Double?
    public let keyMomentWinProbabilityAfterPercent: Double?
    public let whiteName: String?
    public let blackName: String?
    public let result: String?
    public let whiteAccuracy: Double?
    public let blackAccuracy: Double?

    public init(
        currentFEN: String,
        isMainlinePosition: Bool,
        mainlineMovesSAN: [String],
        variationBranchPly: Int = 0,
        variationMovesSAN: [String] = [],
        currentPositionLines: [RankedLine] = [],
        keyMomentOneLiner: String? = nil,
        keyMomentWinProbabilityBeforePercent: Double? = nil,
        keyMomentWinProbabilityAfterPercent: Double? = nil,
        whiteName: String? = nil,
        blackName: String? = nil,
        result: String? = nil,
        whiteAccuracy: Double? = nil,
        blackAccuracy: Double? = nil
    ) {
        self.currentFEN = currentFEN
        self.isMainlinePosition = isMainlinePosition
        self.mainlineMovesSAN = mainlineMovesSAN
        self.variationBranchPly = variationBranchPly
        self.variationMovesSAN = variationMovesSAN
        self.currentPositionLines = currentPositionLines
        self.keyMomentOneLiner = keyMomentOneLiner
        self.keyMomentWinProbabilityBeforePercent = keyMomentWinProbabilityBeforePercent
        self.keyMomentWinProbabilityAfterPercent = keyMomentWinProbabilityAfterPercent
        self.whiteName = whiteName
        self.blackName = blackName
        self.result = result
        self.whiteAccuracy = whiteAccuracy
        self.blackAccuracy = blackAccuracy
    }
}

/// The Codable JSON block sent to the LLM each chat turn the position
/// changes (M7's payload/prompt design decision).
public struct CoachChatPayload: Codable, Sendable, Equatable {
    public let fen: String
    public let sideToMoveIsWhite: Bool
    public let isMainlinePosition: Bool
    public let movesSoFarSAN: String
    public let variationPathSAN: String?
    public let currentPositionLines: [CoachRankedLinePayload]
    public let keyMomentSummary: String?
    public let whiteName: String?
    public let blackName: String?
    public let result: String?
    public let whiteAccuracy: Double?
    public let blackAccuracy: Double?
}

public enum CoachPayloadBuilder {
    public static func chatPayload(_ context: CoachChatContext) -> CoachChatPayload {
        let mainlineSAN = numberedSAN(context.mainlineMovesSAN, startingPly: 1)
        let variationSAN: String? = context.isMainlinePosition
            ? nil
            : numberedSAN(context.variationMovesSAN, startingPly: context.variationBranchPly + 1)
        return CoachChatPayload(
            fen: context.currentFEN,
            sideToMoveIsWhite: sideToMoveIsWhite(fen: context.currentFEN),
            isMainlinePosition: context.isMainlinePosition,
            movesSoFarSAN: mainlineSAN,
            variationPathSAN: variationSAN,
            currentPositionLines: context.currentPositionLines.map { linePayload($0, fen: context.currentFEN) },
            keyMomentSummary: context.keyMomentOneLiner,
            whiteName: context.whiteName,
            blackName: context.blackName,
            result: context.result,
            whiteAccuracy: context.whiteAccuracy,
            blackAccuracy: context.blackAccuracy
        )
    }

    private static func sideToMoveIsWhite(fen: String) -> Bool {
        let fields = fen.split(separator: " ")
        guard fields.count > 1 else { return true }
        return fields[1] == "w"
    }

    /// Renders SAN moves as standard numbered notation ("1. e4 e5 2. Nf3
    /// Nc6"), given the 1-based ply index of the first move in `moves`.
    private static func numberedSAN(_ moves: [String], startingPly: Int) -> String {
        var parts: [String] = []
        for (offset, san) in moves.enumerated() {
            let ply = startingPly + offset
            let moveNumber = (ply + 1) / 2
            let isWhiteMove = ply % 2 == 1
            if isWhiteMove {
                parts.append("\(moveNumber). \(san)")
            } else if parts.isEmpty {
                parts.append("\(moveNumber)... \(san)")
            } else {
                parts.append(san)
            }
        }
        return parts.joined(separator: " ")
    }

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
