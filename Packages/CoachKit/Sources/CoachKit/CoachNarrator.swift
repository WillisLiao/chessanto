import AnalysisKit
import Foundation

/// Minimal streaming-chat surface `CoachNarrator` depends on, so tests can
/// substitute a scripted mock instead of a real `OllamaClient`.
public protocol OllamaChatStreaming: Sendable {
    func chat(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaTool]?,
        numCtx: Int,
        temperature: Double
    ) -> AsyncThrowingStream<OllamaChatChunk, Error>
}

extension OllamaClient: OllamaChatStreaming {}

/// One narrated moment (or the whole-game summary): either LLM prose that
/// survived `CoachVerifier`, or the rule-based fallback text - the UI
/// labels the two differently but both are always safe to render.
public struct CoachNarration: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case coach
        case fallback
    }

    public let text: String
    public let source: Source
    public let toolCallCount: Int
    public let violationCount: Int
    public let duration: TimeInterval

    public init(text: String, source: Source, toolCallCount: Int, violationCount: Int, duration: TimeInterval) {
        self.text = text
        self.source = source
        self.toolCallCount = toolCallCount
        self.violationCount = violationCount
        self.duration = duration
    }
}

/// The orchestrator: payload -> chat stream with tools -> execute tool
/// calls (cap 6) -> verify -> regenerate once with the violations fed back
/// -> fall back to rule-based text on a second failure. Nothing unverified
/// ever renders - every path either returns `.coach` text that passed
/// `CoachVerifier`, or `.fallback`.
public enum CoachNarrator {
    private static let toolCallCap = 6
    private static let maxConversationTurns = 12

    public static func narrateMoment(
        _ moment: KeyMoment,
        input: ReportInput,
        register: RatingRegister,
        fallbackText: String,
        client: any OllamaChatStreaming,
        model: String,
        executor: EngineToolExecutor?
    ) async -> CoachNarration {
        let payload = CoachPayloadBuilder.momentPayload(moment, input: input)
        return await narrateMomentPayload(payload, register: register, fallbackText: fallbackText, client: client, model: model, executor: executor)
    }

    public static func narrateMomentPayload(
        _ payload: CoachMomentPayload,
        register: RatingRegister,
        fallbackText: String,
        client: any OllamaChatStreaming,
        model: String,
        executor: EngineToolExecutor?
    ) async -> CoachNarration {
        let context = momentVerifierContext(payload: payload)
        let systemPrompt = CoachPrompt.systemPrompt(register: register)
        guard let userMessage = try? CoachPrompt.momentUserMessage(payload: payload) else {
            return CoachNarration(text: fallbackText, source: .fallback, toolCallCount: 0, violationCount: 0, duration: 0)
        }
        return await narrate(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            verifierContext: context,
            client: client,
            model: model,
            executor: executor,
            fallbackText: fallbackText
        )
    }

    public static func narrateSummary(
        _ report: GameReport,
        momentPayloads: [CoachMomentPayload],
        register: RatingRegister,
        fallbackText: String,
        client: any OllamaChatStreaming,
        model: String,
        executor: EngineToolExecutor?
    ) async -> CoachNarration {
        let payload = CoachPayloadBuilder.summaryPayload(report)
        let context = summaryVerifierContext(payload: payload, momentPayloads: momentPayloads)
        let systemPrompt = CoachPrompt.systemPrompt(register: register)
        guard let userMessage = try? CoachPrompt.summaryUserMessage(payload: payload) else {
            return CoachNarration(text: fallbackText, source: .fallback, toolCallCount: 0, violationCount: 0, duration: 0)
        }
        return await narrate(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            verifierContext: context,
            client: client,
            model: model,
            executor: executor,
            fallbackText: fallbackText
        )
    }

    // MARK: - Verifier context assembly

    public static func momentVerifierContext(payload: CoachMomentPayload) -> CoachVerifier.Context {
        let preAnchor = CoachVerifier.Anchor(
            fen: payload.preMoveFEN,
            lines: payload.preMoveLines.map {
                CoachVerifier.VerifiedLine(
                    scoreCentipawnsWhitePerspective: $0.scoreCentipawnsWhitePerspective,
                    mateInWhitePerspective: $0.mateInWhitePerspective,
                    principalVariationUCI: $0.principalVariationUCI
                )
            }
        )
        let postAnchor = CoachVerifier.Anchor(fen: payload.postMoveFEN, lines: [])
        var knownEvals = payload.preMoveLines.compactMap(\.scoreCentipawnsWhitePerspective)
        var knownMates = payload.preMoveLines.compactMap(\.mateInWhitePerspective)
        if let betterMove = payload.facts.betterMove {
            if let cp = betterMove.preMoveScoreCentipawns { knownEvals.append(cp) }
            if let mate = betterMove.preMoveMateIn { knownMates.append(mate) }
        }
        let knownWinPs: [Double] = [payload.moverWinProbabilityBeforePercent.rounded(), payload.moverWinProbabilityAfterPercent.rounded()]
        return CoachVerifier.Context(
            anchors: [preAnchor, postAnchor],
            knownEvalsCentipawns: knownEvals,
            knownMates: knownMates,
            knownWinProbabilities: knownWinPs
        )
    }

    public static func summaryVerifierContext(payload: CoachSummaryPayload, momentPayloads: [CoachMomentPayload]) -> CoachVerifier.Context {
        var anchors: [CoachVerifier.Anchor] = []
        var knownEvals: [Int] = []
        var knownMates: [Int] = []
        var knownWinPs: [Double] = [payload.whiteAccuracy.rounded(), payload.blackAccuracy.rounded()]
        for moment in momentPayloads {
            let momentContext = momentVerifierContext(payload: moment)
            anchors.append(contentsOf: momentContext.anchors)
            knownEvals.append(contentsOf: momentContext.knownEvalsCentipawns)
            knownMates.append(contentsOf: momentContext.knownMates)
            knownWinPs.append(contentsOf: momentContext.knownWinProbabilities)
        }
        return CoachVerifier.Context(anchors: anchors, knownEvalsCentipawns: knownEvals, knownMates: knownMates, knownWinProbabilities: knownWinPs)
    }

    // MARK: - Core narrate loop: generate -> verify -> regenerate once -> fallback

    private static func narrate(
        systemPrompt: String,
        userMessage: String,
        verifierContext: CoachVerifier.Context,
        client: any OllamaChatStreaming,
        model: String,
        executor: EngineToolExecutor?,
        fallbackText: String
    ) async -> CoachNarration {
        let start = Date()
        var messages: [OllamaChatMessage] = [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userMessage),
        ]
        var context = verifierContext
        context.engineExecutor = executor

        var toolCallTotal = 0
        var violationTotal = 0

        for attempt in 0..<2 {
            let conversation = await runConversation(
                messages: &messages,
                client: client,
                model: model,
                executor: executor,
                toolCallBudgetRemaining: toolCallCap - toolCallTotal
            )
            toolCallTotal += conversation.toolCallsUsed
            context.anchors.append(contentsOf: conversation.newAnchors)

            guard let text = conversation.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                break
            }

            let verdict = await CoachVerifier.verify(text: text, context: context)
            switch verdict {
            case .verified(let verifiedText):
                return CoachNarration(
                    text: verifiedText,
                    source: .coach,
                    toolCallCount: toolCallTotal,
                    violationCount: violationTotal,
                    duration: Date().timeIntervalSince(start)
                )
            case .violations(let violations):
                violationTotal += violations.count
                if attempt == 0 {
                    messages.append(.init(role: "assistant", content: text))
                    messages.append(.init(role: "user", content: CoachPrompt.regenerationUserMessage(violations: violations)))
                }
            }
        }

        return CoachNarration(
            text: fallbackText,
            source: .fallback,
            toolCallCount: toolCallTotal,
            violationCount: violationTotal,
            duration: Date().timeIntervalSince(start)
        )
    }

    private struct ConversationResult {
        let text: String?
        let toolCallsUsed: Int
        let newAnchors: [CoachVerifier.Anchor]
    }

    /// Runs one turn of the chat, following the model through its own
    /// tool-call loop (cap `toolCallBudgetRemaining`) until it produces
    /// prose with no further tool calls, or `maxConversationTurns` is hit.
    private static func runConversation(
        messages: inout [OllamaChatMessage],
        client: any OllamaChatStreaming,
        model: String,
        executor: EngineToolExecutor?,
        toolCallBudgetRemaining: Int
    ) async -> ConversationResult {
        var toolCallsUsed = 0
        var remainingBudget = toolCallBudgetRemaining
        var newAnchors: [CoachVerifier.Anchor] = []

        for _ in 0..<maxConversationTurns {
            var assembledContent = ""
            var toolCalls: [OllamaToolCall] = []
            do {
                let stream = client.chat(
                    model: model,
                    messages: messages,
                    tools: executor != nil ? [CoachPrompt.evaluateToolSchema] : nil,
                    numCtx: 8192,
                    temperature: 0.2
                )
                for try await chunk in stream {
                    assembledContent += chunk.message?.content ?? ""
                    if let calls = chunk.message?.toolCalls, !calls.isEmpty {
                        toolCalls = calls
                    }
                }
            } catch {
                return ConversationResult(text: nil, toolCallsUsed: toolCallsUsed, newAnchors: newAnchors)
            }

            if toolCalls.isEmpty {
                return ConversationResult(text: assembledContent, toolCallsUsed: toolCallsUsed, newAnchors: newAnchors)
            }

            messages.append(.init(role: "assistant", content: assembledContent, toolCalls: toolCalls))

            for call in toolCalls {
                guard remainingBudget > 0, let executor else {
                    messages.append(.init(
                        role: "tool",
                        content: #"{"error": "tool call limit reached, answer with what you have"}"#,
                        toolName: call.function.name
                    ))
                    continue
                }
                remainingBudget -= 1
                toolCallsUsed += 1
                let fen = call.function.arguments["fen"]?.stringValue ?? ""
                let movesUCI = call.function.arguments["moves"]?.arrayValue?.compactMap(\.stringValue) ?? []
                do {
                    let result = try await executor.evaluate(fen: fen, movesUCI: movesUCI)
                    messages.append(.init(role: "tool", content: toolResultJSON(result), toolName: call.function.name))
                    newAnchors.append(CoachVerifier.Anchor(
                        fen: result.resultingFEN,
                        lines: [CoachVerifier.VerifiedLine(
                            scoreCentipawnsWhitePerspective: result.scoreCentipawnsWhitePerspective,
                            mateInWhitePerspective: result.mateInWhitePerspective,
                            principalVariationUCI: result.principalVariationUCI
                        )]
                    ))
                } catch {
                    messages.append(.init(
                        role: "tool",
                        content: #"{"error": "\#(errorMessage(error))"}"#,
                        toolName: call.function.name
                    ))
                }
            }
        }
        return ConversationResult(text: nil, toolCallsUsed: toolCallsUsed, newAnchors: newAnchors)
    }

    private static func errorMessage(_ error: Error) -> String {
        if let argumentError = error as? EngineToolArgumentError {
            return argumentError.message
        }
        return String(describing: error)
    }

    private static func toolResultJSON(_ result: EngineToolResult) -> String {
        struct ToolResultPayload: Encodable {
            let evalLabel: String
            let scoreCentipawnsWhitePerspective: Int?
            let mateInWhitePerspective: Int?
            let principalVariationSAN: [String]
            let depth: Int
        }
        let payload = ToolResultPayload(
            evalLabel: result.evalLabel,
            scoreCentipawnsWhitePerspective: result.scoreCentipawnsWhitePerspective,
            mateInWhitePerspective: result.mateInWhitePerspective,
            principalVariationSAN: result.principalVariationSAN,
            depth: result.depth
        )
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
