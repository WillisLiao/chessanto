import Foundation
import Testing

@testable import AnalysisKit

/// The M5 plan's step-4 golden test: the full pipeline (builder + templates
/// + auditor) run over real per-ply analysis rows from a genuine chess.com
/// game (MagnusCarlsen vs artin10862, analyzed at Standard quality through
/// the real app - see the M5 devlog), asserted against a committed golden
/// report text. Template wording changes must consciously update the golden.
private func loadFixtureInput() throws -> ReportInput {
    guard let url = Bundle.module.url(forResource: "real-fixture-game-report-input", withExtension: "json") else {
        throw TestFixtureError.missingResource
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ReportInput.self, from: data)
}

private enum TestFixtureError: Error {
    case missingResource
}

@Test func realFixtureGameProducesTheCommittedGoldenReport() throws {
    let input = try loadFixtureInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
    #expect(report != nil)
    guard let report else { return }

    let rendered = ReportText.render(report)

    guard let goldenURL = Bundle.module.url(forResource: "real-fixture-game-golden-report", withExtension: "txt") else {
        Issue.record("missing golden fixture")
        return
    }
    let golden = try String(contentsOf: goldenURL, encoding: .utf8)
    #expect(rendered == golden.trimmingCharacters(in: .newlines))
}

@Test func realFixtureGameProducesTheCommittedBeginnerGoldenReport() throws {
    let input = try loadFixtureInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared, register: .beginner)
    #expect(report != nil)
    guard let report else { return }

    let rendered = ReportText.render(report)

    guard let goldenURL = Bundle.module.url(forResource: "real-fixture-game-golden-report-beginner", withExtension: "txt") else {
        Issue.record("missing beginner golden fixture")
        return
    }
    let golden = try String(contentsOf: goldenURL, encoding: .utf8)
    #expect(rendered == golden.trimmingCharacters(in: .newlines))
}

@Test func realFixtureGameAuditDropsNothing() throws {
    let input = try loadFixtureInput()
    let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
    #expect(report != nil)
    guard let report else { return }

    // Every key moment survived FactAuditor.audit inside ReportBuilder
    // already (a dropped moment would simply be absent); re-running the
    // auditor here must be a no-op re-confirming each surviving fact.
    for moment in report.keyMoments {
        #expect(FactAuditor.verify(moment.evalSwing, input: input))
        if let betterMove = moment.betterMove {
            #expect(FactAuditor.verify(betterMove, input: input))
        }
        if let punishment = moment.punishment {
            #expect(FactAuditor.verify(punishment, input: input))
        }
        if let ignoredThreat = moment.ignoredThreat {
            #expect(FactAuditor.verify(ignoredThreat, input: input))
        }
        if let fork = moment.fork {
            #expect(FactAuditor.verify(fork, input: input))
        }
        if let missedMate = moment.missedMate {
            #expect(FactAuditor.verify(missedMate, input: input))
        }
        if let allowedMate = moment.allowedMate {
            #expect(FactAuditor.verify(allowedMate, input: input))
        }
    }
}

@Test func realFixtureGameIgnoredThreatsScannedAcrossAllPlies() throws {
    let input = try loadFixtureInput()
    var fires: [(ply: Int, fact: IgnoredThreatFact)] = []
    for p in 1..<input.plies.count {
        if let fact = ThemeDetector.ignoredThreat(input: input, ply: p) {
            fires.append((p, fact))
        }
    }
    // Hand-verification of every fire in the real fixture game:
    // In this 55-ply game (MagnusCarlsen vs artin10862), let's inspect all fires.
    print("Real fixture ignoredThreat fires count: \(fires.count)")
    for (p, fact) in fires {
        let mover = input.moverIsWhite(atPly: p) ? "White" : "Black"
        let moveNum = (p + 1) / 2
        let moveLabel = input.moverIsWhite(atPly: p) ? "\(moveNum)." : "\(moveNum)..."
        print("Fire at ply \(p) (\(mover) move \(moveLabel) played \(input.plies[p].playedUCI ?? "")): threatened \(fact.threatenedSAN), isMate: \(fact.isCheckmate), piece: \(String(describing: fact.capturedPieceKind)), square: \(String(describing: fact.capturedSquare)), gain: \(fact.netMaterialGainForOpponent)")
    }
}

@Test func realFixtureGameForksScannedAcrossAllPlies() throws {
    let input = try loadFixtureInput()
    var fires: [(ply: Int, fact: ForkFact)] = []
    for p in 1..<input.plies.count {
        if let fact = ThemeDetector.fork(input: input, ply: p) {
            fires.append((p, fact))
        }
    }
    print("Real fixture fork fires count: \(fires.count)")
    for (p, fact) in fires {
        let mover = input.moverIsWhite(atPly: p) ? "White" : "Black"
        let moveNum = (p + 1) / 2
        let moveLabel = input.moverIsWhite(atPly: p) ? "\(moveNum)." : "\(moveNum)..."
        let targets = fact.targets.map { "\($0.kind.rawValue)@\($0.square)" }.joined(separator: ", ")
        print("Fire at ply \(p) (\(mover) move \(moveLabel) played \(input.plies[p].playedUCI ?? "")): \(fact.forkingPieceKind.rawValue)@\(fact.destinationSquare) targets [\(targets)], won \(fact.wonTarget.kind.rawValue)@\(fact.wonTarget.square), gain \(fact.netMaterialGain)")
    }
}
