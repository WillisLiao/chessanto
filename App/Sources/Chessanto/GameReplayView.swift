import SwiftUI
import ChessCore
import Persistence

struct GameReplayView: View {
    @StateObject private var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var library: GameLibrary
    private let game: GameRecord
    private let store: GameStore

    @State private var quality: AnalysisQuality = .standard
    @State private var analysisTask: Task<Void, Never>?
    @State private var selectedSquare: BoardSquare?
    @State private var rightPaneTab: RightPaneTab = .moves
    @State private var flipped = false

    private enum RightPaneTab: String, CaseIterable {
        case moves = "Moves"
        case report = "Report"
        case chat = "Chat"
    }

    init(game: GameRecord, store: GameStore) {
        self.game = game
        self.store = store
        _viewModel = StateObject(wrappedValue: GameReplayViewModel(record: game, store: store))
    }

    var body: some View {
        HSplitView {
            VStack {
                HStack(alignment: .top, spacing: 8) {
                    EvalBarView(eval: viewModel.currentEvalDisplay(live: engineService.liveEvaluation))
                    BoardView(
                        position: viewModel.position,
                        lastMove: viewModel.lastMove,
                        flipped: flipped,
                        theme: library.boardTheme,
                        selectedSquare: selectedSquare,
                        legalDestinations: legalDestinations,
                        onSquareTapped: handleSquareTapped
                    )
                }
                .padding()
                if viewModel.isExploringVariation {
                    Button("Back to game") { viewModel.backToGame() }
                        .font(.caption)
                }
                controls
                EvalGraphView(
                    series: viewModel.evalGraphSeries,
                    currentPly: viewModel.currentGraphPly
                ) { ply in
                    guard ply >= 0, ply < viewModel.moveIndices.count else { return }
                    viewModel.jump(to: viewModel.moveIndices[ply])
                }
                .padding(.horizontal)
                if let fen = viewModel.currentFEN {
                    LinesPanelView(lines: engineService.liveEvaluation?.lines ?? [], fen: fen) { uciMoves in
                        Task { await viewModel.adoptLine(sanMoves: ChessGame.sanLine(fromUCI: uciMoves, startingFEN: fen)) }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
            }
            .frame(minWidth: 420)

            VStack(spacing: 0) {
                accuracySummary
                Picker("", selection: $rightPaneTab) {
                    ForEach(RightPaneTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                switch rightPaneTab {
                case .moves:
                    MoveListView(viewModel: viewModel)
                case .report:
                    GameReportView(viewModel: viewModel)
                case .chat:
                    ChatView(viewModel: viewModel, store: store)
                }
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
        .onAppear {
            quality = library.analysisQuality
            showLivePosition()
        }
        .onChange(of: viewModel.currentIndex) { _ in
            selectedSquare = nil
            showLivePosition()
        }
        .onChange(of: quality) { _, newValue in
            library.saveAnalysisQuality(newValue)
        }
        .onDisappear {
            analysisTask?.cancel()
            engineService.stopLive()
        }
    }

    private func showLivePosition() {
        guard let fen = viewModel.currentFEN else { return }
        engineService.showPosition(fen: fen)
    }

    private var legalDestinations: Set<BoardSquare> {
        guard let selectedSquare else { return [] }
        return Set(
            viewModel.legalDestinations(from: SquareCoordinate(notation: selectedSquare.algebraic))
                .compactMap { BoardSquare(algebraic: $0.notation) }
        )
    }

    private func handleSquareTapped(_ square: BoardSquare) {
        guard let selectedSquare else {
            if viewModel.position.pieces[square] != nil {
                self.selectedSquare = square
            }
            return
        }

        if square == selectedSquare {
            self.selectedSquare = nil
            return
        }

        if legalDestinations.contains(square) {
            let from = SquareCoordinate(notation: selectedSquare.algebraic)
            let to = SquareCoordinate(notation: square.algebraic)
            self.selectedSquare = nil
            Task { await viewModel.playMove(from: from, to: to) }
        } else if viewModel.position.pieces[square] != nil {
            self.selectedSquare = square
        } else {
            self.selectedSquare = nil
        }
    }

    @ToolbarContentBuilder
    private var analysisToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if let reason = engineService.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !engineService.isStarted {
                Button("Starting engine...") {}
                    .disabled(true)
                    .accessibilityLabel("Starting engine")
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

            Button {
                flipped.toggle()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .accessibilityLabel("Flip board")
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

                    // Variations exploring off `index` - rendered even at the
                    // start position, which has no SAN of its own.
                    ForEach(viewModel.exploredChildren(of: index), id: \.self) { branchRoot in
                        ForEach(viewModel.variationRows(startingAt: branchRoot, depth: 1), id: \.index) { row in
                            variationRow(index: row.index, depth: row.depth)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func variationRow(index: MoveIndex, depth: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                viewModel.jump(to: index)
            } label: {
                Text(viewModel.san(at: index) ?? "")
                    .font(.callout.italic())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .background(index == viewModel.currentIndex ? Color.accentColor.opacity(0.2) : .clear)
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.deleteVariation(at: index) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("delete-variation-\(viewModel.san(at: index) ?? "")")
        }
        .padding(.leading, CGFloat(depth) * 16)
    }
}
