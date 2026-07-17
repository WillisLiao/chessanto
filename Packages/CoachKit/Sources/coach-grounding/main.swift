import AnalysisKit
import ChessCore
import CoachKit
import Foundation

// Live grounding harness for the M6 Verified Coach (PLAN.md's accept
// criterion + NEXT-SESSION-M6.md's step 6/step 8 gates):
//
//     swift run --package-path Packages/CoachKit coach-grounding
//
// Real Ollama (default qwen3:0.6b, the dev/harness model) + a real
// in-process Stockfish + the committed real fixture game. Also folds in
// step 4's deferred live gate (one legal + one illegal `evaluate()` call),
// since this is the executable NEXT-SESSION-M6.md names as the alternative
// place to run it. Exits non-zero if any *rendered* narration fails
// independent re-verification - fallbacks are expected and fine with a
// 0.6b model; unverified renders are not.

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    log("FAIL: \(message)")
    exit(1)
}

// #filePath = <repo>/Packages/CoachKit/Sources/coach-grounding/main.swift
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let netsDir = repoRoot.appendingPathComponent("App/Resources")
let bigNet = netsDir.appendingPathComponent("nn-1111cefa1111.nnue")
let smallNet = netsDir.appendingPathComponent("nn-37f18f62d772.nnue")
let fixtureURL = repoRoot.appendingPathComponent(
    "Packages/AnalysisKit/Tests/AnalysisKitTests/Resources/real-fixture-game-report-input.json"
)

let model = ProcessInfo.processInfo.environment["COACH_GROUNDING_MODEL"] ?? "qwen3:0.6b"
let narrationCount = Int(ProcessInfo.processInfo.environment["COACH_GROUNDING_N"] ?? "") ?? 10
let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

Task.detached {
    try? await Task.sleep(for: .seconds(600))
    fail("timed out after 600s - Ollama/engine responses are not arriving")
}

Task.detached {
    for net in [bigNet, smallNet] where !FileManager.default.fileExists(atPath: net.path) {
        fail("missing \(net.path) - run scripts/fetch-nnue.sh first")
    }
    guard let fixtureData = try? Data(contentsOf: fixtureURL) else {
        fail("missing fixture at \(fixtureURL.path)")
    }
    let input: ReportInput
    do {
        input = try JSONDecoder().decode(ReportInput.self, from: fixtureData)
    } catch {
        fail("failed to decode fixture: \(error)")
    }

    let ollama = OllamaClient()
    do {
        let version = try await ollama.version()
        log("ollama \(version) reachable")
    } catch {
        fail("Ollama not reachable at 127.0.0.1:11434: \(error)")
    }
    let installed = (try? await ollama.installedModels()) ?? []
    guard installed.contains(where: { $0.name == model }) else {
        fail("model '\(model)' not installed (installed: \(installed.map(\.name))) - pull it first")
    }

    let groundingEngine = GroundingEngine()
    await groundingEngine.start(bigNetPath: bigNet.path, smallNetPath: smallNet.path)
    log("engine started (multipv 3)")

    // Step 4's deferred live gate: one legal + one illegal evaluate() call.
    do {
        let legal = try await groundingEngine.evaluate(fen: startFEN, movesUCI: ["e2e4"])
        log("legal evaluate(): \(legal.evalLabel), pv \(legal.principalVariationSAN.prefix(3).joined(separator: " "))")
        guard legal.scoreCentipawnsWhitePerspective != nil || legal.mateInWhitePerspective != nil else {
            fail("legal evaluate() returned no score")
        }
    } catch {
        fail("legal evaluate() call unexpectedly threw: \(error)")
    }
    do {
        _ = try await groundingEngine.evaluate(fen: startFEN, movesUCI: ["e2e5"])
        fail("illegal evaluate() call (e2e5 from the start position) should have thrown")
    } catch is EngineToolArgumentError {
        log("illegal evaluate() correctly returned a typed argument error")
    } catch {
        fail("illegal evaluate() threw the wrong error type: \(error)")
    }

    guard let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared) else {
        fail("ReportBuilder returned nil for the fixture")
    }
    guard !report.keyMoments.isEmpty else {
        fail("fixture report has no key moments to narrate")
    }
    let momentPayloads = report.keyMoments.map { CoachPayloadBuilder.momentPayload($0, input: input) }

    var totalToolCalls = 0
    var totalViolationsDuringGeneration = 0
    var fallbackCount = 0
    var coachCount = 0
    var leakCount = 0

    for run in 0..<narrationCount {
        let momentIndex = run % report.keyMoments.count
        let moment = report.keyMoments[momentIndex]
        let payload = momentPayloads[momentIndex]
        let fallbackText = ReportText.momentSummary(moment, report: report)

        let narration = await CoachNarrator.narrateMomentPayload(
            payload, register: .intermediate, fallbackText: fallbackText,
            client: ollama, model: model, executor: groundingEngine
        )
        totalToolCalls += narration.toolCallCount
        totalViolationsDuringGeneration += narration.violationCount
        if narration.source == .fallback {
            fallbackCount += 1
        } else {
            coachCount += 1
            // Independent re-verification: re-derive the base context fresh
            // from the payload (not the anchors accumulated during this
            // narration's own tool loop) with a live executor for its
            // fresh-verification hook, and confirm the rendered text still
            // passes. A failure here is a real leak - CoachNarrator
            // rendered something CoachVerifier should never have allowed.
            let freshContext = CoachNarrator.momentVerifierContext(payload: payload)
            var contextWithExecutor = freshContext
            contextWithExecutor.engineExecutor = groundingEngine
            let verdict = await CoachVerifier.verify(text: narration.text, context: contextWithExecutor)
            if case .violations(let violations) = verdict {
                leakCount += 1
                log("LEAK on run \(run) (moment ply \(moment.ply)): \(violations.map(\.description))")
            }
        }
        log("run \(run): source=\(narration.source) toolCalls=\(narration.toolCallCount) violations=\(narration.violationCount)")
    }

    log("--- coach-grounding summary ---")
    log(
        "runs=\(narrationCount) coach=\(coachCount) fallback=\(fallbackCount) toolCalls=\(totalToolCalls) "
            + "violationsDuringGeneration=\(totalViolationsDuringGeneration) leaks=\(leakCount)"
    )

    if leakCount > 0 {
        fail("\(leakCount) rendered narration(s) failed independent re-verification - unverified text would have reached the UI")
    }
    log("OK: zero unverified renders across \(narrationCount) runs (fallbacks are expected with a small model)")

    // --- M7 chat section ---
    // Real CoachChat turns against the real fixture + real Ollama + real
    // Stockfish: a legal-proposal turn, an illegal-proposal turn (must
    // short-circuit via the precheck with zero LLM requests), and an open
    // question (should trigger at least one evaluate() tool call).
    log("--- coach-grounding chat section ---")
    var chatLeakCount = 0
    var chatToolCallTotal = 0
    var chatViolationTotal = 0
    var chatSourceCounts: [String: Int] = [:]

    let chatMoment = report.keyMoments[0]
    let chatPayload = momentPayloads[0]
    let chatFEN = chatPayload.preMoveFEN

    guard let legalLine = chatPayload.preMoveLines.first(where: { $0.rank == 2 }) ?? chatPayload.preMoveLines.first,
        let legalUCI = legalLine.principalVariationUCI.first
    else {
        fail("fixture's first key moment has no ranked lines to build a legal-proposal chat turn from")
    }
    let legalSAN = ChessGame.sanLine(fromUCI: [legalUCI], startingFEN: chatFEN).first ?? legalUCI

    func firstIllegalSAN(fen: String) -> String {
        let candidates = ["Qh8", "Ra8", "Bxh8", "Rxh8", "Qxa8", "Nh8", "Kd7", "Qb8"]
        for candidate in candidates {
            var game = ChessGame(startingFEN: fen)
            if game.playMove(san: candidate, at: game.startIndex) == nil {
                return candidate
            }
        }
        fail("could not find a guaranteed-illegal SAN candidate for \(fen) - extend the candidate list")
    }
    let illegalSAN = firstIllegalSAN(fen: chatFEN)

    let chatContext = CoachChatContext(
        currentFEN: chatFEN,
        isMainlinePosition: true,
        mainlineMovesSAN: [],
        currentPositionLines: chatPayload.preMoveLines.map {
            RankedLine(
                rank: $0.rank, scoreCentipawns: $0.scoreCentipawnsWhitePerspective, mateIn: $0.mateInWhitePerspective,
                principalVariationUCI: $0.principalVariationUCI, depth: $0.depth
            )
        },
        keyMomentOneLiner: ReportText.momentSummary(chatMoment, report: report),
        keyMomentWinProbabilityBeforePercent: chatMoment.evalSwing.moverWinProbabilityBefore,
        keyMomentWinProbabilityAfterPercent: chatMoment.evalSwing.moverWinProbabilityAfter,
        whiteName: report.whiteName, blackName: report.blackName, result: report.result,
        whiteAccuracy: report.whiteAccuracy, blackAccuracy: report.blackAccuracy
    )

    func runChatTurn(label: String, question: String) async -> CoachChatReply {
        let chat = CoachChat(client: ollama, model: model, register: .intermediate, executor: groundingEngine)
        let reply = await chat.send(question: question, context: chatContext)
        chatToolCallTotal += reply.toolCallCount
        chatViolationTotal += reply.violationCount
        chatSourceCounts[reply.source.rawValue, default: 0] += 1
        log("chat[\(label)]: source=\(reply.source) toolCalls=\(reply.toolCallCount) violations=\(reply.violationCount) text=\(reply.text.prefix(160))")
        if reply.source == .coach {
            // Only re-verify actual LLM prose. `.fallback` text is a fixed
            // safe template; `.precheck` text is a closed template that
            // legitimately names the illegal move token it's declining -
            // running it back through CoachVerifier would misfire on that
            // token exactly as intended (it isn't a cited line, it's part
            // of the canned sentence).
            // Independent re-verification with a FRESH context (not this
            // turn's own accumulated anchors) - the same leak check
            // narration gets.
            let freshContext = CoachVerifier.Context(
                anchors: [CoachVerifier.Anchor(
                    fen: chatFEN,
                    lines: chatPayload.preMoveLines.map {
                        CoachVerifier.VerifiedLine(
                            scoreCentipawnsWhitePerspective: $0.scoreCentipawnsWhitePerspective,
                            mateInWhitePerspective: $0.mateInWhitePerspective,
                            principalVariationUCI: $0.principalVariationUCI
                        )
                    }
                )],
                knownWinProbabilities: [
                    chatMoment.evalSwing.moverWinProbabilityBefore.rounded(),
                    chatMoment.evalSwing.moverWinProbabilityAfter.rounded(),
                ],
                engineExecutor: groundingEngine
            )
            let verdict = await CoachVerifier.verify(text: reply.text, context: freshContext)
            if case .violations(let violations) = verdict {
                chatLeakCount += 1
                log("CHAT LEAK [\(label)]: \(violations.map(\.description))")
            }
        }
        return reply
    }

    let legalReply = await runChatTurn(label: "legal-proposal", question: "What if I played \(legalSAN)?")
    guard legalReply.source != .precheck else {
        fail("legal-proposal turn (\(legalSAN)) unexpectedly short-circuited as illegal")
    }

    let illegalReply = await runChatTurn(label: "illegal-proposal", question: "What if I played \(illegalSAN)?")
    guard illegalReply.source == .precheck else {
        fail("illegal-proposal turn (\(illegalSAN)) did not short-circuit via the precheck (source=\(illegalReply.source))")
    }

    let sideLabel = chatMoment.evalSwing.moverIsWhite ? "White" : "Black"
    let openReply = await runChatTurn(label: "open-question", question: "How should \(sideLabel) continue here?")
    if openReply.toolCallCount == 0 {
        log("NOTE: open question produced zero tool calls with model \(model) - the accept criterion may need a larger model (qwen3:8b) to verify live")
    }

    // Concurrent-evaluate probe (fact 3's FIFO gate): fire two evaluate()
    // calls at once and confirm both return sane, non-crashing results.
    async let concurrentA = groundingEngine.evaluate(fen: startFEN, movesUCI: ["e2e4"])
    async let concurrentB = groundingEngine.evaluate(fen: startFEN, movesUCI: ["d2d4"])
    do {
        let (resultA, resultB) = try await (concurrentA, concurrentB)
        guard resultA.scoreCentipawnsWhitePerspective != nil || resultA.mateInWhitePerspective != nil,
            resultB.scoreCentipawnsWhitePerspective != nil || resultB.mateInWhitePerspective != nil
        else {
            fail("concurrent evaluate() calls returned no score")
        }
        log("concurrent evaluate() probe: A=\(resultA.evalLabel) B=\(resultB.evalLabel)")
    } catch {
        fail("concurrent evaluate() calls unexpectedly threw: \(error)")
    }

    log("--- coach-grounding chat summary ---")
    log("chatTurns=3 sources=\(chatSourceCounts) toolCalls=\(chatToolCallTotal) violations=\(chatViolationTotal) leaks=\(chatLeakCount)")

    if chatLeakCount > 0 {
        fail("\(chatLeakCount) rendered chat reply(ies) failed independent re-verification - unverified text would have reached the UI")
    }
    log("OK: zero unverified chat renders")
    exit(0)
}

RunLoop.main.run()
