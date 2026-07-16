import SwiftUI
import ChessCore
import Persistence

struct GameReplayView: View {
    @StateObject private var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    private let game: GameRecord

    @State private var quality: AnalysisQuality = .standard
    @State private var analysisTask: Task<Void, Never>?

    init(game: GameRecord, store: GameStore) {
        self.game = game
        _viewModel = StateObject(wrappedValue: GameReplayViewModel(record: game, store: store))
    }

    var body: some View {
        HSplitView {
            VStack {
                HStack(alignment: .top, spacing: 8) {
                    EvalBarView(eval: viewModel.currentEvalDisplay(live: engineService.liveEvaluation))
                    BoardView(position: viewModel.position)
                }
                .padding()
                controls
                EvalGraphView(
                    series: viewModel.evalGraphSeries,
                    currentPly: viewModel.moveIndices.firstIndex(of: viewModel.currentIndex) ?? 0
                ) { ply in
                    guard ply >= 0, ply < viewModel.moveIndices.count else { return }
                    viewModel.jump(to: viewModel.moveIndices[ply])
                }
                .padding(.horizontal)
                if let fen = viewModel.currentFEN {
                    LinesPanelView(lines: engineService.liveEvaluation?.lines ?? [], fen: fen)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }
            .frame(minWidth: 420)

            VStack(spacing: 0) {
                accuracySummary
                MoveListView(viewModel: viewModel)
            }
            .frame(minWidth: 260, maxWidth: 340)
        }
        .navigationTitle("\(game.white) vs \(game.black)")
        .toolbar { analysisToolbar }
        .alert("Load error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.loadError ?? "")
        }
        .alert("Analysis error", isPresented: analysisErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.analysisError ?? "")
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .right: viewModel.stepForward()
            case .left: viewModel.stepBackward()
            default: break
            }
        }
        .onAppear { showLivePosition() }
        .onChange(of: viewModel.currentIndex) { _ in showLivePosition() }
        .onDisappear {
            analysisTask?.cancel()
            engineService.stopLive()
        }
    }

    private func showLivePosition() {
        guard let fen = viewModel.currentFEN else { return }
        engineService.showPosition(fen: fen)
    }

    @ToolbarContentBuilder
    private var analysisToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if let reason = engineService.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if engineService.isAnalyzing, let progress = engineService.batchProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 100)
                Button("Cancel") {
                    analysisTask?.cancel()
                }
            } else {
                Picker("Quality", selection: $quality) {
                    ForEach(AnalysisQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Button(viewModel.isAnalyzed ? "Re-analyze" : "Analyze") {
                    startAnalysis(reanalyze: viewModel.isAnalyzed)
                }
            }
        }
    }

    private func startAnalysis(reanalyze: Bool) {
        analysisTask?.cancel()
        analysisTask = Task {
            if reanalyze {
                await viewModel.reanalyze(engineService: engineService, quality: quality)
            } else {
                await viewModel.analyze(engineService: engineService, quality: quality)
            }
        }
    }

    @ViewBuilder
    private var accuracySummary: some View {
        if let white = viewModel.whiteAccuracy, let black = viewModel.blackAccuracy {
            HStack {
                Text("White \(String(format: "%.1f", white))")
                Text("·").foregroundStyle(.secondary)
                Text("Black \(String(format: "%.1f", black))")
            }
            .font(.callout.bold())
            .padding(8)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.stepBackward()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canStepBackward)
            .accessibilityLabel("Previous move")

            Button {
                viewModel.stepForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canStepForward)
            .accessibilityLabel("Next move")
        }
        .buttonStyle(.bordered)
        .padding(.bottom)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.loadError != nil },
            set: { if !$0 { viewModel.loadError = nil } }
        )
    }

    private var analysisErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.analysisError != nil },
            set: { if !$0 { viewModel.analysisError = nil } }
        )
    }
}

private struct MoveListView: View {
    @ObservedObject var viewModel: GameReplayViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.moveIndices.enumerated()), id: \.element) { position, index in
                    if let san = viewModel.san(at: index) {
                        Button {
                            viewModel.jump(to: index)
                        } label: {
                            HStack {
                                if position % 2 == 1 {
                                    Text("\(position / 2 + 1).")
                                        .foregroundStyle(.secondary)
                                }
                                Text(san)
                                Spacer()
                                if let classification = viewModel.classification(at: index) {
                                    ClassificationBadge(classification: classification)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(index == viewModel.currentIndex ? Color.accentColor.opacity(0.2) : .clear)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            position % 2 == 1 ? "Move \(position / 2 + 1), \(san)" : san
                        )
                    }
                }
            }
            .padding()
        }
    }
}
