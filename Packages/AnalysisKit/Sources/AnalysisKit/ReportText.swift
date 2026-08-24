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
        case .book: return "book"
        case .forced: return "forced"
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

    /// The rule-based one-line summary of a single key moment, without the
    /// leading list marker - used both by `render` and (as a Layer 1 input)
    /// by CoachKit's whole-game summary payload.
    public static func momentSummary(_ moment: KeyMoment, report: GameReport, includingMoveLabel: Bool = true) -> String {
        momentLines(moment, report: report, includingMoveLabel: includingMoveLabel)[0]
            .replacingOccurrences(of: "- ", with: "", options: [.anchored])
    }

    private static func momentLines(_ moment: KeyMoment, report: GameReport, includingMoveLabel: Bool = true) -> [String] {
        var text = evalSwingSentence(moment.evalSwing, report: report, includingMoveLabel: includingMoveLabel)
        if let betterMove = moment.betterMove {
            text += " " + betterMoveSentence(betterMove, report: report)
        }
        if let punishment = moment.punishment {
            if let ignored = moment.ignoredThreat, !punishment.capturesJustMovedPiece, punishment.capturedSquare == ignored.capturedSquare {
                // If an ignored threat already explains the loss of this exact piece on this square,
                // the ignored threat sentence provides the more complete explanation of why it happened.
            } else {
                text += " " + punishmentSentence(punishment)
            }
        }
        if let ignoredThreat = moment.ignoredThreat {
            text += " " + ignoredThreatSentence(ignoredThreat)
        }
        if let fork = moment.fork, moment.missedMate == nil, moment.allowedMate == nil {
            text += " " + forkSentence(fork)
        }
        if let missedMate = moment.missedMate {
            text += " " + missedMateSentence(missedMate)
        }
        if let allowedMate = moment.allowedMate {
            text += " " + allowedMateSentence(allowedMate)
        }
        if let moveQuality = moment.moveQuality, let sentence = moveQualitySentence(moveQuality) {
            text += " " + sentence
        }
        return ["- \(text)"]
    }

    private static func evalSwingSentence(_ fact: EvalSwingFact, report: GameReport, includingMoveLabel: Bool = true) -> String {
        let player = playerLabel(report: report, isWhite: fact.moverIsWhite)
        let moveLabel = moveNumberLabel(ply: fact.ply, moverIsWhite: fact.moverIsWhite)
        let prefix = includingMoveLabel ? "\(moveLabel) " : ""
        if report.register.usesWinPercentages {
            return "\(prefix)\(fact.playedSAN) drops \(possessive(player)) winning chances from \(pct(fact.moverWinProbabilityBefore))% to \(pct(fact.moverWinProbabilityAfter))%."
        }

        let before = fact.moverWinProbabilityBefore
        let after = fact.moverWinProbabilityAfter
        let drop = before - after
        let magnitude: String
        if drop >= 20 {
            magnitude = "much worse"
        } else if drop >= 10 {
            magnitude = "worse"
        } else {
            magnitude = "a little worse"
        }

        let opponent = playerLabel(report: report, isWhite: !fact.moverIsWhite)
        func verb(_ label: String) -> String { label == "you" ? "are" : "is" }
        let stateClause: String
        if after >= 70 {
            stateClause = "\(player) \(verb(player)) still winning, just by less"
        } else if after >= 55 {
            stateClause = "\(player) \(verb(player)) still better"
        } else if after >= 45 {
            stateClause = "the position is level now"
        } else if after >= 30 {
            stateClause = "\(opponent) \(verb(opponent)) better now"
        } else {
            stateClause = "\(opponent) \(verb(opponent)) winning now"
        }

        return "\(prefix)\(fact.playedSAN) makes things \(magnitude) for \(player): \(stateClause)."
    }

    private static func betterMoveSentence(_ fact: BetterMoveFact, report: GameReport) -> String {
        let line = Array(fact.lineSANs.prefix(report.register.betterLinePlyCap))
        var text = "Better was \(fact.bestMoveSAN)"
        if line.count > 1 {
            text += " (\(line.joined(separator: " ")))"
        }
        if report.register.showsEvalLabel {
            let evalLabel = EvalLabel.format(scoreCentipawns: fact.preMoveScoreCentipawns, mateIn: fact.preMoveMateIn)
            text += ", keeping the evaluation around \(evalLabel)."
        } else {
            text += "."
        }
        return text
    }

    private static func punishmentSentence(_ fact: PunishmentFact) -> String {
        // A `PunishmentFact` exists only when the opponent nets material
        // over a settled exchange, or when the refuting line ends in
        // checkmate. The mating case can net nothing (or even give material
        // up), and needs no material clause: the SAN already ends in "#".
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

    private static func ignoredThreatSentence(_ fact: IgnoredThreatFact) -> String {
        if fact.isCheckmate {
            return "This ignored the threat of checkmate: \(fact.threatenedSAN)."
        }
        guard let kind = fact.capturedPieceKind, let square = fact.capturedSquare else {
            return "This ignored the threat: \(fact.threatenedSAN)."
        }
        let pieceValue = value(of: kind)
        if fact.netMaterialGainForOpponent >= pieceValue {
            return "This ignored the threat to the \(kind.rawValue) on \(square): \(fact.threatenedSAN) winning the \(kind.rawValue)."
        } else if fact.netMaterialGainForOpponent > 0 {
            return "This ignored the threat to the \(kind.rawValue) on \(square): \(fact.threatenedSAN) winning material."
        } else {
            return "This ignored the threat: \(fact.threatenedSAN)."
        }
    }

    private static func forkSentence(_ fact: ForkFact) -> String {
        let targets = fact.targets
            .map { "\($0.kind.rawValue) on \($0.square)" }
            .joined(separator: " and ")
        return "This fork by the \(fact.forkingPieceKind.rawValue) on \(fact.destinationSquare) attacked \(targets); it won the \(fact.wonTarget.kind.rawValue) on \(fact.wonTarget.square) (net material gain: \(fact.netMaterialGain))."
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

    private static func moveQualitySentence(_ fact: MoveQualityFact) -> String? {
        var clauses: [String] = []
        if fact.isCapture {
            if let capturedPieceKind = fact.capturedPieceKind {
                clauses.append("captured a \(capturedPieceKind.rawValue)")
            } else {
                clauses.append("made a capture")
            }
        }
        if fact.isCheckmate {
            clauses.append("delivered checkmate")
        } else if fact.isCheck {
            clauses.append("delivered check")
        }
        if fact.isMovedTwiceBeforeCastling {
            clauses.append("moved the \(fact.movedPieceKind.rawValue) again before castling")
        } else if fact.isRedevelopedPiece {
            clauses.append("moved the \(fact.movedPieceKind.rawValue) again in the opening")
        }
        if fact.isEarlyQueenMove {
            clauses.append("brought the queen out before move 5")
        }
        guard !clauses.isEmpty else { return nil }
        let body: String
        if clauses.count == 1 {
            body = clauses[0]
        } else {
            body = clauses.dropLast().joined(separator: ", ") + ", and " + clauses.last!
        }
        return "Move quality: \(body)."
    }

    /// "White"/"Black" rather than the player's real name (user decision,
    /// UI/UX redesign session) - color reads faster on a board-focused
    /// report than usernames do, and stays legible for fixtures with
    /// arbitrary online handles. Still says "you" for the user's own game.
    private static func playerLabel(report: GameReport, isWhite: Bool) -> String {
        let name = isWhite ? report.whiteName : report.blackName
        if let username = report.chessComUsername, !username.isEmpty, name.caseInsensitiveCompare(username) == .orderedSame {
            return "you"
        }
        return isWhite ? "White" : "Black"
    }

    /// "you" takes "your"; "White"/"Black" takes "'s" - both grammatically
    /// correct, a rendering choice only.
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
