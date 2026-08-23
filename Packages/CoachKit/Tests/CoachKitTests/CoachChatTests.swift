import AnalysisKit
import ChessCore
import Foundation
import Testing

@testable import CoachKit

/// A scripted `OllamaChatStreaming` mock, same shape as `CoachNarratorTests`'
/// (each file needs its own copy since the original is file-private), plus
/// full request capture so tests can inspect exactly what was sent.
private final class MockChatClient: OllamaChatStreaming, @unchecked Sendable {
    enum ScriptedResponse {
        case content(String)
        case toolCall(name: String, arguments: [String: JSONValue])
        case failure
    }

    private var responses: [ScriptedResponse]
    private(set) var requestedMessages: [[OllamaChatMessage]] = []

    init(_ responses: [ScriptedResponse]) {
        self.responses = responses
    }

    var callCount: Int { requestedMessages.count }

    func chat(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaTool]?,
        numCtx: Int,
        temperature: Double
    ) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        requestedMessages.append(messages)
        let next = responses.isEmpty ? ScriptedResponse.content("") : responses.removeFirst()
        return AsyncThrowingStream { continuation in
            switch next {
            case .content(let text):
                continuation.yield(OllamaChatChunk.stub(content: text, done: false))
                continuation.yield(OllamaChatChunk.stub(content: "", done: true))
                continuation.finish()
            case .toolCall(let name, let arguments):
                let call = OllamaToolCall(id: "call_1", function: .init(index: 0, name: name, arguments: arguments))
                continuation.yield(OllamaChatChunk.stub(content: "", toolCalls: [call], done: false))
                continuation.yield(OllamaChatChunk.stub(content: "", done: true))
                continuation.finish()
            case .failure:
                continuation.finish(throwing: OllamaClientError.notReachable)
            }
        }
    }
}

private final class StubExecutor: EngineToolExecutor, @unchecked Sendable {
    /// Keyed by `movesUCI.joined(separator: ",")`; falls back to
    /// `defaultResult` (typically the seed "no moves" evaluate call).
    var resultsByMovesKey: [String: EngineToolResult] = [:]
    var defaultResult: Result<EngineToolResult, Error>
    private(set) var calls: [(fen: String, movesUCI: [String])] = []

    init(default defaultResult: Result<EngineToolResult, Error>) {
        self.defaultResult = defaultResult
    }

    func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
        calls.append((fen, movesUCI))
        if let result = resultsByMovesKey[movesUCI.joined(separator: ",")] {
            return result
        }
        return try defaultResult.get()
    }
}

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

private func sampleContext(fen: String = startFEN, lines: [RankedLine]? = nil) -> CoachChatContext {
    CoachChatContext(
        currentFEN: fen,
        isMainlinePosition: true,
        mainlineMovesSAN: [],
        currentPositionLines: lines ?? [
            RankedLine(rank: 1, scoreCentipawns: 20, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 10)
        ]
    )
}

@Suite(.serialized)
struct CoachChatTests {

    @Test func happyPathReturnsVerifiedCoachReply() async throws {
        let client = MockChatClient([.content("Hello!")])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())
        #expect(reply.source == .coach)
        #expect(reply.text == "Hello!")
    }

    @Test func inflectedConcretePlanWithoutToolCallTriggersViolation() async throws {
        let client = MockChatClient([
            .content("Focus on developing your pieces and controlling the center."),
            .content("Focus on developing your pieces and controlling the center."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())
        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(client.callCount == 2)
    }

    // MARK: - Precheck: illegal proposal never reaches the LLM

    @Test func illegalProposalShortCircuitsWithZeroClientCalls() async throws {
        let client = MockChatClient([.content("should never be used")])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        // Nf6 is not reachable by any white knight from the start position.
        let reply = await chat.send(question: "what about Nf6?", context: sampleContext())
        #expect(reply.source == .precheck)
        #expect(reply.text.contains("Nf6"))
        #expect(reply.text.lowercased().contains("legal"))
        #expect(client.callCount == 0)
    }

    // MARK: - Precheck: legal proposal is pre-evaluated and cited

    @Test func legalProposalIsPreEvaluatedButStillRequiresModelEvaluateForConcreteReply() async throws {
        let executor = StubExecutor(default: .failure(EngineToolArgumentError("unexpected default call")))
        executor.resultsByMovesKey["g1f3"] = EngineToolResult(
            resultingFEN: "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1",
            scoreCentipawnsWhitePerspective: 35, mateInWhitePerspective: nil,
            evalLabel: "+0.4", principalVariationUCI: ["g1f3", "b8c6"], principalVariationSAN: ["Nf3", "Nc6"], depth: 12
        )
        let client = MockChatClient([
            .content("Nf3 develops naturally and keeps things balanced (+0.4)."),
            .content("Nf3 develops naturally and keeps things balanced (+0.4)."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: executor)
        let reply = await chat.send(question: "what about Nf3?", context: sampleContext())

        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(client.callCount == 2)
        let sentUserText = client.requestedMessages[0].last { $0.role == "user" }?.content ?? ""
        #expect(sentUserText.contains("+0.4"))
        #expect(sentUserText.contains("Nf3"))
    }

    // MARK: - Violation -> regeneration -> fallback

    @Test func violationTriggersRegenerationThenFallback() async throws {
        let client = MockChatClient([
            .content("You should play Bxc6 winning a piece (+9.9)."),  // invented eval
            .content("You should play Bxc6 winning a piece (+9.9)."),  // still bad on regeneration
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())
        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(client.callCount == 2)
    }

    // MARK: - Mid-stream failure

    @Test func midStreamClientDeathFallsBackNeverThrows() async throws {
        let client = MockChatClient([.failure])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())
        #expect(reply.source == .fallback)
    }

    // MARK: - Position change -> fresh context block

    @Test func contextBlockIsOmittedWhenPositionUnchangedAndReincludedOnFENChange() async throws {
        let secondFEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        let client = MockChatClient([
            .content("Okay."),
            .content("Thanks."),
            .content("Got it."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)

        _ = await chat.send(question: "hello", context: sampleContext())
        let firstUserText = client.requestedMessages[0].last { $0.role == "user" }?.content ?? ""
        #expect(firstUserText.contains("\"fen\""))

        _ = await chat.send(question: "hello again", context: sampleContext())
        let secondUserText = client.requestedMessages[1].last { $0.role == "user" }?.content ?? ""
        #expect(!secondUserText.contains("\"fen\""))

        _ = await chat.send(question: "and now?", context: sampleContext(fen: secondFEN))
        let thirdUserText = client.requestedMessages[2].last { $0.role == "user" }?.content ?? ""
        #expect(thirdUserText.contains("\"fen\""))
    }

    // MARK: - History pruning and cap

    @Test func historyIsPrunedToPlainTurnsAndCappedAtTwelveMessages() async throws {
        var responses: [MockChatClient.ScriptedResponse] = []
        for _ in 0..<8 {
            responses.append(.content("Okay."))
        }
        let client = MockChatClient(responses)
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)

        for i in 0..<8 {
            _ = await chat.send(question: "question number \(i)", context: sampleContext())
        }

        // system (1) + history (capped at 12) + this turn's user message (1).
        let lastRequest = client.requestedMessages.last!
        #expect(lastRequest.count <= 14)
        #expect(lastRequest.first?.role == "system")
        // No tool or violation-feedback roles should ever survive pruning.
        #expect(lastRequest.allSatisfy { $0.role == "system" || $0.role == "user" || $0.role == "assistant" })
    }

    // MARK: - P4.8 Concreteness gate

    @Test func concreteClaimWithNoToolCallAndNoEngineDataTriggersViolation() async throws {
        // The model answers with a concrete move recommendation without
        // calling the evaluate tool, and no engine lines are in the context.
        // Both attempts produce the same concrete claim -> falls back.
        let client = MockChatClient([
            .content("You should play Nf3 to develop your knight and control the center."),
            .content("You should play Nf3 to develop your knight and control the center."),
        ])
        let noLinesContext = sampleContext(lines: [])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: noLinesContext)
        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(client.callCount == 2)
    }

    @Test func concreteClaimAfterToolCallPassesThrough() async throws {
        // The model correctly calls evaluate first, then gives a concrete answer.
        let executor = StubExecutor(default: .success(EngineToolResult(
            resultingFEN: startFEN, scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
            evalLabel: "+0.3", principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
        )))
        let client = MockChatClient([
            .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN)]),
            .content("You should play 1. e4 to control the center (+0.3)."),
        ])
        let noLinesContext = sampleContext(lines: [])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: executor)
        let reply = await chat.send(question: "how should I continue?", context: noLinesContext)
        #expect(reply.source == .coach)
        #expect(reply.violationCount == 0)
    }

    @Test func failedEvaluateDoesNotSatisfyConcreteClaimGate() async throws {
        let executor = StubExecutor(default: .failure(EngineToolArgumentError("engine rejected arguments")))
        let client = MockChatClient([
            .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN)]),
            .content("White is winning."),
            .content("White is winning."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: executor)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext(lines: []))

        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(reply.toolCallCount == 1)
        #expect(executor.calls.count == 2)
    }

    @Test func seedEvaluationDoesNotSatisfyConcreteClaimGate() async throws {
        let executor = StubExecutor(default: .success(EngineToolResult(
            resultingFEN: startFEN, scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
            evalLabel: "+0.3", principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
        )))
        let client = MockChatClient([
            .content("White is winning."),
            .content("White is winning."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: executor)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext(lines: []))

        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(reply.toolCallCount == 0)
        #expect(executor.calls.count == 1)
    }

    @Test func successfulEvaluateRemainsSatisfiedThroughRegeneration() async throws {
        let executor = StubExecutor(default: .success(EngineToolResult(
            resultingFEN: startFEN, scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
            evalLabel: "+0.3", principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
        )))
        let client = MockChatClient([
            .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN)]),
            .content("You should play 1. e4 to control the center (+9.9)."),
            .content("White is winning."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: executor)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())

        #expect(reply.source == .coach)
        #expect(reply.violationCount > 0)
        #expect(reply.toolCallCount == 1)
        #expect(client.callCount == 3)
    }

    @Test func nonConcreteResponseWithNoToolCallPassesThrough() async throws {
        // A conversational response with no concrete claims - no gate trigger.
        let client = MockChatClient([
            .content("What specifically would you like to know about this position?"),
        ])
        let noLinesContext = sampleContext(lines: [])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: noLinesContext)
        #expect(reply.source == .coach)
        #expect(reply.violationCount == 0)
    }

    @Test func concreteClaimWithPreExistingEngineDataStillRequiresEvaluateCall() async throws {
        // Stored lines are context, not an evaluate tool invocation in this
        // user turn, so they cannot satisfy the hard gate.
        let client = MockChatClient([
            .content("You should play 1. e4 to control the center."),
            .content("You should play 1. e4 to control the center."),
        ])
        let chat = CoachChat(client: client, model: "test-model", register: .intermediate, executor: nil)
        let reply = await chat.send(question: "how should I continue?", context: sampleContext())
        #expect(reply.source == .fallback)
        #expect(reply.violationCount > 0)
        #expect(client.callCount == 2)
    }
}
