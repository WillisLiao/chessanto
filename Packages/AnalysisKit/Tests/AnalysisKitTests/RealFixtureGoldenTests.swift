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
        if let moveQuality = moment.moveQuality {
            #expect(FactAuditor.verify(moveQuality, input: input))
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

@Test func realFixtureGameMoveQualityScannedAcrossAllPlies() throws {
    let input = try loadFixtureInput()
    var moveQualityFacts: [(ply: Int, fact: MoveQualityFact)] = []
    for p in 1..<input.plies.count {
        if let fact = ThemeDetector.moveQuality(input: input, ply: p) {
            moveQualityFacts.append((p, fact))
            #expect(FactAuditor.verify(fact, input: input))
        }
    }

    #expect(moveQualityFacts.count == input.plies.count - 1)

    // Hand-verify specific key moves in the MagnusCarlsen vs artin10862 game:
    // Game: 1. d4 d6 2. e4 Nf6 3. Nc3 e5 4. f4 exd4 5. Qxd4 Nbd7 6. Nf3 c6 7. Be3 d5 8. exd5 Bc5 9. Qd3 cxd5 10. O-O-O O-O ...
    //
    // Ply 8 (4... exd4): Pawn capture
    let ply8 = try #require(moveQualityFacts.first(where: { $0.ply == 8 })?.fact)
    #expect(ply8.isCapture == true)
    #expect(ply8.capturedPieceKind == .pawn)
    #expect(ply8.movedPieceKind == .pawn)
    #expect(ply8.isCheck == false)
    #expect(ply8.isRedevelopedPiece == false)

    // Ply 9 (5. Qxd4): White Queen captures d4 on move 5
    // Note: Move 5 is ply 9 -> moveNumber = (9 + 1)/2 = 5 (not before move 5)
    let ply9 = try #require(moveQualityFacts.first(where: { $0.ply == 9 })?.fact)
    #expect(ply9.isCapture == true)
    #expect(ply9.capturedPieceKind == .pawn)
    #expect(ply9.movedPieceKind == .queen)
    #expect(ply9.isEarlyQueenMove == false) // Move 5 is not < 5
    #expect(ply9.isRedevelopedPiece == false) // First queen move

    // Ply 17 (9. Qd3): Queen moves a second time in opening (moves 1-10) before White castled (White castled at ply 19)
    let ply17 = try #require(moveQualityFacts.first(where: { $0.ply == 17 })?.fact)
    #expect(ply17.movedPieceKind == .queen)
    #expect(ply17.isRedevelopedPiece == true)
    #expect(ply17.isMovedTwiceBeforeCastling == true)

    // Ply 21 (11. Nxd5): White Knight (Nf3 or Nc3) captures on d5.
    // Nc3 moved on move 3 (ply 5). On move 11 (ply 21, move 11 > 10, after castling O-O-O at ply 19):
    // Move 11 is past opening phase (ply 21 > 20)
    let ply21 = try #require(moveQualityFacts.first(where: { $0.ply == 21 })?.fact)
    #expect(ply21.isCapture == true)
    #expect(ply21.capturedPieceKind == .pawn)
    #expect(ply21.movedPieceKind == .knight)
    #expect(ply21.isRedevelopedPiece == false) // Ply 21 > 20 is past opening phase
    #expect(ply21.isMovedTwiceBeforeCastling == false) // White already castled at ply 19

    // Ply 43 (22. Qxd8+): Queen capture with check!
    let ply43 = try #require(moveQualityFacts.first(where: { $0.ply == 43 })?.fact)
    #expect(ply43.isCapture == true)
    #expect(ply43.capturedPieceKind == .rook)
    #expect(ply43.isCheck == true)
    #expect(ply43.isCheckmate == false)
}
