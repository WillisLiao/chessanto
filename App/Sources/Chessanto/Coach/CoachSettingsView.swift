import CoachKit
import Persistence
import SwiftUI

/// The Coach settings pane (`Settings` scene): enable toggle, model picker,
/// teaching level, and the Intel/no-Ollama/no-model guidance states. Every
/// control is a real native SwiftUI control (buttons, pickers, toggles) -
/// the M3 accessibility lesson carried forward.
struct CoachSettingsView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var coachService: CoachService

    @State private var coachEnabled = false
    @State private var ratingBand = "adaptive"
    @State private var coachModel = ""
    @State private var customModelText = ""
    @State private var pullProgress: (completed: Int64, total: Int64)?
    @State private var pullError: String?

    private let ratingBands = ["adaptive", "beginner", "intermediate", "advanced"]

    var body: some View {
        Form {
            if coachService.isIntel {
                Section {
                    Label("This Mac doesn't have Apple Silicon. Local LLM inference will be slow; the coach defaults to rule-based explanations only.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Verified Coach") {
                Toggle("Enable AI coach", isOn: $coachEnabled)
                    .onChange(of: coachEnabled) { _, newValue in save(coachEnabled: newValue) }

                Picker("Teaching level", selection: $ratingBand) {
                    ForEach(ratingBands, id: \.self) { band in
                        Text(band.capitalized).tag(band)
                    }
                }
                .onChange(of: ratingBand) { _, newValue in save(ratingBand: newValue) }
            }

            if coachEnabled {
                Section("Model") {
                    healthSection
                }
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .task {
            load()
            await coachService.checkHealth()
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        switch coachService.health {
        case .unknown, .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking Ollama…")
            }
        case .unreachable:
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama isn't running.")
                    .foregroundStyle(.secondary)
                Text("Install it from ollama.com or run `brew install ollama`, then start it, and check again. The app remains fully usable in rule-based mode without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

        VStack(alignment: .leading, spacing: 8) {
            if let recommendation {
                Text("Recommended for this Mac: \(recommendation.defaultModel) (approx. \(sizeLabel(recommendation.defaultModel))), or \(recommendation.alternativeModel) (approx. \(sizeLabel(recommendation.alternativeModel))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !installedModelNames.isEmpty {
                Picker("Installed models", selection: $coachModel) {
                    Text("None").tag("")
                    ForEach(installedModelNames.sorted(), id: \.self) { name in
                        Text(modelsWithTools.contains(name) ? name : "\(name) (no tool support)").tag(name)
                    }
                }
                .onChange(of: coachModel) { _, newValue in save(coachModel: newValue) }
            }

            if !coachModel.isEmpty && !modelsWithTools.contains(coachModel) {
                Text("This model doesn't support tool calling - the coach will still narrate from the analysis data, but won't be able to calculate live lines.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pullError {
                HStack {
                    Text(pullError).font(.caption).foregroundStyle(.red)
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
                save(coachModel: model)
                await coachService.checkHealth()
            } catch {
                pullError = "Pull failed: \(error.localizedDescription)"
            }
        }
    }

    private func load() {
        guard let profile = try? library.store.userProfile() else { return }
        coachEnabled = profile.coachEnabled
        ratingBand = profile.ratingBand
        coachModel = profile.coachModel ?? ""
    }

    private func save(coachEnabled newValue: Bool) {
        updateProfile { $0.coachEnabled = newValue }
    }

    private func save(ratingBand newValue: String) {
        updateProfile { $0.ratingBand = newValue }
    }

    private func save(coachModel newValue: String) {
        updateProfile { $0.coachModel = newValue.isEmpty ? nil : newValue }
    }

    private func updateProfile(_ mutate: (inout UserProfileRecord) -> Void) {
        guard var profile = try? library.store.userProfile() else { return }
        mutate(&profile)
        try? library.store.saveUserProfile(profile)
    }
}
