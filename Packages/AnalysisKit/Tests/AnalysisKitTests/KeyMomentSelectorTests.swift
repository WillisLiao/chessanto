import Testing

@testable import AnalysisKit

/// Builds a synthetic ReportInput where White plays every odd ply and
/// Black's even plies are no-ops (never change the white-perspective win
/// probability, and are always classified `.best` so they're never
/// candidates) - this isolates each white move's win-probability drop from
/// mover-alternation sign flips, so `whiteDrops[k]` is exactly the drop for
/// White's `(k+1)`th move.
private func makeWhiteDropsInput(whiteDrops: [Double], whiteClassifications: [MoveClassification]) -> (ReportInput, [MoveClassification]) {
    func cpFor(winPercent: Double) -> Int {
        var lo = -2000, hi = 2000
        while lo < hi {
            // `lo + (hi - lo) / 2`, not `(lo + hi) / 2`: since `hi - lo` is
            // always >= 0, Int truncating division agrees with floor here,
            // which the naive sum form does not once `lo` goes negative
            // (e.g. lo=-1, hi=0 gives mid=0 forever, an infinite loop).
            let mid = lo + (hi - lo) / 2
            if WinProbability.fromCentipawns(mid) < winPercent {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    var whiteWinPercents: [Double] = [50]
    for drop in whiteDrops {
        let afterWhiteMove = whiteWinPercents.last! - drop
        whiteWinPercents.append(afterWhiteMove)
        whiteWinPercents.append(afterWhiteMove) // Black's no-op ply.
    }

    var plies: [PlyRecord] = []
    for (index, winPercent) in whiteWinPercents.enumerated() {
        let cp = cpFor(winPercent: winPercent)
        let sideToMove = index % 2 == 0 ? "w" : "b"
        // A real (if sparse) legal-looking position - both kings present, a
        // white a2 pawn so the synthetic "a2a3" playedUCI actually replays.
        // An empty (kingless) board previously hung chesskit's check-state
        // computation instead of failing fast.
        let fen = "4k3/8/8/8/8/8/P7/4K3 \(sideToMove) - - 0 1"
        let playedUCI = index == 0 ? nil : "a2a3"
        plies.append(
            PlyRecord(
                fen: fen,
                lines: [RankedLine(rank: 1, scoreCentipawns: cp, mateIn: nil, principalVariationUCI: ["b2b3"], depth: 10)],
                playedUCI: playedUCI
            )
        )
    }
    let input = ReportInput(plies: plies, whiteName: "White", blackName: "Black", result: "*", chessComUsername: nil)

    var classifications: [MoveClassification] = []
    for whiteClassification in whiteClassifications {
        classifications.append(whiteClassification)
        classifications.append(.best)
    }
    return (input, classifications)
}

@Test func emptyCandidatesReturnsEmptySelection() {
    let (input, classifications) = makeWhiteDropsInput(whiteDrops: [1, 1, 1], whiteClassifications: [.best, .best, .best])
    #expect(KeyMomentSelector.selectPlies(classifications: classifications, input: input) == [])
}

@Test func everyBlunderIsAlwaysIncluded() {
    // White's 2nd move (ply 3) is a blunder; the rest are small/no candidates.
    let (input, classifications) = makeWhiteDropsInput(
        whiteDrops: [2, 35, 2],
        whiteClassifications: [.excellent, .blunder, .good]
    )
    let selected = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
    #expect(selected.contains(3))
}

@Test func fillsToAtLeastThreeWhenAvailable() {
    let (input, classifications) = makeWhiteDropsInput(
        whiteDrops: [12, 14, 16, 18],
        whiteClassifications: [.inaccuracy, .inaccuracy, .inaccuracy, .inaccuracy]
    )
    let selected = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
    #expect(selected.count >= 3)
}

@Test func capsAtEightOptionalCandidatesKeepingLargestDrops() {
    // 10 inaccuracies, none required - only the 8 with the largest drops survive.
    let drops = (1...10).map { Double($0) }
    let (input, classifications) = makeWhiteDropsInput(
        whiteDrops: drops,
        whiteClassifications: Array(repeating: .inaccuracy, count: 10)
    )
    let selected = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
    #expect(selected.count == 8)
    // White's kth move is mainline ply 2k - 1; the largest 8 drops are k = 3...10.
    #expect(selected == [5, 7, 9, 11, 13, 15, 17, 19])
}

@Test func requiredMomentsAreNeverDroppedEvenPastTheCap() {
    // 9 blunders - the cap must not drop any of them.
    let drops = (1...9).map { Double($0) * 5 }
    let (input, classifications) = makeWhiteDropsInput(
        whiteDrops: drops,
        whiteClassifications: Array(repeating: .blunder, count: 9)
    )
    let selected = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
    #expect(selected.count == 9)
}

@Test func selectionIsChronological() {
    let (input, classifications) = makeWhiteDropsInput(
        whiteDrops: [40, 10, 60],
        whiteClassifications: [.blunder, .blunder, .blunder]
    )
    let selected = KeyMomentSelector.selectPlies(classifications: classifications, input: input)
    #expect(selected == selected.sorted())
    #expect(selected == [1, 3, 5])
}
