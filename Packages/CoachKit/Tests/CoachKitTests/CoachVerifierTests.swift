import AnalysisKit
import ChessCore
import Foundation
import Testing

@testable import CoachKit

private enum TestFixtureError: Error { case missingResource }

private func loadFixtureInput() throws -> ReportInput {
    guard let url = Bundle.module.url(forResource: "real-fixture-game-report-input", withExtension: "json") else {
        throw TestFixtureError.missingResource
    }
    return try JSONDecoder().decode(ReportInput.self, from: Data(contentsOf: url))
}

private func anchor(for input: ReportInput, plyIndex: Int) -> CoachVerifier.Anchor {
    let ply = input.plies[plyIndex]
    let lines = ply.lines.map {
        CoachVerifier.VerifiedLine(
            scoreCentipawnsWhitePerspective: $0.scoreCentipawns,
            mateInWhitePerspective: $0.mateIn,
            principalVariationUCI: $0.principalVariationUCI
        )
    }
    return CoachVerifier.Anchor(fen: ply.fen, lines: lines)
}

/// The full context a real narration response for this fixture would be
/// checked against: every key moment's pre/post anchors plus every
/// percentage the rule-based text is allowed to state.
private func contextForFullReport(_ report: GameReport, input: ReportInput) -> CoachVerifier.Context {
    var anchors: [CoachVerifier.Anchor] = []
    var knownWinProbabilities: [Double] = [report.whiteAccuracy.rounded(), report.blackAccuracy.rounded()]
    if let opening = report.opening, let deviationPly = opening.deviationPly {
        anchors.append(anchor(for: input, plyIndex: deviationPly - 1))
        anchors.append(anchor(for: input, plyIndex: deviationPly))
    }
    for moment in report.keyMoments {
        anchors.append(anchor(for: input, plyIndex: moment.ply - 1))
        anchors.append(anchor(for: input, plyIndex: moment.ply))
        knownWinProbabilities.append(moment.evalSwing.moverWinProbabilityBefore.rounded())
        knownWinProbabilities.append(moment.evalSwing.moverWinProbabilityAfter.rounded())
    }
    return CoachVerifier.Context(anchors: anchors, knownWinProbabilities: knownWinProbabilities)
}

@Suite(.serialized)
struct CoachVerifierTests {

    // MARK: - The M5 golden report must pass its own verifier

    @Test func realFixtureGoldenReportPassesWithZeroViolations() async throws {
        let input = try loadFixtureInput()
        let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        #expect(report != nil)
        guard let report else { return }
        let rendered = ReportText.render(report)
        let context = contextForFullReport(report, input: input)
        let verdict = await CoachVerifier.verify(text: rendered, context: context)
        if case .violations(let violations) = verdict {
            Issue.record("expected zero violations, got: \(violations.map(\.description))")
        }
    }

    // MARK: - Planted violations

    @Test func inventedLineIsRejected() async throws {
        let context = CoachVerifier.Context(anchors: [
            .init(fen: startFEN, lines: [.init(scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil, principalVariationUCI: ["e2e4", "e7e5"])])
        ])
        let verdict = await CoachVerifier.verify(text: "1. Qh5 Ke7 2. Qxe5#", context: context)
        guard case .violations(let violations) = verdict else {
            Issue.record("expected violations for an illegal invented line")
            return
        }
        #expect(!violations.isEmpty)
    }

    @Test func wrongEvalIsRejected() async throws {
        let context = CoachVerifier.Context(
            anchors: [.init(fen: startFEN, lines: [.init(scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil, principalVariationUCI: ["e2e4"])])],
            knownEvalsCentipawns: [30]
        )
        let verdict = await CoachVerifier.verify(text: "This position is around +5.0 for White.", context: context)
        guard case .violations(let violations) = verdict else {
            Issue.record("expected a wrong-eval violation")
            return
        }
        #expect(violations.contains { $0.description.contains("+5.0") })
    }

    @Test func correctEvalIsAccepted() async throws {
        let context = CoachVerifier.Context(
            anchors: [.init(fen: startFEN, lines: [.init(scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil, principalVariationUCI: ["e2e4"])])],
            knownEvalsCentipawns: [30]
        )
        let verdict = await CoachVerifier.verify(text: "This position is around +0.3 for White.", context: context)
        #expect(verdict == .verified("This position is around +0.3 for White."))
    }

    @Test func wrongMateCountIsRejected() async throws {
        let context = CoachVerifier.Context(anchors: [], knownMates: [3])
        let verdict = await CoachVerifier.verify(text: "White has mate in 7 here.", context: context)
        guard case .violations(let violations) = verdict else {
            Issue.record("expected a wrong-mate-count violation")
            return
        }
        #expect(!violations.isEmpty)
    }

    @Test func correctMateCountIsAccepted() async throws {
        let context = CoachVerifier.Context(anchors: [], knownMates: [3])
        let verdict = await CoachVerifier.verify(text: "White has mate in 3 here.", context: context)
        #expect(verdict == .verified("White has mate in 3 here."))
    }

    // MARK: - Fact 15's suffix-trust trap: truth comes from UCI re-replay, never the SAN path's own flags

    @Test func correctCheckmateSuffixOnRealMateIsAccepted() async throws {
        // Fool's mate: 1. f3 e5 2. g4 Qh4#
        var game = ChessGame()
        var index = game.startIndex
        for san in ["f3", "e5", "g4"] {
            index = game.playMove(san: san, at: index)!
        }
        let preMoveFEN = game.fen(at: index)!
        let postIndex = game.playMove(san: "Qh4", at: index)!
        let postMoveFEN = game.fen(at: postIndex)!
        let context = CoachVerifier.Context(anchors: [.init(fen: preMoveFEN, lines: []), .init(fen: postMoveFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "3... Qh4#", context: context)
        #expect(verdict == .verified("3... Qh4#"))
    }

    @Test func bareCheckmateMoveWithNoSuffixMakesNoClaimAndIsAccepted() async throws {
        var game = ChessGame()
        var index = game.startIndex
        for san in ["f3", "e5", "g4"] {
            index = game.playMove(san: san, at: index)!
        }
        let preMoveFEN = game.fen(at: index)!
        let postIndex = game.playMove(san: "Qh4", at: index)!
        let postMoveFEN = game.fen(at: postIndex)!
        let context = CoachVerifier.Context(anchors: [.init(fen: preMoveFEN, lines: []), .init(fen: postMoveFEN, lines: [])])
        // No number marker, single bare token that isn't a plain 2-char
        // square (it's a piece move), so it's a real move claim, not exempt -
        // but with no +/# suffix it makes no check/mate claim to verify.
        let verdict = await CoachVerifier.verify(text: "3... Qh4", context: context)
        #expect(verdict == .verified("3... Qh4"))
    }

    @Test func spuriousCheckSuffixOnQuietMoveIsRejected() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "1. e4+", context: context)
        guard case .violations(let violations) = verdict else {
            Issue.record("expected a spurious-check violation for 1. e4+")
            return
        }
        #expect(violations.contains { $0.description.contains("e4+") })
    }

    @Test func plusSuffixOnAnActualCheckmateIsRejectedAsImprecise() async throws {
        // The suffix must match the UCI-replay-derived state exactly:
        // isCheck and isCheckmate are mutually exclusive, so "+" on a mate
        // (should have been "#") is a real mismatch, not a lenient pass.
        var game = ChessGame()
        var index = game.startIndex
        for san in ["f3", "e5", "g4"] {
            index = game.playMove(san: san, at: index)!
        }
        let preMoveFEN = game.fen(at: index)!
        let postIndex = game.playMove(san: "Qh4", at: index)!
        let postMoveFEN = game.fen(at: postIndex)!
        let context = CoachVerifier.Context(anchors: [.init(fen: preMoveFEN, lines: []), .init(fen: postMoveFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "3... Qh4+", context: context)
        guard case .violations(let violations) = verdict else {
            Issue.record("expected a violation for Qh4+ on an actual checkmate")
            return
        }
        #expect(violations.contains { $0.description.contains("checkmate, not a plain check") })
    }

    // MARK: - Bare-square exemption

    @Test func loneSquareReferenceWithNoNumberOrSuffixIsExempt() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])])
        let verdict = await CoachVerifier.verify(text: "The knight on c6 is strong.", context: context)
        #expect(verdict == .verified("The knight on c6 is strong."))
    }

    @Test func numberedBareSquareIsNotExemptAndMustBeLegal() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])])
        // "27. z9" isn't even a legal token shape, but a numbered pawn move
        // to an occupied/illegal square must still be checked, not waved
        // through as a square reference.
        let verdict = await CoachVerifier.verify(text: "1. e5", context: context)
        guard case .violations = verdict else {
            Issue.record("expected 1. e5 (illegal from the start position) to be rejected, not exempted")
            return
        }
    }

    // MARK: - Zero-style castling tolerance (fact 15's bonus tolerance)

    @Test func zeroStyleCastlingIsAccepted() async throws {
        var game = ChessGame()
        var index = game.startIndex
        for san in ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"] {
            index = game.playMove(san: san, at: index)!
        }
        let preFEN = game.fen(at: index)!
        let postIndex = game.playMove(san: "O-O", at: index)!
        let postFEN = game.fen(at: postIndex)!
        let context = CoachVerifier.Context(anchors: [
            .init(fen: preFEN, lines: []),
            .init(fen: postFEN, lines: []),
        ])
        let verdict = await CoachVerifier.verify(text: "7. 0-0", context: context)
        #expect(verdict == .verified("7. 0-0"))
    }

    // MARK: - UCI-space prefix matching against real stored PVs

    @Test func citedSANLineMatchingRankedPVUCIPrefixIsAccepted() async throws {
        let input = try loadFixtureInput()
        // Ply 10's rank-1 PV starting SAN, taken from the real fixture.
        let ply = input.plies[9]
        guard let rank1 = ply.rank1 else {
            Issue.record("fixture ply 10 missing rank1")
            return
        }
        let sans = ChessGame.sanLine(fromUCI: rank1.principalVariationUCI, startingFEN: ply.fen)
        #expect(!sans.isEmpty)
        let context = CoachVerifier.Context(anchors: [anchor(for: input, plyIndex: 9)])
        let verdict = await CoachVerifier.verify(text: "Best is \(sans.first!).", context: context)
        #expect(verdict == .verified("Best is \(sans.first!)."))
    }

    // MARK: - Fresh verification via the engine tool

    private struct StubExecutor: EngineToolExecutor {
        let result: EngineToolResult
        func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult { result }
    }

    @Test func lineNotInAnyStoredPVIsVerifiedFreshViaExecutorOnce() async throws {
        var game = ChessGame()
        let index = game.startIndex
        let played = game.playMove(san: "d4", at: index)!
        let resultingFEN = game.fen(at: played)!
        let stub = StubExecutor(result: EngineToolResult(
            resultingFEN: resultingFEN,
            scoreCentipawnsWhitePerspective: 25,
            mateInWhitePerspective: nil,
            evalLabel: "+0.3",
            principalVariationUCI: ["d2d4"],
            principalVariationSAN: ["d4"],
            depth: 12
        ))
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [])], engineExecutor: stub)
        let verdict = await CoachVerifier.verify(text: "1. d4", context: context)
        #expect(verdict == .verified("1. d4"))
    }

    @Test func lineWithNoMatchAndNoExecutorIsRejected() async throws {
        let context = CoachVerifier.Context(anchors: [.init(fen: startFEN, lines: [.init(scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil, principalVariationUCI: ["e2e4"])])])
        // d4 is legal but not in the stored PV, and there's no executor -
        // must be rejected, not silently accepted.
        let verdict = await CoachVerifier.verify(text: "1. d4", context: context)
        guard case .violations = verdict else {
            Issue.record("expected 1. d4 to be rejected with no matching PV and no executor")
            return
        }
    }
}

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
