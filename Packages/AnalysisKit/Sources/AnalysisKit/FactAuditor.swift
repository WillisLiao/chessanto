import Foundation

/// Layer 3 of the M5 zero-false-statement design: independently re-derives
/// every attached Fact from `ReportInput` via the same `ThemeDetector`
/// functions used to build it, and drops any that no longer match (a
/// mismatch means a builder/templating bug, not a detector bug, since the
/// detectors themselves are the source of truth). This is the seed of
/// M6's `CoachVerifier`.
public enum FactAuditor {
    public static func verify(_ fact: EvalSwingFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.evalSwing(input: input, ply: fact.ply, classification: fact.classification) else {
            return false
        }
        return fact.playedSAN == expected.playedSAN
            && fact.moverIsWhite == expected.moverIsWhite
            && abs(fact.moverWinProbabilityBefore - expected.moverWinProbabilityBefore) < 0.01
            && abs(fact.moverWinProbabilityAfter - expected.moverWinProbabilityAfter) < 0.01
    }

    public static func verify(_ fact: BetterMoveFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.betterMove(input: input, ply: fact.ply) else { return false }
        return fact.bestMoveSAN == expected.bestMoveSAN
            && fact.lineSANs == expected.lineSANs
            && fact.preMoveScoreCentipawns == expected.preMoveScoreCentipawns
            && fact.preMoveMateIn == expected.preMoveMateIn
    }

    public static func verify(_ fact: PunishmentFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.punishment(input: input, ply: fact.ply) else { return false }
        return fact.refutingSAN == expected.refutingSAN
            && fact.capturedPieceKind == expected.capturedPieceKind
            && fact.capturedSquare == expected.capturedSquare
            && fact.capturesJustMovedPiece == expected.capturesJustMovedPiece
            && fact.netMaterialGainForOpponent == expected.netMaterialGainForOpponent
    }

    public static func verify(_ fact: MissedMateFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.missedMate(input: input, ply: fact.ply) else { return false }
        return fact.mateInN == expected.mateInN && fact.matingLineSANs == expected.matingLineSANs
    }

    public static func verify(_ fact: AllowedMateFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.allowedMate(input: input, ply: fact.ply) else { return false }
        return fact.mateInN == expected.mateInN && fact.matingLineSANs == expected.matingLineSANs
    }

    public static func verify(_ fact: IgnoredThreatFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.ignoredThreat(input: input, ply: fact.ply) else { return false }
        return fact.threatenedSAN == expected.threatenedSAN
            && fact.capturedPieceKind == expected.capturedPieceKind
            && fact.capturedSquare == expected.capturedSquare
            && fact.netMaterialGainForOpponent == expected.netMaterialGainForOpponent
            && fact.isCheckmate == expected.isCheckmate
    }

    public static func verify(_ fact: ForkFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.fork(input: input, ply: fact.ply) else { return false }
        return fact.forkingPieceKind == expected.forkingPieceKind
            && fact.destinationSquare == expected.destinationSquare
            && fact.targets == expected.targets
            && fact.wonTarget == expected.wonTarget
            && fact.netMaterialGain == expected.netMaterialGain
    }

    public static func verify(_ fact: PinFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.pin(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    public static func verify(_ fact: MoveQualityFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.moveQuality(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    public static func verify(_ fact: SkewerFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.skewer(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    public static func verify(_ fact: DiscoveredAttackFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.discoveredAttack(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    public static func verify(_ fact: BackRankWeaknessFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.backRankWeakness(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    public static func verify(_ fact: TrappedPieceFact, input: ReportInput) -> Bool {
        guard let expected = ThemeDetector.trappedPiece(input: input, ply: fact.ply) else { return false }
        return fact == expected
    }

    /// Re-verifies every Fact attached to `moment`, dropping (setting to
    /// `nil`) any that fail. `evalSwing` is the moment's foundation - if it
    /// fails, the whole moment is unsalvageable and `nil` is returned.
    public static func audit(_ moment: KeyMoment, input: ReportInput) -> KeyMoment? {
        guard verify(moment.evalSwing, input: input) else {
            #if DEBUG
            FileHandle.standardError.write("FactAuditor: dropped EvalSwingFact at ply \(moment.ply) (failed re-verification)\n".data(using: .utf8)!)
            #endif
            return nil
        }
        func keep<F>(_ fact: F?, verify: (F) -> Bool, label: String) -> F? {
            guard let fact else { return nil }
            guard verify(fact) else {
                #if DEBUG
                FileHandle.standardError.write("FactAuditor: dropped \(label) at ply \(moment.ply) (failed re-verification)\n".data(using: .utf8)!)
                #endif
                return nil
            }
            return fact
        }
        return KeyMoment(
            ply: moment.ply,
            evalSwing: moment.evalSwing,
            betterMove: keep(moment.betterMove, verify: { verify($0, input: input) }, label: "BetterMoveFact"),
            punishment: keep(moment.punishment, verify: { verify($0, input: input) }, label: "PunishmentFact"),
            ignoredThreat: keep(moment.ignoredThreat, verify: { verify($0, input: input) }, label: "IgnoredThreatFact"),
            fork: keep(moment.fork, verify: { verify($0, input: input) }, label: "ForkFact"),
            missedMate: keep(moment.missedMate, verify: { verify($0, input: input) }, label: "MissedMateFact"),
            allowedMate: keep(moment.allowedMate, verify: { verify($0, input: input) }, label: "AllowedMateFact"),
            moveQuality: keep(moment.moveQuality, verify: { verify($0, input: input) }, label: "MoveQualityFact"),
            pin: keep(moment.pin, verify: { verify($0, input: input) }, label: "PinFact"),
            skewer: keep(moment.skewer, verify: { verify($0, input: input) }, label: "SkewerFact"),
            discoveredAttack: keep(moment.discoveredAttack, verify: { verify($0, input: input) }, label: "DiscoveredAttackFact"),
            backRankWeakness: keep(moment.backRankWeakness, verify: { verify($0, input: input) }, label: "BackRankWeaknessFact"),
            trappedPiece: keep(moment.trappedPiece, verify: { verify($0, input: input) }, label: "TrappedPieceFact")
        )
    }
}
