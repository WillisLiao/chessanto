import Foundation

/// Selects which mainline moves get full coaching treatment, per the M5
/// plan's fixed rule: always include every blunder/missedWin, rank the rest
/// by mover win-probability drop, fill to at least 3 (when available) and
/// cap at 8, then present chronologically. An empty result is a legitimate
/// outcome (a clean game).
public enum KeyMomentSelector {
    public static func selectPlies(classifications: [MoveClassification], input: ReportInput) -> [Int] {
        let candidateKinds: Set<MoveClassification> = [.inaccuracy, .mistake, .blunder, .missedWin]
        let mustInclude: Set<MoveClassification> = [.blunder, .missedWin]

        var drops: [(ply: Int, drop: Double, classification: MoveClassification)] = []
        for (offset, classification) in classifications.enumerated() {
            let ply = offset + 1
            guard candidateKinds.contains(classification) else { continue }
            guard let fact = ThemeDetector.evalSwing(input: input, ply: ply, classification: classification) else { continue }
            let drop = fact.moverWinProbabilityBefore - fact.moverWinProbabilityAfter
            drops.append((ply, drop, classification))
        }

        let required = drops.filter { mustInclude.contains($0.classification) }
        let optional = drops.filter { !mustInclude.contains($0.classification) }
            .sorted { $0.drop > $1.drop }

        var selected = Set(required.map(\.ply))
        // Every blunder/missedWin is always kept, so the cap only bounds
        // how many optional (inaccuracy/mistake) fill-ins join them; it
        // never drops a required moment. Filling all the way to the cap
        // (rather than stopping once 3 is reached) is what makes "at least
        // 3" actually a floor rather than a target: with 10 available
        // candidates the report should show the 8 biggest drops, not just 3.
        let cap = max(8, required.count)
        for candidate in optional {
            if selected.count >= cap { break }
            selected.insert(candidate.ply)
        }

        return selected.sorted()
    }
}
