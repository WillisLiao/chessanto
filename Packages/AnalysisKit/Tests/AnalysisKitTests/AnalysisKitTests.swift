import Testing
@testable import AnalysisKit

struct AnalysisKitTests {
    @Test func placeholder() {
        #expect(true)
    }
}

struct WinProbabilityTests {
    @Test func zeroCentipawnsIsFiftyPercent() {
        #expect(abs(WinProbability.fromCentipawns(0) - 50) < 0.001)
    }

    @Test func workedExampleValues() {
        // From the fixed-conventions worked example: +50cp before, -250cp after.
        #expect(abs(WinProbability.fromCentipawns(50) - 54.6) < 0.05)
        #expect(abs(WinProbability.fromCentipawns(-250) - 28.5) < 0.05)
    }

    @Test func mateScoresPinToExtremes() {
        #expect(WinProbability.fromMate(3) == 100)
        #expect(WinProbability.fromMate(-2) == 0)
    }

    @Test func moverPerspectiveFlipsForBlack() {
        #expect(WinProbability.moverWinProbability(whiteWinProbability: 70, whiteToMove: true) == 70)
        #expect(WinProbability.moverWinProbability(whiteWinProbability: 70, whiteToMove: false) == 30)
    }
}

struct AccuracyTests {
    @Test func zeroDropIsFullAccuracy() {
        #expect(abs(Accuracy.perMove(drop: 0) - 100) < 0.01)
    }

    @Test func dropTwentyMatchesWorkedValue() {
        #expect(abs(Accuracy.perMove(drop: 20) - 40.0) < 0.1)
    }

    @Test func clampsToZero() {
        #expect(Accuracy.perMove(drop: 1000) == 0)
    }

    @Test func averagesPerMoveAccuracies() {
        #expect(Accuracy.average([100, 50, 0]) == 50)
        #expect(Accuracy.average([]) == 0)
    }
}

struct MoveClassifierTests {
    private func eval(cp: Int? = nil, mate: Int? = nil, best: String? = nil) -> PlyEvaluation {
        PlyEvaluation(scoreCentipawns: cp, mateIn: mate, bestMoveUCI: best)
    }

    /// Inverts `WinProbability.fromCentipawns` to find a cp value producing
    /// approximately the given white win probability, via bisection.
    private func inverseCP(for winP: Double) -> Int {
        var low = -3000.0
        var high = 3000.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if WinProbability.fromCentipawns(Int(mid)) < winP {
                low = mid
            } else {
                high = mid
            }
        }
        return Int((low + high) / 2)
    }

    /// Classifies a single white move going from `beforeWinP` to `afterWinP`
    /// mover (white) win probability, played move not matching engine best.
    private func classifyByWinP(before beforeWinP: Double, after afterWinP: Double) -> MoveClassification {
        let evals = [
            eval(cp: inverseCP(for: beforeWinP), best: "z0z0"),
            eval(cp: inverseCP(for: afterWinP))
        ]
        return MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )[0]
    }

    @Test func bestMoveByUCIMatch() {
        let evals = [eval(cp: 30, best: "e2e4"), eval(cp: 30)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result == [.best])
    }

    @Test func workedExampleIsClassifiedAsMistake() {
        // White's move: +50cp before, -250cp after; drop 26.1 -> Mistake.
        let evals = [eval(cp: 50, best: "d2d4"), eval(cp: -250)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result == [.mistake])
    }

    @Test func blackBlunderComputesDropFromBlackSide() {
        // A huge white-perspective cp swing in White's favor after Black's
        // move means Black's own win probability collapsed, so this must be
        // a blunder from Black's side even though the classifier only ever
        // sees white-perspective cp.
        let evals = [eval(cp: 0, best: "a7a6"), eval(cp: 600)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e7e5"], whiteToMove: [false]
        )
        #expect(result == [.blunder])
    }

    @Test func dropBandBoundaries() {
        // Margins are kept away from the exact 2/10/20/30 thresholds since
        // the win-probability -> cp inversion used to construct fixtures has
        // limited (integer-cp) resolution; each pair still straddles a band
        // edge closely enough to prove the boundary is in the right place.
        #expect(classifyByWinP(before: 50, after: 48.5) == .excellent) // drop 1.5
        #expect(classifyByWinP(before: 50, after: 47.5) == .good) // drop 2.5
        #expect(classifyByWinP(before: 50, after: 40.5) == .good) // drop 9.5
        #expect(classifyByWinP(before: 50, after: 39.5) == .inaccuracy) // drop 10.5
        #expect(classifyByWinP(before: 50, after: 30.5) == .inaccuracy) // drop 19.5
        #expect(classifyByWinP(before: 50, after: 29.5) == .mistake) // drop 20.5
        #expect(classifyByWinP(before: 50, after: 20.5) == .mistake) // drop 29.5
        #expect(classifyByWinP(before: 50, after: 19.5) == .blunder) // drop 30.5
    }

    @Test func missedWinFiresWhenLargeAdvantageCollapses() {
        let evals = [eval(cp: 900, best: "z0z0"), eval(cp: 100)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result == [.missedWin])
    }

    @Test func missedWinDoesNotFireWhenAdvantageStaysHigh() {
        let evals = [eval(cp: 900, best: "z0z0"), eval(cp: 800)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result != [.missedWin])
    }

    @Test func missedWinFiresFromMateBefore() {
        let evals = [eval(mate: 3, best: "z0z0"), eval(cp: 50)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result == [.missedWin])
    }

    @Test func matePliesClassifyByWinProbabilityCollapse() {
        // Mate delivered against the mover counts as winP 0 after.
        let evals = [eval(cp: 0, best: "z0z0"), eval(mate: -1)]
        let result = MoveClassifier.classify(
            positionEvaluations: evals, playedUCIs: ["e2e4"], whiteToMove: [true]
        )
        #expect(result == [.blunder])
    }
}
