import ChessCore
import Foundation

public enum ReportBuilder {
    /// Builds the full coaching report for an analyzed game. Returns `nil`
    /// if the game isn't fully analyzed (every ply needs a rank-1 record)
    /// or has no moves at all.
    public static func build(input: ReportInput, openingBook: OpeningBook, register: RatingRegister = .advanced) -> GameReport? {
        guard input.isFullyAnalyzed, input.plies.count > 1 else { return nil }

        let moveCount = input.plies.count - 1
        let evaluations: [PlyEvaluation] = input.plies.map { $0.rank1!.rank1Evaluation }
        let playedUCIs: [String] = (1...moveCount).map { input.plies[$0].playedUCI ?? "" }
        let whiteToMove: [Bool] = (1...moveCount).map { input.moverIsWhite(atPly: $0) }

        let classifications = MoveClassifier.classify(
            positionEvaluations: evaluations,
            playedUCIs: playedUCIs,
            whiteToMove: whiteToMove,
            context: ClassificationContext.forGame(input: input, openingBook: openingBook)
        )

        var whiteCounts: [MoveClassification: Int] = [:]
        var blackCounts: [MoveClassification: Int] = [:]

        for p in 1...moveCount {
            let classification = classifications[p - 1]
            if whiteToMove[p - 1] {
                whiteCounts[classification, default: 0] += 1
            } else {
                blackCounts[classification, default: 0] += 1
            }
        }

        // Book and forced moves stay in the win-probability series, because
        // they still shape how sharp the game was, but they are not scored -
        // neither was a decision the player made.
        let whiteWinPercents = evaluations.map {
            WinProbability.whiteWinProbability(scoreCentipawns: $0.scoreCentipawns, mateIn: $0.mateIn)
        }
        let accuracies = Accuracy.game(
            whiteWinPercents: whiteWinPercents,
            moverIsWhite: whiteToMove,
            isScored: classifications.map(\.isPlayerDecision)
        )

        let opening = buildOpeningFact(input: input, openingBook: openingBook)

        let selectedPlies = KeyMomentSelector.selectPlies(classifications: classifications, input: input, register: register)
        var keyMoments: [KeyMoment] = []
        for p in selectedPlies {
            guard let evalSwing = ThemeDetector.evalSwing(input: input, ply: p, classification: classifications[p - 1]) else {
                continue
            }
            let candidate = KeyMoment(
                ply: p,
                evalSwing: evalSwing,
                betterMove: ThemeDetector.betterMove(input: input, ply: p),
                punishment: ThemeDetector.punishment(input: input, ply: p),
                ignoredThreat: ThemeDetector.ignoredThreat(input: input, ply: p),
                missedMate: ThemeDetector.missedMate(input: input, ply: p),
                allowedMate: ThemeDetector.allowedMate(input: input, ply: p)
            )
            if let audited = FactAuditor.audit(candidate, input: input) {
                keyMoments.append(audited)
            }
        }

        func orderedCounts(_ counts: [MoveClassification: Int]) -> [ClassificationCount] {
            MoveClassification.allCases.compactMap { classification in
                guard let count = counts[classification], count > 0 else { return nil }
                return ClassificationCount(classification: classification, count: count)
            }
        }

        let takeaways = buildTakeaways(
            input: input,
            keyMoments: keyMoments,
            whiteCounts: whiteCounts,
            blackCounts: blackCounts,
            opening: opening
        )

        return GameReport(
            whiteName: input.whiteName,
            blackName: input.blackName,
            result: input.result,
            chessComUsername: input.chessComUsername,
            whiteAccuracy: accuracies?.white ?? 0,
            blackAccuracy: accuracies?.black ?? 0,
            whiteClassificationCounts: orderedCounts(whiteCounts),
            blackClassificationCounts: orderedCounts(blackCounts),
            opening: opening,
            keyMoments: keyMoments,
            takeaways: takeaways,
            register: register
        )
    }

    private static func buildOpeningFact(input: ReportInput, openingBook: OpeningBook) -> OpeningFact? {
        let fens = input.plies.map(\.fen)
        guard let match = openingBook.lookup(fens: fens) else { return nil }

        let deviationPly = match.deepestBookPly + 1
        guard deviationPly < input.plies.count, let uci = input.plies[deviationPly].playedUCI else {
            return OpeningFact(eco: match.eco, name: match.name, deepestBookPly: match.deepestBookPly, deviationSAN: nil, deviationPly: nil)
        }
        let replayed = ChessGame.replayLine(fromUCI: [uci], startingFEN: input.plies[deviationPly - 1].fen)
        guard let san = replayed.first?.san else {
            return OpeningFact(eco: match.eco, name: match.name, deepestBookPly: match.deepestBookPly, deviationSAN: nil, deviationPly: nil)
        }
        return OpeningFact(eco: match.eco, name: match.name, deepestBookPly: match.deepestBookPly, deviationSAN: san, deviationPly: deviationPly)
    }

    /// Rule-based, whole-game aggregation (cap 3):
    /// 1. Decisive tactical moments (missed/allowed forced mates)
    /// 2. Recurring tactical blindspots (punishments, ignored threats - 2+ occurrences)
    /// 3. Opening deviation into an unfavorable position
    /// 4. General error frequency (inaccuracies, mistakes, blunders, missed wins)
    /// 5. Clean-game / no-pattern fallback when nothing else fires.
    private static func buildTakeaways(
        input: ReportInput,
        keyMoments: [KeyMoment],
        whiteCounts: [MoveClassification: Int],
        blackCounts: [MoveClassification: Int],
        opening: OpeningFact?
    ) -> [String] {
        var takeaways: [String] = []

        // Priority 1: Missed & Allowed Forced Mates (decisive game-ending misses)
        if let missed = keyMoments.first(where: { $0.missedMate != nil }), let fact = missed.missedMate {
            let player = input.playerName(isWhite: missed.evalSwing.moverIsWhite)
            takeaways.append("\(player) missed a forced mate in \(fact.mateInN) on move \(moveNumberLabel(ply: missed.ply, moverIsWhite: missed.evalSwing.moverIsWhite)).")
        }
        if let allowed = keyMoments.first(where: { $0.allowedMate != nil }), let fact = allowed.allowedMate {
            let mover = input.playerName(isWhite: allowed.evalSwing.moverIsWhite)
            takeaways.append("\(mover) allowed a forced mate in \(fact.mateInN) on move \(moveNumberLabel(ply: allowed.ply, moverIsWhite: allowed.evalSwing.moverIsWhite)).")
        }

        // Priority 2: Recurring Tactical Themes (2+ occurrences)
        for isWhite in [true, false] {
            let player = input.playerName(isWhite: isWhite)
            let punishedMoments = keyMoments.filter {
                $0.evalSwing.moverIsWhite == isWhite && $0.punishment != nil
            }
            guard punishedMoments.count >= 2 else { continue }
            let moveNumbers = punishedMoments.map { moveNumberLabel(ply: $0.ply, moverIsWhite: isWhite) }
            takeaways.append(
                "\(punishedMoments.count) of \(player)'s mistakes left a piece to be captured on the next move (\(moveNumbers.joined(separator: ", ")))."
            )
        }

        for isWhite in [true, false] {
            let player = input.playerName(isWhite: isWhite)
            let ignoredMoments = keyMoments.filter {
                $0.evalSwing.moverIsWhite == isWhite && $0.ignoredThreat != nil
            }
            guard ignoredMoments.count >= 2 else { continue }
            let moveNumbers = ignoredMoments.map { moveNumberLabel(ply: $0.ply, moverIsWhite: isWhite) }
            takeaways.append(
                "\(ignoredMoments.count) of \(player)'s mistakes ignored an active threat from the opponent (\(moveNumbers.joined(separator: ", ")))."
            )
        }

        // Priority 3: Opening Deviation Note
        if let opening, let deviationPly = opening.deviationPly, let deviationSAN = opening.deviationSAN {
            let deviatingIsWhite = input.moverIsWhite(atPly: deviationPly)
            let deviatingPlayer = input.playerName(isWhite: deviatingIsWhite)
            let opponent = input.playerName(isWhite: !deviatingIsWhite)
            let windowEnd = min(deviationPly + 4, input.plies.count - 1)
            if deviationPly <= windowEnd,
                let record = (deviationPly...windowEnd).compactMap({ input.plies[$0].rank1 }).first(where: {
                    let whiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: $0.scoreCentipawns, mateIn: $0.mateIn)
                    let deviatingWinP = WinProbability.moverWinProbability(whiteWinProbability: whiteWinP, whiteToMove: deviatingIsWhite)
                    return deviatingWinP < 45
                })
            {
                let label = EvalLabel.format(scoreCentipawns: record.scoreCentipawns, mateIn: record.mateIn)
                takeaways.append(
                    "\(deviatingPlayer) left book on move \(moveNumberLabel(ply: deviationPly, moverIsWhite: deviatingIsWhite)) with \(deviationSAN); the engine already preferred \(opponent) soon after (\(label))."
                )
            }
        }

        // Priority 4: General Error Frequency
        var errorTakeaways: [(text: String, errorCount: Int, isWhite: Bool)] = []
        if let whiteSummary = errorFrequencyTakeaway(player: input.playerName(isWhite: true), counts: whiteCounts) {
            errorTakeaways.append((text: whiteSummary.text, errorCount: whiteSummary.errorCount, isWhite: true))
        }
        if let blackSummary = errorFrequencyTakeaway(player: input.playerName(isWhite: false), counts: blackCounts) {
            errorTakeaways.append((text: blackSummary.text, errorCount: blackSummary.errorCount, isWhite: false))
        }
        errorTakeaways.sort { a, b in
            if a.errorCount != b.errorCount {
                return a.errorCount > b.errorCount
            }
            return a.isWhite && !b.isWhite
        }
        for entry in errorTakeaways {
            takeaways.append(entry.text)
        }

        // Priority 5: Clean Game / No Pattern Fallback
        if takeaways.isEmpty {
            takeaways.append(
                keyMoments.isEmpty
                    ? "A clean game: no mistakes or blunders at this analysis depth."
                    : "No single recurring pattern stood out - see the key moments above for specifics."
            )
        }

        return Array(takeaways.prefix(3))
    }

    private static func errorFrequencyTakeaway(
        player: String,
        counts: [MoveClassification: Int]
    ) -> (text: String, errorCount: Int, scoredCount: Int)? {
        let scoredCount = counts.reduce(0) { total, pair in
            pair.key.isPlayerDecision ? total + pair.value : total
        }
        guard scoredCount > 0 else { return nil }

        var breakdownItems: [String] = []
        let errorClassifications: [MoveClassification] = [.inaccuracy, .mistake, .blunder, .missedWin]
        var totalErrors = 0

        for classification in errorClassifications {
            guard let count = counts[classification], count > 0 else { continue }
            totalErrors += count
            switch classification {
            case .inaccuracy:
                breakdownItems.append(count == 1 ? "1 inaccuracy" : "\(count) inaccuracies")
            case .mistake:
                breakdownItems.append(count == 1 ? "1 mistake" : "\(count) mistakes")
            case .blunder:
                breakdownItems.append(count == 1 ? "1 blunder" : "\(count) blunders")
            case .missedWin:
                breakdownItems.append(count == 1 ? "1 missed win" : "\(count) missed wins")
            default:
                break
            }
        }

        guard totalErrors > 0 else { return nil }

        let errorNoun = totalErrors == 1 ? "error" : "errors"
        let moveNoun = scoredCount == 1 ? "scored move" : "scored moves"
        let breakdown = breakdownItems.joined(separator: ", ")
        let text = "\(player) made \(totalErrors) \(errorNoun) across \(scoredCount) \(moveNoun) (\(breakdown))."
        return (text: text, errorCount: totalErrors, scoredCount: scoredCount)
    }

    private static func moveNumberLabel(ply: Int, moverIsWhite: Bool) -> String {
        let moveNumber = (ply + 1) / 2
        return moverIsWhite ? "\(moveNumber)" : "\(moveNumber)..."
    }
}
