import AnalysisKit
import ChessCore
import Foundation
import Testing

@testable import CoachKit

/// A scripted `OllamaChatStreaming` mock: each call to `chat` consumes the
/// next scripted response in order (either a plain-content reply or a
/// tool-call reply), so tests can drive exact multi-turn conversations
/// without a real server.
private final class MockChatClient: OllamaChatStreaming, @unchecked Sendable {
    enum ScriptedResponse {
        case content(String)
        case toolCall(name: String, arguments: [String: JSONValue])
        case failure
    }

    private var responses: [ScriptedResponse]
    private(set) var requestedMessageCounts: [Int] = []

    init(_ responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func chat(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaTool]?,
        numCtx: Int,
        temperature: Double
    ) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        requestedMessageCounts.append(messages.count)
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

extension OllamaChatChunk {
    static func stub(content: String, toolCalls: [OllamaToolCall]? = nil, done: Bool) -> OllamaChatChunk {
        let json: [String: Any] = [
            "model": "test",
            "message": [
                "role": "assistant",
                "content": content,
            ],
            "done": done,
        ]
        var data = try! JSONSerialization.data(withJSONObject: json)
        if let toolCalls, !toolCalls.isEmpty {
            let toolCallsData = try! JSONEncoder().encode(toolCalls)
            var mutableJSON = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            var messageDict = mutableJSON["message"] as! [String: Any]
            messageDict["tool_calls"] = try! JSONSerialization.jsonObject(with: toolCallsData)
            mutableJSON["message"] = messageDict
            data = try! JSONSerialization.data(withJSONObject: mutableJSON)
        }
        return try! JSONDecoder().decode(OllamaChatChunk.self, from: data)
    }
}

private struct StubExecutor: EngineToolExecutor {
    let result: Result<EngineToolResult, Error>
    func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
        try result.get()
    }
}

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

private func samplePayload() -> CoachMomentPayload {
    var game = ChessGame()
    let index = game.startIndex
    let postIndex = game.playMove(san: "e4", at: index)!
    let postFEN = game.fen(at: postIndex)!
    return CoachMomentPayload(
        moveNumberLabel: "1.",
        moverName: "TestPlayer",
        moverIsWhite: true,
        playedSAN: "e4",
        playedUCI: "e2e4",
        classification: .best,
        moverWinProbabilityBeforePercent: 50,
        moverWinProbabilityAfterPercent: 55,
        preMoveFEN: startFEN,
        postMoveFEN: postFEN,
        preMoveLines: [
            CoachRankedLinePayload(
                rank: 1, evalLabel: "+0.3", scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
                principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
            )
        ],
        facts: CoachFactsPayload(betterMove: nil, punishment: nil, missedMate: nil, allowedMate: nil)
    )
}

@Suite(.serialized)
struct CoachNarratorTests {
    @Test func happyPathReturnsVerifiedCoachText() async throws {
        let client = MockChatClient([.content("1. e4 is a fine start (+0.3).")])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback",
            client: client, model: "test-model", executor: nil
        )
        #expect(narration.source == .coach)
        #expect(narration.text == "1. e4 is a fine start (+0.3).")
        #expect(narration.toolCallCount == 0)
    }

    @Test func toolCallLoopExecutesAndFeedsResultBack() async throws {
        let executor = StubExecutor(result: .success(EngineToolResult(
            resultingFEN: startFEN, scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
            evalLabel: "+0.3", principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
        )))
        let client = MockChatClient([
            .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN)]),
            .content("1. e4 keeps things balanced (+0.3)."),
        ])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback",
            client: client, model: "test-model", executor: executor
        )
        #expect(narration.source == .coach)
        #expect(narration.toolCallCount == 1)
    }

    @Test func toolCallCapStopsFurtherRealEvaluations() async throws {
        let executor = StubExecutor(result: .success(EngineToolResult(
            resultingFEN: startFEN, scoreCentipawnsWhitePerspective: 30, mateInWhitePerspective: nil,
            evalLabel: "+0.3", principalVariationUCI: ["e2e4"], principalVariationSAN: ["e4"], depth: 12
        )))
        // 7 tool-call turns, then a final content turn. Only 6 should reach the executor.
        var responses: [MockChatClient.ScriptedResponse] = Array(
            repeating: .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN)]), count: 7
        )
        responses.append(.content("Done (+0.3)."))
        let client = MockChatClient(responses)
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback",
            client: client, model: "test-model", executor: executor
        )
        #expect(narration.toolCallCount == 6)
    }

    @Test func illegalToolArgumentsReturnTypedErrorNotThrow() async throws {
        let executor = StubExecutor(result: .failure(EngineToolArgumentError("illegal move")))
        let client = MockChatClient([
            .toolCall(name: "evaluate", arguments: ["fen": .string(startFEN), "moves": .array([.string("z9z9")])]),
            .content("Let me answer without that (+0.3)."),
        ])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback",
            client: client, model: "test-model", executor: executor
        )
        #expect(narration.source == .coach)
        #expect(narration.toolCallCount == 1)
    }

    @Test func violationTriggersRegenerationWithViolationTextInSecondRequest() async throws {
        let client = MockChatClient([
            .content("12. Bxc6 wins a piece (+9.9)."),  // invented line + wrong eval
            .content("1. e4 is a fine start (+0.3)."),  // corrected on regeneration
        ])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback",
            client: client, model: "test-model", executor: nil
        )
        #expect(narration.source == .coach)
        #expect(narration.text == "1. e4 is a fine start (+0.3).")
        // system + user, then + assistant + regeneration-user for the second call.
        #expect(client.requestedMessageCounts == [2, 4])
    }

    @Test func doubleFailureFallsBackToRuleBasedText() async throws {
        let client = MockChatClient([
            .content("12. Bxc6 wins a piece (+9.9)."),
            .content("13. Qxc6 also wins a piece (+9.9)."),
        ])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback text",
            client: client, model: "test-model", executor: nil
        )
        #expect(narration.source == .fallback)
        #expect(narration.text == "fallback text")
        #expect(narration.violationCount > 0)
    }

    @Test func midStreamOllamaDeathFallsBackNeverThrowsToUI() async throws {
        let client = MockChatClient([.failure])
        let narration = await CoachNarrator.narrateMomentPayload(
            samplePayload(), register: .intermediate, fallbackText: "fallback text",
            client: client, model: "test-model", executor: nil
        )
        #expect(narration.source == .fallback)
        #expect(narration.text == "fallback text")
    }
}
