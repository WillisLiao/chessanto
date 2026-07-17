import AnalysisKit
import Foundation

/// M7's chat analogue of `CoachNarration`: `.precheck` is a new source with
/// no `KeyMoment` counterpart - an illegal-move proposal is answered by a
/// closed template and never reaches the LLM.
public struct CoachChatReply: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case coach
        case fallback
        case precheck
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

/// Multi-turn position chat (M7 PLAN.md): a durable actor holding
/// conversation state across turns, sharing `CoachNarrator`'s single-turn
/// engine (`runConversation`). An actor serializes turns by construction.
/// Nothing unverified ever renders - every reply is `.coach` text that
/// passed `CoachVerifier`, `.precheck` (never reached the LLM), or
/// `.fallback`.
public actor CoachChat {
    private static let historyCap = 12
    private static let maxPrecheckEvaluations = 2

    private static let verificationFailureFallback =
        "I couldn't give you a verified answer to that - the lines I checked didn't support what I wanted to say. Try asking about a specific move or line."
    private static let connectionFailureFallback =
        "I couldn't reach the coach model just now. Check that Ollama is running and try again."

    private let client: any OllamaChatStreaming
    private let model: String
    private let register: RatingRegister
    private let executor: EngineToolExecutor?

    /// Plain user/assistant turns only - no system prompt, no tool
    /// round-trips, no violation-feedback messages (pruned after every
    /// turn resolves), capped to `historyCap`.
    private var messages: [OllamaChatMessage]
    /// Every anchor accumulated across turns this session (payload lines,
    /// precheck evaluations, tool-call results), so a later turn can still
    /// cite a line grounded several turns ago.
    private var anchorPool: [CoachVerifier.Anchor] = []
    private var lastContextFEN: String?

    public init(
        client: any OllamaChatStreaming,
        model: String,
        register: RatingRegister,
        executor: EngineToolExecutor?,
        seedHistory: [OllamaChatMessage] = []
    ) {
        self.client = client
        self.model = model
        self.register = register
        self.executor = executor
        self.messages = Array(seedHistory.suffix(Self.historyCap))
    }

    public func send(question: String, context: CoachChatContext) async -> CoachChatReply {
        let start = Date()

        // Precheck (design decision 3): classify every move-shaped chain in
        // the question BEFORE any LLM call. Any illegal proposal anywhere
        // in the question short-circuits the whole turn.
        let classifications = ProposedLineCheck.classify(text: question, currentFEN: context.currentFEN)
        if let illegal = classifications.first(where: {
            if case .illegalProposal = $0.classification { return true }
            return false
        }), case .illegalProposal(let rawTokens) = illegal.classification {
            let reply = CoachPrompt.illegalProposalReply(rawTokens: rawTokens)
            recordTurn(question: question, reply: reply)
            return CoachChatReply(text: reply, source: .precheck, toolCallCount: 0, violationCount: 0, duration: Date().timeIntervalSince(start))
        }

        var precheckAnchors: [CoachVerifier.Anchor] = []
        var precheckNotes: [String] = []
        if let executor {
            let legalProposals = classifications.compactMap { pair -> (tokens: [String], uci: [String])? in
                guard case .legalProposal(let uci) = pair.classification else { return nil }
                return (pair.chain.tokens, uci)
            }
            for proposal in legalProposals.prefix(Self.maxPrecheckEvaluations) {
                guard let result = try? await executor.evaluate(fen: context.currentFEN, movesUCI: proposal.uci) else { continue }
                precheckNotes.append(CoachPrompt.precheckEvaluationNote(rawTokens: proposal.tokens, result: result))
                precheckAnchors.append(CoachVerifier.Anchor(
                    fen: result.resultingFEN,
                    lines: [CoachVerifier.VerifiedLine(
                        scoreCentipawnsWhitePerspective: result.scoreCentipawnsWhitePerspective,
                        mateInWhitePerspective: result.mateInWhitePerspective,
                        principalVariationUCI: result.principalVariationUCI
                    )]
                ))
            }
        }

        // Seed evaluation (design decision 2): ensure at least one verified
        // eval exists for the current position when nothing else grounds it.
        var effectiveContext = context
        var seedAnchor: CoachVerifier.Anchor?
        if context.currentPositionLines.isEmpty, let executor,
            let result = try? await executor.evaluate(fen: context.currentFEN, movesUCI: []) {
            let seedLine = RankedLine(
                rank: 1,
                scoreCentipawns: result.scoreCentipawnsWhitePerspective,
                mateIn: result.mateInWhitePerspective,
                principalVariationUCI: result.principalVariationUCI,
                depth: result.depth
            )
            effectiveContext = CoachChatContext(
                currentFEN: context.currentFEN,
                isMainlinePosition: context.isMainlinePosition,
                mainlineMovesSAN: context.mainlineMovesSAN,
                variationBranchPly: context.variationBranchPly,
                variationMovesSAN: context.variationMovesSAN,
                currentPositionLines: [seedLine],
                keyMomentOneLiner: context.keyMomentOneLiner,
                keyMomentWinProbabilityBeforePercent: context.keyMomentWinProbabilityBeforePercent,
                keyMomentWinProbabilityAfterPercent: context.keyMomentWinProbabilityAfterPercent,
                whiteName: context.whiteName,
                blackName: context.blackName,
                result: context.result,
                whiteAccuracy: context.whiteAccuracy,
                blackAccuracy: context.blackAccuracy
            )
            seedAnchor = CoachVerifier.Anchor(
                fen: result.resultingFEN,
                lines: [CoachVerifier.VerifiedLine(
                    scoreCentipawnsWhitePerspective: result.scoreCentipawnsWhitePerspective,
                    mateInWhitePerspective: result.mateInWhitePerspective,
                    principalVariationUCI: result.principalVariationUCI
                )]
            )
        }

        let payload = CoachPayloadBuilder.chatPayload(effectiveContext)
        let includeContext = context.currentFEN != lastContextFEN
        lastContextFEN = context.currentFEN

        guard var userText = try? CoachPrompt.chatUserMessage(question: question, payload: payload, includeContext: includeContext) else {
            return CoachChatReply(text: Self.connectionFailureFallback, source: .fallback, toolCallCount: 0, violationCount: 0, duration: Date().timeIntervalSince(start))
        }
        if !precheckNotes.isEmpty {
            userText += "\n\n" + precheckNotes.joined(separator: "\n")
        }

        var verifierContext = CoachVerifier.Context(
            anchors: [CoachVerifier.Anchor(
                fen: context.currentFEN,
                lines: payload.currentPositionLines.map {
                    CoachVerifier.VerifiedLine(
                        scoreCentipawnsWhitePerspective: $0.scoreCentipawnsWhitePerspective,
                        mateInWhitePerspective: $0.mateInWhitePerspective,
                        principalVariationUCI: $0.principalVariationUCI
                    )
                }
            )] + precheckAnchors + (seedAnchor.map { [$0] } ?? []) + anchorPool,
            engineExecutor: executor
        )
        verifierContext.knownEvalsCentipawns = verifierContext.anchors.flatMap { $0.lines.compactMap(\.scoreCentipawnsWhitePerspective) }
        verifierContext.knownMates = verifierContext.anchors.flatMap { $0.lines.compactMap(\.mateInWhitePerspective) }
        if let before = context.keyMomentWinProbabilityBeforePercent, let after = context.keyMomentWinProbabilityAfterPercent {
            verifierContext.knownWinProbabilities = [before.rounded(), after.rounded()]
        }

        var turnMessages = [OllamaChatMessage(role: "system", content: CoachPrompt.chatSystemPrompt(register: register))]
        turnMessages.append(contentsOf: messages)
        turnMessages.append(.init(role: "user", content: userText))

        var toolCallTotal = 0
        var violationTotal = 0

        var precheckAndSeedPooled = false
        func poolNewAnchors(_ newAnchors: [CoachVerifier.Anchor]) {
            if !precheckAndSeedPooled {
                anchorPool.append(contentsOf: precheckAnchors)
                if let seedAnchor { anchorPool.append(seedAnchor) }
                precheckAndSeedPooled = true
            }
            anchorPool.append(contentsOf: newAnchors)
        }

        for attempt in 0..<2 {
            let conversation = await CoachNarrator.runConversation(
                messages: &turnMessages,
                client: client,
                model: model,
                executor: executor,
                toolCallBudgetRemaining: CoachNarrator.toolCallCap
            )
            toolCallTotal += conversation.toolCallsUsed
            verifierContext.anchors.append(contentsOf: conversation.newAnchors)

            guard let text = conversation.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                poolNewAnchors(conversation.newAnchors)
                let reply = CoachChatReply(
                    text: Self.connectionFailureFallback, source: .fallback,
                    toolCallCount: toolCallTotal, violationCount: violationTotal, duration: Date().timeIntervalSince(start)
                )
                recordTurn(question: question, reply: reply.text)
                return reply
            }

            let verdict = await CoachVerifier.verify(text: text, context: verifierContext)
            switch verdict {
            case .verified(let verifiedText):
                poolNewAnchors(conversation.newAnchors)
                recordTurn(question: question, reply: verifiedText)
                return CoachChatReply(
                    text: verifiedText, source: .coach,
                    toolCallCount: toolCallTotal, violationCount: violationTotal, duration: Date().timeIntervalSince(start)
                )
            case .violations(let violations):
                violationTotal += violations.count
                poolNewAnchors(conversation.newAnchors)
                if attempt == 0 {
                    turnMessages.append(.init(role: "assistant", content: text))
                    turnMessages.append(.init(role: "user", content: CoachPrompt.regenerationUserMessage(violations: violations)))
                }
            }
        }

        let reply = CoachChatReply(
            text: Self.verificationFailureFallback, source: .fallback,
            toolCallCount: toolCallTotal, violationCount: violationTotal, duration: Date().timeIntervalSince(start)
        )
        recordTurn(question: question, reply: reply.text)
        return reply
    }

    /// Appends this turn's bare question + final rendered reply to the
    /// durable history (never the JSON context block, precheck data, or
    /// tool round-trips), capped to the last `historyCap` messages.
    private func recordTurn(question: String, reply: String) {
        messages.append(.init(role: "user", content: question))
        messages.append(.init(role: "assistant", content: reply))
        if messages.count > Self.historyCap {
            messages.removeFirst(messages.count - Self.historyCap)
        }
    }
}
