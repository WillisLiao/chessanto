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

    private let client = OllamaClient()
    private var generationTask: Task<Void, Never>?

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
}
