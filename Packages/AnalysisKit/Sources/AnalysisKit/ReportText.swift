import ChessCore
import Foundation

/// Renders a `GameReport` to display text using fixed template functions.
/// Every chess-meaningful token interpolates a typed Fact field - there is
/// no free-composed chess prose here (that's M6's LLM, behind
/// `CoachVerifier`).
public enum ReportText {
    public static func render(_ report: GameReport) -> String {
        var lines: [String] = []
        lines.append(header(report))
        lines.append("")
        lines.append(contentsOf: classificationSection(report))
        if let opening = report.opening {
            lines.append("")
            lines.append(openingLine(opening, report: report))
        }
        lines.append("")
        lines.append("Key moments:")
        if report.keyMoments.isEmpty {
            lines.append("No significant mistakes at this analysis depth.")
        } else {
            for moment in report.keyMoments {
                lines.append(contentsOf: momentLines(moment, report: report))
            }
        }
        lines.append("")
        lines.append("Takeaways:")
        for takeaway in report.takeaways {
            lines.append("- \(takeaway)")
        }
        return lines.joined(separator: "\n")
    }

    private static func header(_ report: GameReport) -> String {
        "\(report.whiteName) (\(pct(report.whiteAccuracy))% accuracy) vs \(report.blackName) (\(pct(report.blackAccuracy))% accuracy). Result: \(report.result)."
    }

    private static func classificationSection(_ report: GameReport) -> [String] {
        [
            "\(report.whiteName): \(countsText(report.whiteClassificationCounts))",
            "\(report.blackName): \(countsText(report.blackClassificationCounts))",
        ]
    }

    private static func countsText(_ counts: [ClassificationCount]) -> String {
        guard !counts.isEmpty else { return "no analyzed moves" }
        return counts.map { "\($0.count) \(label(for: $0.classification))" }.joined(separator: ", ")
    }

    private static func label(for classification: MoveClassification) -> String {
        switch classification {
        case .best: return "best"
        case .brilliant: return "brilliant"
        case .excellent: return "excellent"
        case .good: return "good"
        case .inaccuracy: return "inaccuracies"
        case .mistake: return "mistakes"
        case .blunder: return "blunders"
        case .missedWin: return "missed wins"
        }
    }

    private static func openingLine(_ opening: OpeningFact, report: GameReport) -> String {
        var text = "Opening: \(opening.name) (\(opening.eco))."
        if let deviationSAN = opening.deviationSAN, let deviationPly = opening.deviationPly {
            let deviatingIsWhite = deviationPly % 2 == 1
            let player = playerLabel(report: report, isWhite: deviatingIsWhite)
            text += " \(player) left book on move \(moveNumberLabel(ply: deviationPly, moverIsWhite: deviatingIsWhite)) with \(deviationSAN)."
        }
        return text
    }

    private static func momentLines(_ moment: KeyMoment, report: GameReport) -> [String] {
        var text = evalSwingSentence(moment.evalSwing, report: report)
        if let betterMove = moment.betterMove {
            text += " " + betterMoveSentence(betterMove)
        }
        if let punishment = moment.punishment {
            text += " " + punishmentSentence(punishment)
        }
        if let missedMate = moment.missedMate {
            text += " " + missedMateSentence(missedMate)
        }
        if let allowedMate = moment.allowedMate {
            text += " " + allowedMateSentence(allowedMate)
        }
        return ["- \(text)"]
    }

    private static func evalSwingSentence(_ fact: EvalSwingFact, report: GameReport) -> String {
        let player = playerLabel(report: report, isWhite: fact.moverIsWhite)
        let moveLabel = moveNumberLabel(ply: fact.ply, moverIsWhite: fact.moverIsWhite)
        return "\(moveLabel) \(fact.playedSAN) drops \(possessive(player)) winning chances from \(pct(fact.moverWinProbabilityBefore))% to \(pct(fact.moverWinProbabilityAfter))%."
    }

    private static func betterMoveSentence(_ fact: BetterMoveFact) -> String {
        let evalLabel = EvalLabel.format(scoreCentipawns: fact.preMoveScoreCentipawns, mateIn: fact.preMoveMateIn)
        var text = "Better was \(fact.bestMoveSAN)"
        if fact.lineSANs.count > 1 {
            text += " (\(fact.lineSANs.joined(separator: " ")))"
        }
        text += ", keeping the evaluation around \(evalLabel)."
        return text
    }

    private static func punishmentSentence(_ fact: PunishmentFact) -> String {
        let pieceValue = value(of: fact.capturedPieceKind)
        let materialClause: String
        if fact.netMaterialGainForOpponent >= pieceValue {
            materialClause = " winning the \(fact.capturedPieceKind.rawValue)"
        } else if fact.netMaterialGainForOpponent > 0 {
            materialClause = " winning material"
        } else {
            materialClause = ""
        }
        if fact.capturesJustMovedPiece {
            return "This left it where it could be taken: \(fact.refutingSAN)\(materialClause)."
        } else {
            return "This also left the \(fact.capturedPieceKind.rawValue) on \(fact.capturedSquare) hanging: \(fact.refutingSAN)\(materialClause)."
        }
    }

    private static func missedMateSentence(_ fact: MissedMateFact) -> String {
        var text = "This missed a forced mate in \(fact.mateInN)"
        if let line = fact.matingLineSANs {
            text += " (\(line.joined(separator: " ")))"
        }
        return text + "."
    }

    private static func allowedMateSentence(_ fact: AllowedMateFact) -> String {
        var text = "This allowed a forced mate in \(fact.mateInN) for the opponent"
        if let line = fact.matingLineSANs {
            text += " (\(line.joined(separator: " ")))"
        }
        return text + "."
    }

    private static func playerLabel(report: GameReport, isWhite: Bool) -> String {
        let name = isWhite ? report.whiteName : report.blackName
        if let username = report.chessComUsername, !username.isEmpty, name.caseInsensitiveCompare(username) == .orderedSame {
            return "you"
        }
        return name
    }

    /// "you" takes "your"; a name takes "'s" - both grammatically correct,
    /// a rendering choice only.
    private static func possessive(_ label: String) -> String {
        label == "you" ? "your" : "\(label)'s"
    }

    private static func moveNumberLabel(ply: Int, moverIsWhite: Bool) -> String {
        let moveNumber = (ply + 1) / 2
        return moverIsWhite ? "\(moveNumber)." : "\(moveNumber)..."
    }

    private static func pct(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func value(of kind: PieceKind) -> Int {
        switch kind {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }
}
