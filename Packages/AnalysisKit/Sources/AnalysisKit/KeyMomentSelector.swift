import Foundation

/// Selects which mainline moves get full coaching treatment, per the M5
/// plan's fixed rule: always include every blunder/missedWin, rank the rest
/// by mover win-probability drop, fill to at least 3 (when available) and
/// cap at 8, then present chronologically. An empty result is a legitimate
/// outcome (a clean game).
///
/// When the report knows which player the user is, only that player's moves
/// are candidates. This is a review-your-own-games app: the opponent's
/// mistakes competed for the same eight slots, so a user's own third-worst
/// move could be pushed out by a move they did not play. It also made the
/// report disagree with itself, because `TrainingCardFactory` already
/// filtered to the user's side afterwards - the register would list eight
/// moments and Practice would then offer three cards with no explanation.
public enum KeyMomentSelector {
    public static func selectPlies(classifications: [MoveClassification], input: ReportInput, register: RatingRegister = .advanced) -> [Int] {
        let candidateKinds: Set<MoveClassification> = [.inaccuracy, .mistake, .blunder, .missedWin]
        let mustInclude: Set<MoveClassification> = [.blunder, .missedWin]

        let userIsWhite: Bool? = if input.isUser(isWhite: true) {
            true
        } else if input.isUser(isWhite: false) {
            false
        } else {
            nil
        }

        var drops: [(ply: Int, drop: Double, classification: MoveClassification)] = []
        for (offset, classification) in classifications.enumerated() {
            let ply = offset + 1
            guard candidateKinds.contains(classification) else { continue }
            if let userIsWhite, input.moverIsWhite(atPly: ply) != userIsWhite { continue }
            guard let fact = ThemeDetector.evalSwing(input: input, ply: ply, classification: classification) else { continue }
            let drop = fact.moverWinProbabilityBefore - fact.moverWinProbabilityAfter
            drops.append((ply, drop, classification))
        }

        let required = drops.filter { mustInclude.contains($0.classification) }
        var optional = drops.filter { !mustInclude.contains($0.classification) }
        if register.prefersNameableConsequences {
            // Beginner register: prefer optional moments a learner can name
            // a consequence for (something was hung, a mate was missed or
            // allowed) over the raw win-probability drop, without ever
            // filtering anything out - a game with no such moments still
            // fills from the drop-sorted pool.
            func hasConsequence(_ ply: Int) -> Bool {
                ThemeDetector.punishment(input: input, ply: ply) != nil
                    || ThemeDetector.ignoredThreat(input: input, ply: ply) != nil
                    || ThemeDetector.missedMate(input: input, ply: ply) != nil
                    || ThemeDetector.allowedMate(input: input, ply: ply) != nil
            }
            optional.sort {
                let lhs = hasConsequence($0.ply)
                let rhs = hasConsequence($1.ply)
                if lhs != rhs { return lhs && !rhs }
                return $0.drop > $1.drop
            }
        } else {
            optional.sort { $0.drop > $1.drop }
        }

        var selected = Set(required.map(\.ply))
        // Every blunder/missedWin is always kept, so the cap only bounds
        // how many optional (inaccuracy/mistake) fill-ins join them; it
        // never drops a required moment. Filling all the way to the cap
        // (rather than stopping once 3 is reached) is what makes "at least
        // 3" actually a floor rather than a target: with 10 available
        // candidates the report should show the 8 biggest drops, not just 3.
        let cap = max(register.keyMomentCap, required.count)
        for candidate in optional {
            if selected.count >= cap { break }
            selected.insert(candidate.ply)
        }

        return selected.sorted()
    }
}
