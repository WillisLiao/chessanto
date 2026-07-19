import AnalysisKit
import CoachKit
import Foundation
import Persistence

/// Health of the local Ollama server, per the fallback ladder
/// (NEXT-SESSION-M6.md's Narration flow decisions).
enum CoachHealth: Equatable {
    case unknown
    case checking
    case reachable(installedModelNames: Set<String>, modelsWithTools: Set<String>)
    case unreachable
}

/// Owns an `OllamaClient` and per-game narration state. Health-checks are
/// on demand (settings pane, "Check again"); narration generation is
/// sequential (one moment at a time - one engine, one LLM, bounded memory)
/// and lives only in memory, keyed by the currently loaded game.
@MainActor
final class CoachService: ObservableObject {
    @Published private(set) var health: CoachHealth = .unknown
    @Published private(set) var narrationsByPly: [Int: CoachNarration] = [:]
    @Published private(set) var summaryNarration: CoachNarration?
    @Published private(set) var isGenerating = false

    /// Position chat (M7), the current game's messages in insertion order.
    @Published private(set) var chatMessages: [ChatMessageRecord] = []
    @Published private(set) var isSendingChatMessage = false

    private let client = OllamaClient()
    private var generationTask: Task<Void, Never>?

    /// One `CoachChat` per loaded game, keyed alongside the model/register
    /// it was created with - recreated if either changes (M7 design
    /// decision 1), otherwise reused so its conversation state (message
    /// history, anchor pool, last-context FEN) persists across turns.
    private var chatsByGameId: [Int64: (chat: CoachChat, model: String, register: RatingRegister)] = [:]
    private var currentChatGameId: Int64?

    var isIntel: Bool { !MachineProfile.isAppleSilicon }

    func checkHealth() async {
        health = .checking
        do {
            _ = try await client.version()
            let models = try await client.installedModels()
            let names = Set(models.map(\.name))
            let toolModels = Set(models.filter { ($0.capabilities ?? []).contains("tools") }.map(\.name))
            health = .reachable(installedModelNames: names, modelsWithTools: toolModels)
        } catch {
            health = .unreachable
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullEvent, Error> {
        client.pull(model: model)
    }

    /// Cancels any in-flight generation and clears state - call when
    /// switching games or turning the coach off.
    func reset() {
        generationTask?.cancel()
        generationTask = nil
        narrationsByPly = [:]
        summaryNarration = nil
        isGenerating = false
        chatMessages = []
        chatsByGameId = [:]
        currentChatGameId = nil
        isSendingChatMessage = false
    }

    func generateNarrations(
        report: GameReport,
        input: ReportInput,
        userProfile: UserProfileRecord,
        userRating: Int?,
        executor: EngineToolExecutor
    ) {
        reset()
        guard userProfile.coachEnabled, let model = userProfile.coachModel, !model.isEmpty else { return }
        isGenerating = true
        let client = client
        generationTask = Task { [weak self] in
            guard let self else { return }
            let register = RatingRegister.resolve(ratingBand: userProfile.ratingBand, userRating: userRating)
            for moment in report.keyMoments {
                if Task.isCancelled { break }
                let fallback = ReportText.momentSummary(moment, report: report)
                let narration = await CoachNarrator.narrateMoment(
                    moment, input: input, register: register, fallbackText: fallback,
                    client: client, model: model, executor: executor
                )
                if Task.isCancelled { break }
                self.narrationsByPly[moment.ply] = narration
            }
            if !Task.isCancelled {
                let momentPayloads = report.keyMoments.map { CoachPayloadBuilder.momentPayload($0, input: input) }
                let fallback = report.takeaways.joined(separator: " ")
                let narration = await CoachNarrator.narrateSummary(
                    report, momentPayloads: momentPayloads, register: register, fallbackText: fallback,
                    client: client, model: model, executor: executor
                )
                if !Task.isCancelled {
                    self.summaryNarration = narration
                }
            }
            self.isGenerating = false
        }
    }

    /// Builds verified, portable narration without changing the desktop
    /// report's currently displayed Coach state.
    func portableNarrations(
        report: GameReport,
        input: ReportInput,
        userProfile: UserProfileRecord,
        userRating: Int?,
        executor: EngineToolExecutor
    ) async -> [Int: CoachNarration] {
        guard
            userProfile.coachEnabled,
            let model = userProfile.coachModel,
            !model.isEmpty
        else {
            return [:]
        }
        let register = RatingRegister.resolve(
            ratingBand: userProfile.ratingBand,
            userRating: userRating
        )
        var narrations: [Int: CoachNarration] = [:]
        for moment in report.keyMoments {
            if Task.isCancelled {
                break
            }
            let fallback = ReportText.momentSummary(
                moment,
                report: report
            )
            narrations[moment.ply] = await CoachNarrator.narrateMoment(
                moment,
                input: input,
                register: register,
                fallbackText: fallback,
                client: client,
                model: model,
                executor: executor
            )
        }
        return narrations
    }

    // MARK: - Position chat (M7)

    /// Loads a game's persisted chat history on game load.
    func loadChat(gameId: Int64, store: GameStore) async {
        currentChatGameId = gameId
        chatMessages = (try? await store.chatMessages(gameId: gameId)) ?? []
    }

    /// The Clear-chat affordance: empties the table and drops the in-memory
    /// conversation state, so the next turn starts fresh.
    func clearChat(gameId: Int64, store: GameStore) async {
        try? await store.deleteChatMessages(gameId: gameId)
        chatsByGameId[gameId] = nil
        if currentChatGameId == gameId {
            chatMessages = []
        }
    }

    private func chat(
        gameId: Int64, model: String, register: RatingRegister, executor: EngineToolExecutor
    ) -> CoachChat {
        if let existing = chatsByGameId[gameId], existing.model == model, existing.register == register {
            return existing.chat
        }
        // Seed from the last 12 persisted rows as plain prose turns -
        // context blocks aren't persisted and are re-injected with the
        // next question anyway.
        let seedHistory: [OllamaChatMessage] = chatMessages.suffix(12).map {
            OllamaChatMessage(role: $0.role, content: $0.content)
        }
        let newChat = CoachChat(client: client, model: model, register: register, executor: executor, seedHistory: seedHistory)
        chatsByGameId[gameId] = (newChat, model, register)
        return newChat
    }

    /// Persists the user row, runs the turn, persists the reply row, and
    /// publishes both. Sends are sequential (input disabled while a turn is
    /// in flight, enforced here and by the actor itself).
    func sendChatMessage(
        text: String,
        gameId: Int64,
        plyIndex: Int,
        context: CoachChatContext,
        userProfile: UserProfileRecord,
        userRating: Int?,
        executor: EngineToolExecutor,
        store: GameStore
    ) async {
        guard !isSendingChatMessage else { return }
        guard userProfile.coachEnabled, let model = userProfile.coachModel, !model.isEmpty else { return }

        isSendingChatMessage = true
        defer { isSendingChatMessage = false }

        let userRecord = ChatMessageRecord(gameId: gameId, plyIndex: plyIndex, role: "user", content: text)
        if let saved = try? await store.insertChatMessage(userRecord) {
            chatMessages.append(saved)
        }

        let register = RatingRegister.resolve(ratingBand: userProfile.ratingBand, userRating: userRating)
        let activeChat = chat(gameId: gameId, model: model, register: register, executor: executor)
        let reply = await activeChat.send(question: text, context: context)

        let assistantRecord = ChatMessageRecord(
            gameId: gameId, plyIndex: plyIndex, role: "assistant", content: reply.text, source: reply.source.rawValue
        )
        if let saved = try? await store.insertChatMessage(assistantRecord) {
            chatMessages.append(saved)
        }
    }
}
