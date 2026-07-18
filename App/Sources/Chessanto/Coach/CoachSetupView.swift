import CoachKit
import SwiftUI

/// The enable-toggle/teaching-level/model-picker cluster, shared between
/// `CoachSettingsView` (the ongoing Settings surface) and onboarding's Coach
/// page - one implementation of the health-check/pull/recommendation UI,
/// not two. Card-grouped so the health states (checking/unreachable/model-
/// picker/pull-progress/warnings) read as one settled panel instead of a
/// wall of loose controls.
struct CoachSetupView: View {
    @EnvironmentObject private var coachService: CoachService

    @Binding var coachEnabled: Bool
    @Binding var ratingBand: String
    @Binding var coachModel: String
    /// Onboarding shows teaching level on its own dedicated page (page 3)
    /// before this view appears on the coach page - suppress the picker
    /// there so it isn't shown twice in the same flow.
    var showsTeachingLevel: Bool = true

    @State private var customModelText = ""
    @State private var pullProgress: (completed: Int64, total: Int64)?
    @State private var pullError: String?

    private let ratingBands = ["adaptive", "beginner", "intermediate", "advanced"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            if coachService.isIntel {
                Label("This Mac doesn't have Apple Silicon. Local LLM inference will be slow; the coach defaults to rule-based explanations only.", systemImage: "exclamationmark.triangle")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.accent)
            }

            Card {
                Toggle("Enable AI coach", isOn: $coachEnabled)

                if showsTeachingLevel {
                    Picker("Teaching level", selection: $ratingBand) {
                        ForEach(ratingBands, id: \.self) { band in
                            Text(band.capitalized).tag(band)
                        }
                    }
                }
            }

            if coachEnabled {
                Card {
                    healthSection
                }
            }
        }
        .task {
            await coachService.checkHealth()
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        switch coachService.health {
        case .unknown, .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking Ollama…").font(.dsBody)
            }
        case .unreachable:
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text("Ollama isn't running.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                Text("Install it from ollama.com or run `brew install ollama`, then start it, and check again. The app remains fully usable in rule-based mode without it.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                Button("Check again") {
                    Task { await coachService.checkHealth() }
                }
            }
        case .reachable(let installedModelNames, let modelsWithTools):
            reachableModelPicker(installedModelNames: installedModelNames, modelsWithTools: modelsWithTools)
        }
    }

    @ViewBuilder
    private func reachableModelPicker(installedModelNames: Set<String>, modelsWithTools: Set<String>) -> some View {
        let recommendation = CoachModelCatalog.recommendation(
            physicalMemoryGB: MachineProfile.physicalMemoryGB, isAppleSilicon: MachineProfile.isAppleSilicon
        )

        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            if let recommendation {
                Text("Recommended for this Mac: \(recommendation.defaultModel) (approx. \(sizeLabel(recommendation.defaultModel))), or \(recommendation.alternativeModel) (approx. \(sizeLabel(recommendation.alternativeModel))).")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }

            if !installedModelNames.isEmpty {
                Picker("Installed models", selection: $coachModel) {
                    Text("None").tag("")
                    ForEach(installedModelNames.sorted(), id: \.self) { name in
                        Text(modelsWithTools.contains(name) ? name : "\(name) (no tool support)").tag(name)
                    }
                }
            }

            if !coachModel.isEmpty && !modelsWithTools.contains(coachModel) {
                Text("This model doesn't support tool calling - the coach will still narrate from the analysis data, but won't be able to calculate live lines.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.accent)
            }

            Divider()

            HStack {
                TextField("Or pull a model by tag (e.g. qwen3:8b)", text: $customModelText)
                Button("Pull") {
                    pullCustomModel()
                }
                .disabled(customModelText.isEmpty)
            }

            if let pullProgress, pullProgress.total > 0 {
                ProgressView(value: Double(pullProgress.completed), total: Double(pullProgress.total))
                Text("\(pullProgress.completed / 1_000_000) MB / \(pullProgress.total / 1_000_000) MB")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            if let pullError {
                HStack {
                    Text(pullError).font(.dsSecondary).foregroundStyle(.red)
                    Button("Retry") { pullCustomModel() }
                }
            }
        }
    }

    private func sizeLabel(_ model: String) -> String {
        guard let gb = CoachModelCatalog.approxDownloadSizeGB[model] else { return "?" }
        return String(format: "%.1f GB", gb)
    }

    private func pullCustomModel() {
        let model = customModelText
        pullError = nil
        pullProgress = (0, 0)
        Task {
            do {
                for try await event in coachService.pull(model: model) {
                    if let total = event.total, let completed = event.completed {
                        pullProgress = (Int64(completed), Int64(total))
                    }
                }
                pullProgress = nil
                coachModel = model
                await coachService.checkHealth()
            } catch {
                pullError = "Pull failed: \(error.localizedDescription)"
            }
        }
    }
}
