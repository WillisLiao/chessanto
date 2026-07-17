import ChessCore
import Foundation

public enum ReportBuilder {
    /// Builds the full coaching report for an analyzed game. Returns `nil`
    /// if the game isn't fully analyzed (every ply needs a rank-1 record)
    /// or has no moves at all.
    public static func build(input: ReportInput, openingBook: OpeningBook) -> GameReport? {
        guard input.isFullyAnalyzed, input.plies.count > 1 else { return nil }

        let moveCount = input.plies.count - 1
        let evaluations: [PlyEvaluation] = input.plies.map { $0.rank1!.rank1Evaluation }
        let playedUCIs: [String] = (1...moveCount).map { input.plies[$0].playedUCI ?? "" }
        let whiteToMove: [Bool] = (1...moveCount).map { input.moverIsWhite(atPly: $0) }

        let classifications = MoveClassifier.classify(
            positionEvaluations: evaluations, playedUCIs: playedUCIs, whiteToMove: whiteToMove
        )

        var whiteAccuracies: [Double] = []
        var blackAccuracies: [Double] = []
        var whiteCounts: [MoveClassification: Int] = [:]
        var blackCounts: [MoveClassification: Int] = [:]

        for p in 1...moveCount {
            let moverIsWhite = whiteToMove[p - 1]
            let classification = classifications[p - 1]
            if moverIsWhite {
                whiteCounts[classification, default: 0] += 1
            } else {
                blackCounts[classification, default: 0] += 1
            }

            let before = evaluations[p - 1]
            let after = evaluations[p]
            let beforeWhiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: before.scoreCentipawns, mateIn: before.mateIn)
            let afterWhiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: after.scoreCentipawns, mateIn: after.mateIn)
            let moverBefore = WinProbability.moverWinProbability(whiteWinProbability: beforeWhiteWinP, whiteToMove: moverIsWhite)
            let moverAfter = WinProbability.moverWinProbability(whiteWinProbability: afterWhiteWinP, whiteToMove: moverIsWhite)
            let drop = max(0, moverBefore - moverAfter)
            let accuracy = Accuracy.perMove(drop: drop)
            if moverIsWhite {
                whiteAccuracies.append(accuracy)
            } else {
                blackAccuracies.append(accuracy)
            }
        }

        let opening = buildOpeningFact(input: input, openingBook: openingBook)

        let selectedPlies = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
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

        let takeaways = buildTakeaways(input: input, keyMoments: keyMoments, opening: opening)

        return GameReport(
            whiteName: input.whiteName,
            blackName: input.blackName,
            result: input.result,
            chessComUsername: input.chessComUsername,
            whiteAccuracy: Accuracy.average(whiteAccuracies),
            blackAccuracy: Accuracy.average(blackAccuracies),
            whiteClassificationCounts: orderedCounts(whiteCounts),
            blackClassificationCounts: orderedCounts(blackCounts),
            opening: opening,
            keyMoments: keyMoments,
            takeaways: takeaways
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

    /// Rule-based, whole-game aggregation (cap 3): a recurring
    /// punishment theme per player, mate awareness, an opening-deviation
    /// note, and a clean-game fallback when nothing else applies.
    private static func buildTakeaways(input: ReportInput, keyMoments: [KeyMoment], opening: OpeningFact?) -> [String] {
        var takeaways: [String] = []

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

        if let missed = keyMoments.first(where: { $0.missedMate != nil }), let fact = missed.missedMate {
            let player = input.playerName(isWhite: missed.evalSwing.moverIsWhite)
            takeaways.append("\(player) missed a forced mate in \(fact.mateInN) on move \(moveNumberLabel(ply: missed.ply, moverIsWhite: missed.evalSwing.moverIsWhite)).")
        }
        if let allowed = keyMoments.first(where: { $0.allowedMate != nil }), let fact = allowed.allowedMate {
            let mover = input.playerName(isWhite: allowed.evalSwing.moverIsWhite)
            takeaways.append("\(mover) allowed a forced mate in \(fact.mateInN) on move \(moveNumberLabel(ply: allowed.ply, moverIsWhite: allowed.evalSwing.moverIsWhite)).")
        }

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
                let whiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: record.scoreCentipawns, mateIn: record.mateIn)
                let label = EvalLabel.format(scoreCentipawns: record.scoreCentipawns, mateIn: record.mateIn)
                _ = whiteWinP
                takeaways.append(
                    "\(deviatingPlayer) left book on move \(moveNumberLabel(ply: deviationPly, moverIsWhite: deviatingIsWhite)) with \(deviationSAN); the engine already preferred \(opponent) soon after (\(label))."
                )
            }
        }

        if takeaways.isEmpty {
            takeaways.append(
                keyMoments.isEmpty
                    ? "A clean game: no mistakes or blunders at this analysis depth."
                    : "No single recurring pattern stood out - see the key moments above for specifics."
            )
        }

        return Array(takeaways.prefix(3))
    }

    private static func moveNumberLabel(ply: Int, moverIsWhite: Bool) -> String {
        let moveNumber = (ply + 1) / 2
        return moverIsWhite ? "\(moveNumber)" : "\(moveNumber)..."
    }
}
