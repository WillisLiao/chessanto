import CompanionDomain
import SwiftUI

struct GamesView: View {
    @EnvironmentObject private var model: MobileAppModel
    @State private var selectedGame: CatalogGame?
    @State private var quality: CompanionAnalysisQuality = .standard

    var body: some View {
        Group {
            if case .unpaired = model.pairingStage {
                ContentUnavailableView {
                    Label("Pair your Mac", systemImage: "link.badge.plus")
                } description: {
                    Text("Pair in the Mac tab to browse games and request local analysis.")
                }
            } else if let catalog = model.catalog, !catalog.games.isEmpty {
                List {
                    if let active = model.jobs.first {
                        Section("Analysis progress") {
                            AnalysisJobRow(job: active) {
                                Task { await model.cancel(active) }
                            }
                        }
                    }
                    Section("On your Mac") {
                        ForEach(catalog.games) { game in
                            Button {
                                selectedGame = game
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(game.white) vs \(game.black)")
                                            .font(.headline)
                                            .foregroundStyle(MobileColors.graphite)
                                        HStack {
                                            Text(game.result)
                                            if game.isAnalyzed {
                                                Label(
                                                    "Analyzed",
                                                    systemImage: "checkmark.seal.fill"
                                                )
                                                .foregroundStyle(
                                                    MobileColors.success
                                                )
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(
                                            MobileColors.graphiteSoft
                                        )
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(
                                            MobileColors.graphiteSoft
                                        )
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView {
                    Label("Waiting for your Mac", systemImage: "laptopcomputer")
                } description: {
                    Text(
                        model.isOnline
                            ? "Open Chessanto on your Mac, then pull to refresh."
                            : "You are offline. The game catalog will refresh when you reconnect."
                    )
                }
            }
        }
        .navigationTitle("Games")
        .companionBackground()
        .refreshable {
            try? await model.synchronize(reason: .pullToRefresh)
        }
        .sheet(item: $selectedGame) { game in
            NavigationStack {
                Form {
                    Section("Analysis quality") {
                        Picker("Quality", selection: $quality) {
                            ForEach(
                                CompanionAnalysisQuality.allCases,
                                id: \.rawValue
                            ) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(qualityExplanation)
                            .font(.footnote)
                            .foregroundStyle(MobileColors.graphiteSoft)
                    }
                    Section {
                        Button {
                            selectedGame = nil
                            Task {
                                await model.requestAnalysis(
                                    gameID: game.id,
                                    quality: quality
                                )
                            }
                        } label: {
                            Label(
                                game.isAnalyzed
                                    ? "Send or improve report"
                                    : "Analyze on Mac",
                                systemImage: "sparkles"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .navigationTitle("\(game.white) vs \(game.black)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { selectedGame = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var qualityExplanation: String {
        switch quality {
        case .fast:
            "A quick review for the main turning points."
        case .standard:
            "Balanced detail and analysis time."
        case .deep:
            "The strongest review. The Mac may take several minutes."
        }
    }
}

struct AnalysisJobRow: View {
    let job: AnalysisJobSnapshot
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(text: statusText)
                Spacer()
                if let progress = job.progress {
                    Text(
                        "\(progress.completedPlies) of \(progress.totalPlies)"
                    )
                    .font(.caption.monospacedDigit())
                }
            }
            if let progress = job.progress, progress.totalPlies > 0 {
                ProgressView(
                    value: Double(progress.completedPlies),
                    total: Double(progress.totalPlies)
                )
                .tint(MobileColors.brass)
            }
            if !job.state.isTerminal {
                Button("Cancel request", action: cancel)
                    .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if job.reception != .accepted {
            return "Mac has not received this yet"
        }
        switch job.state {
        case .submitted, .queued:
            return "Queued"
        case .accepted:
            return "Accepted by Mac"
        case .waitingForEngine:
            return "Waiting for engine"
        case .analyzing:
            return "Analyzing on your Mac"
        case .packaging:
            return "Packaging report"
        case .transferring:
            return "Saving for offline reading"
        case .completed:
            return "Saved for offline reading"
        case .failed:
            return "Analysis failed"
        case .cancelled:
            return "Cancelled"
        case .expired:
            return "Request expired"
        case .rejected:
            return "Request rejected"
        }
    }
}
