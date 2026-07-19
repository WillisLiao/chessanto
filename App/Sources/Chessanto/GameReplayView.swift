import SwiftUI
import ChessCore
import Persistence
import AnalysisKit
import CoachKit

struct GameReplayView: View {
    @StateObject private var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var coachService: CoachService
    private let game: GameRecord
    private let store: GameStore

    @State private var quality: AnalysisQuality = .standard
    @State private var analysisTask: Task<Void, Never>?
    @State private var selectedSquare: BoardSquare?
    @State private var rightPaneTab: RightPaneTab = .moves
    @State private var flipped = false
    @State private var isCoachOpen = false
    @State private var practiceSourcePly: Int?
    @State private var practiceViewModel: PracticeSessionViewModel?
    @State private var linePreview: LinePreviewController?
    @State private var coachMomentPly: Int?

    private let pendingPracticeLoadCards: (() async throws -> [TrainingCardRecord])?
    private let onPendingPracticeConsumed: (() -> Void)?

    private enum RightPaneTab: String, CaseIterable {
        case moves = "Moves"
        case report = "Review"
        /// Never a segment in the Moves/Report picker - entered
        /// programmatically only, as a full-width mode (DD1).
        case practice = "Practice"
    }

    /// Below this window width the Coach panel slides over the Moves/Report
    /// pane instead of docking as a third column (decision A) - board(420)
    /// + moves/report(~300) + coach(~320) needs roughly this much room to
    /// coexist comfortably.
    private static let coachDockWidthThreshold: CGFloat = 1100

    init(
        game: GameRecord,
        store: GameStore,
        pendingPracticeLoadCards: (() async throws -> [TrainingCardRecord])? = nil,
        onPendingPracticeConsumed: (() -> Void)? = nil
    ) {
        self.game = game
        self.store = store
        self.pendingPracticeLoadCards = pendingPracticeLoadCards
        self.onPendingPracticeConsumed = onPendingPracticeConsumed
        _viewModel = StateObject(wrappedValue: GameReplayViewModel(record: game, store: store))
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= Self.coachDockWidthThreshold
            ZStack(alignment: .trailing) {
                HSplitView {
                    boardColumn
                        .frame(minWidth: 420)

                    movesReportColumn
                        .frame(minWidth: 260, maxWidth: 340)

                    if isCoachOpen && isWide {
                        coachColumn
                            .frame(minWidth: 280, maxWidth: 380)
                    }
                }

                if isCoachOpen && !isWide {
                    coachColumn
                        .frame(width: min(340, proxy.size.width * 0.9))
                        .background(DesignColors.surface0)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(DesignColors.hairline).frame(width: 1)
                        }
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isCoachOpen)
        }
        .navigationTitle("\(game.white) vs \(game.black)")
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
        .onExitCommand {
            if isCoachOpen { isCoachOpen = false }
        }
        .onAppear {
            quality = library.analysisQuality
            showLivePosition()
            if let pendingPracticeLoadCards {
                openPractice(loadCards: pendingPracticeLoadCards)
                onPendingPracticeConsumed?()
            }
        }
        .onChange(of: viewModel.currentIndex) {
            selectedSquare = nil
            if linePreview == nil {
                showLivePosition()
            }
        }
        .onChange(of: quality) { _, newValue in
            library.saveAnalysisQuality(newValue)
        }
        .onDisappear {
            analysisTask?.cancel()
            linePreview?.pause()
            engineService.stopLive()
        }
        .task(id: viewModel.report) {
            await maybeGenerateNarrations()
        }
    }

    private func showLivePosition() {
        guard linePreview == nil, !viewModel.isPracticeActive, let fen = viewModel.currentFEN else { return }
        engineService.showPosition(fen: fen)
    }

    // MARK: - Columns

    private func identityStrips(flipped: Bool) -> (top: BoardIdentityStripInfo, bottom: BoardIdentityStripInfo) {
        BoardIdentityStrip.strips(
            whiteName: game.white,
            blackName: game.black,
            whiteRating: game.whiteRating,
            blackRating: game.blackRating,
            flipped: flipped,
            username: library.chessComUsername
        )
    }

    private var boardColumn: some View {
        VStack {
            if rightPaneTab == .practice, let practiceViewModel {
                PracticeBoardSection(
                    viewModel: practiceViewModel,
                    theme: library.boardTheme,
                    identityStrips: identityStrips(flipped: practiceViewModel.flipped)
                )
                .padding()
                practiceControls(practiceViewModel)
            } else if let linePreview {
                LinePreviewBoardSection(
                    controller: linePreview,
                    flipped: flipped,
                    theme: library.boardTheme,
                    identityStrips: identityStrips(flipped: flipped),
                    coachContent: coachContent(forPly: coachMomentPly),
                    onDone: endLinePreview
                )
                .padding()
            } else {
                HStack(alignment: .top, spacing: DesignSpacing.md) {
                    EvalBarView(eval: viewModel.currentEvalDisplay(live: engineService.liveEvaluation))
                    VStack(spacing: DesignSpacing.xs) {
                        BoardIdentityStripView(info: identityStrips(flipped: flipped).top)
                        BoardView(
                            position: viewModel.position,
                            lastMove: viewModel.lastMove,
                            flipped: flipped,
                            theme: library.boardTheme,
                            selectedSquare: selectedSquare,
                            legalDestinations: legalDestinations,
                            arrows: suggestedMoveArrows,
                            onSquareTapped: handleSquareTapped
                        )
                        BoardIdentityStripView(info: identityStrips(flipped: flipped).bottom)
                    }
                }
                .padding()
                if let coachMomentPly {
                    CoachStageView(
                        content: coachContent(forPly: coachMomentPly),
                        primaryActionTitle: canPreviewBetterLine(atPly: coachMomentPly)
                            ? "Replay better line"
                            : nil,
                        onPrimaryAction: canPreviewBetterLine(atPly: coachMomentPly)
                            ? { previewBetterLine(atPly: coachMomentPly) }
                            : nil,
                        secondaryActionTitle: "What happened",
                        onSecondaryAction: { previewPlayedContinuation(atPly: coachMomentPly) },
                        onAskCoach: { askCoach(aboutPly: coachMomentPly) }
                    )
                    .padding(.horizontal)
                }
                if viewModel.isExploringVariation {
                    Button("Back to game") { viewModel.backToGame() }
                        .font(.caption)
                }
                controls
                EvalGraphView(
                    series: viewModel.evalGraphSeries,
                    currentPly: viewModel.currentGraphPly,
                    keyMoments: viewModel.report?.keyMoments ?? []
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
        }
    }

    private var movesReportColumn: some View {
        VStack(spacing: 0) {
            if rightPaneTab == .practice, let practiceViewModel {
                PracticeContentView(viewModel: practiceViewModel, onExit: exitPractice)
            } else {
                analysisControls
                accuracySummary
                HStack(spacing: DesignSpacing.sm) {
                    Picker("", selection: $rightPaneTab) {
                        ForEach([RightPaneTab.moves, .report], id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    coachToggleButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                switch rightPaneTab {
                case .moves:
                    MoveListView(viewModel: viewModel, onAskCoach: askCoach(aboutPly:))
                case .report:
                    GameReportView(
                        viewModel: viewModel,
                        onAskCoach: askCoach(aboutPly:),
                        onPractice: openPractice(sourcePly:),
                        onSelectMoment: selectAndPreview(moment:),
                        onPlayContinuation: playContinuation(moment:)
                    )
                case .practice:
                    EmptyView()
                }
            }
        }
    }

    private var coachColumn: some View {
        ChatView(viewModel: viewModel, store: store) {
            isCoachOpen = false
        }
    }

    /// The single, always-available Coach control (decision A) - toggles
    /// the slide-over/dock panel without pinning; opening this way leaves
    /// the subject following the board (default mode).
    private var coachToggleButton: some View {
        Button {
            isCoachOpen.toggle()
        } label: {
            Label("Coach", systemImage: isCoachOpen ? "bubble.left.fill" : "bubble.left")
                .font(.dsSecondary.weight(.semibold))
                .foregroundStyle(isCoachOpen ? DesignColors.accentText : DesignColors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCoachOpen ? "Close Coach panel" : "Open Coach panel")
    }

    /// Opens the Coach panel pinned to a specific ply - the move-row and
    /// Report key-moment entry points (decision A).
    private func askCoach(aboutPly ply: Int) {
        guard ply < viewModel.moveIndices.count else { return }
        viewModel.pinChat(to: viewModel.moveIndices[ply])
        isCoachOpen = true
    }

    private func selectAndPreview(moment: KeyMoment) {
        guard moment.ply < viewModel.moveIndices.count else { return }
        coachMomentPly = moment.ply
        viewModel.jump(to: viewModel.moveIndices[moment.ply])
        if moment.betterMove != nil {
            previewBetterLine(atPly: moment.ply)
        }
    }

    private func playContinuation(moment: KeyMoment) {
        guard moment.ply < viewModel.moveIndices.count else { return }
        coachMomentPly = moment.ply
        viewModel.jump(to: viewModel.moveIndices[moment.ply])
        previewPlayedContinuation(atPly: moment.ply)
    }

    private func canPreviewBetterLine(atPly ply: Int) -> Bool {
        guard let input = viewModel.reportInput, ply > 0, ply - 1 < input.plies.count else { return false }
        return input.plies[ply - 1].rank1?.principalVariationUCI.isEmpty == false
    }

    private func previewBetterLine(atPly ply: Int) {
        guard let input = viewModel.reportInput,
            ply > 0,
            ply - 1 < input.plies.count,
            let line = input.plies[ply - 1].rank1,
            !line.principalVariationUCI.isEmpty
        else { return }
        beginLinePreview(
            label: "Better line",
            startingFEN: input.plies[ply - 1].fen,
            moves: line.principalVariationUCI,
            coachPly: ply
        )
    }

    private func previewPlayedContinuation(atPly ply: Int) {
        guard let input = viewModel.reportInput,
            ply >= 0,
            ply < input.plies.count
        else { return }
        let continuation = viewModel.uciContinuation(fromPly: ply, maxPlies: 10)
        guard !continuation.isEmpty else { return }
        beginLinePreview(
            label: "What happened",
            startingFEN: input.plies[ply].fen,
            moves: continuation,
            coachPly: ply
        )
    }

    private func beginLinePreview(label: String, startingFEN: String, moves: [String], coachPly: Int) {
        linePreview?.pause()
        engineService.stopLive()
        selectedSquare = nil
        coachMomentPly = coachPly
        let preview = LinePreviewController(label: label, startingFEN: startingFEN, uciMoves: moves)
        linePreview = preview
        preview.play()
    }

    private func endLinePreview() {
        linePreview?.pause()
        linePreview = nil
        showLivePosition()
    }

    private func coachContent(forPly ply: Int?) -> CoachStageContent {
        guard let ply,
            let moment = viewModel.report?.keyMoments.first(where: { $0.ply == ply })
        else {
            return CoachStageContent(
                eyebrow: "Coach",
                headline: "Choose a key moment.",
                message: "I’ll connect the explanation to the exact moves on the board.",
                source: "Engine verified"
            )
        }
        let narration = coachService.narrationsByPly[ply]
        return CoachStageContent(
            eyebrow: "\(moveNumberLabel(ply: ply)) \(moment.evalSwing.playedSAN)",
            headline: CoachStageText.headline(for: moment.evalSwing.classification),
            message: CoachStageText.condensed(narration?.text ?? momentSummary(moment)),
            source: narration?.source == .coach ? "Local Coach" : "Engine verified"
        )
    }

    private func momentSummary(_ moment: KeyMoment) -> String {
        var parts = [
            "Winning chances changed from \(Int(moment.evalSwing.moverWinProbabilityBefore.rounded()))% to \(Int(moment.evalSwing.moverWinProbabilityAfter.rounded()))%."
        ]
        if let betterMove = moment.betterMove {
            parts.append("Better was \(betterMove.bestMoveSAN).")
        }
        if let punishment = moment.punishment {
            parts.append("\(punishment.refutingSAN) is the reply to watch.")
        }
        return parts.joined(separator: " ")
    }

    private func moveNumberLabel(ply: Int) -> String {
        let moveNumber = (ply + 1) / 2
        return ply % 2 == 1 ? "\(moveNumber)." : "\(moveNumber)..."
    }

    @MainActor
    private func maybeGenerateNarrations() async {
        guard let report = viewModel.report,
            let input = viewModel.reportInput,
            let profile = viewModel.userProfile(),
            profile.coachEnabled
        else { return }
        coachService.generateNarrations(
            report: report,
            input: input,
            userProfile: profile,
            userRating: viewModel.userRatingInThisGame,
            executor: engineService
        )
    }

    private func openPractice(sourcePly: Int?) {
        practiceSourcePly = sourcePly
        openPractice {
            let cards = try await viewModel.trainingCards()
            guard let sourcePly else { return cards }
            return cards.filter { $0.sourcePly == sourcePly }
        }
    }

    /// The single seam both the Report's "Practice" button and a
    /// dashboard-originated pending practice session go through (DD1) - the
    /// caller supplies which cards to practice, and this owns creating the
    /// session, switching the right pane, and suspending live analysis.
    private func openPractice(loadCards: @escaping () async throws -> [TrainingCardRecord]) {
        let sessionViewModel = PracticeSessionViewModel(
            store: store,
            loadCards: loadCards,
            evaluator: DefaultTrainingMoveEvaluator { request in
                try await engineService.evaluateTrainingPosition(request)
            }
        )
        practiceViewModel = sessionViewModel
        rightPaneTab = .practice
        viewModel.enterPractice()
        engineService.stopLive()
        Task { await sessionViewModel.load() }
    }

    private func exitPractice() {
        rightPaneTab = .report
        practiceViewModel = nil
        viewModel.exitPractice()
        showLivePosition()
    }

    /// The live engine's top line's first move, drawn as a board arrow -
    /// only trusted when its FEN matches the displayed position (same rule
    /// as the eval bar/graph, so scrubbing never shows a stale suggestion).
    private var suggestedMoveArrows: [(from: BoardSquare, to: BoardSquare)] {
        guard let fen = viewModel.currentFEN, let live = engineService.liveEvaluation, live.fen == fen,
            let topLine = live.lines.first(where: { ($0.multiPVRank ?? 1) == 1 }),
            let uciMove = topLine.principalVariation.first, uciMove.count >= 4,
            let from = BoardSquare(algebraic: String(uciMove.prefix(2))),
            let to = BoardSquare(algebraic: String(uciMove.dropFirst(2).prefix(2)))
        else { return [] }
        return [(from: from, to: to)]
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

    /// Analysis controls (quality picker, Analyze/Re-analyze, engine status)
    /// live at the top of the right pane rather than the window toolbar.
    /// The unified toolbar's native title reserves nearly all its width for
    /// the window/game title text, forcing anything placed there behind the
    /// ">>" overflow chevron at every supported width (fact 1 in the
    /// redesign plan, which also bit the sidebar's toolbar) - the right
    /// pane's own fixed 260-340pt column has no such competition.
    @ViewBuilder
    private var analysisControls: some View {
        Group {
            if let reason = engineService.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !engineService.isStarted {
                Button("Starting engine...") {}
                    .disabled(true)
                    .accessibilityLabel("Starting engine")
            } else if engineService.isAnalyzing, let progress = engineService.batchProgress {
                HStack {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Button("Cancel") {
                        analysisTask?.cancel()
                    }
                }
            } else {
                HStack {
                    if viewModel.isAnalyzed {
                        Image(systemName: "checkmark")
                            .font(.dsSecondary.weight(.semibold))
                            .foregroundStyle(DesignColors.accentText)
                        Text("Analyzed · \(quality.label)")
                            .font(.dsSecondary.weight(.semibold))
                            .foregroundStyle(DesignColors.textPrimary)
                        Spacer()
                        Menu {
                            Picker("Quality", selection: $quality) {
                                ForEach(AnalysisQuality.allCases) { quality in
                                    Text(quality.label).tag(quality)
                                }
                            }
                            Divider()
                            Button("Re-analyze") {
                                startAnalysis(reanalyze: true)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Picker("Quality", selection: $quality) {
                            ForEach(AnalysisQuality.allCases) { quality in
                                Text(quality.label).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Spacer()
                        Button("Analyze") {
                            startAnalysis(reanalyze: false)
                        }
                        .buttonStyle(.dsPrimary)
                    }
                }
            }
        }
        .padding(DesignSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
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
            library.reload()
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
            .font(.dsNotation.weight(.semibold))
            .foregroundStyle(DesignColors.textSecondary)
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, DesignSpacing.xs)
        }
    }

    private var controls: some View {
        HStack(spacing: DesignSpacing.md) {
            HStack(spacing: 1) {
                Button {
                    viewModel.jump(to: viewModel.moveIndices[0])
                } label: {
                    Image(systemName: "backward.end.fill")
                        .padding(DesignSpacing.sm)
                }
                .disabled(!viewModel.canStepBackward)
                .accessibilityLabel("Jump to start")

                Button {
                    viewModel.stepBackward()
                } label: {
                    Image(systemName: "chevron.left")
                        .padding(DesignSpacing.sm)
                }
                .disabled(!viewModel.canStepBackward)
                .accessibilityLabel("Previous move")

                Button {
                    viewModel.stepForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .padding(DesignSpacing.sm)
                }
                .disabled(!viewModel.canStepForward)
                .accessibilityLabel("Next move")

                Button {
                    if let last = viewModel.moveIndices.last {
                        viewModel.jump(to: last)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .padding(DesignSpacing.sm)
                }
                .disabled(!viewModel.canStepForward)
                .accessibilityLabel("Jump to end")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, DesignSpacing.xs)

            flipButton

            Button {
                askCoach(aboutPly: viewModel.currentGraphPly)
            } label: {
                Label("Ask Coach", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.dsSecondary.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Ask the coach about this position")
        }
        .padding(.bottom)
    }

    private var flipButton: some View {
        Button {
            flipped.toggle()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Flip board")
    }

    /// Practice hides the step/jump controls, eval graph, and lines panel -
    /// none of them apply to a position that isn't a ply of this game - but
    /// keeps the flip button, per DD1.
    private func practiceControls(_ practiceViewModel: PracticeSessionViewModel) -> some View {
        HStack {
            Button {
                practiceViewModel.toggleFlip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Flip board")
        }
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

/// Two-column notation table (move number | White | Black) - the standard
/// analysis-board layout, replacing the single tall column of M1-M8 (also
/// closes an M3 debt: variation rows sit inline in the same table).
/// Classification stops being a full capsule on every move (visual noise on
/// a 55-ply game); it's a quiet colored dot inline, with a chip reserved for
/// anything worth a second look (inaccuracy and worse, plus brilliancies).
private struct MoveListView: View {
    @ObservedObject var viewModel: GameReplayViewModel
    /// Opens the Coach panel pinned to a ply - the move-row entry point
    /// (decision A), wired from a right-click/hover context menu.
    let onAskCoach: (Int) -> Void

    private var pairs: [(number: Int, white: MoveIndex?, black: MoveIndex?)] {
        let plies = Array(viewModel.moveIndices.dropFirst())
        return stride(from: 0, to: plies.count, by: 2).map { i in
            (number: i / 2 + 1, white: plies[i], black: i + 1 < plies.count ? plies[i + 1] : nil)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(pairs, id: \.number) { pair in
                    HStack(spacing: 0) {
                        Text("\(pair.number).")
                            .font(.dsNotation)
                            .foregroundStyle(DesignColors.textSecondary)
                            .frame(width: 28, alignment: .leading)
                        moveCell(pair.white)
                        moveCell(pair.black)
                    }

                    // Variations exploring off either move of this pair -
                    // rendered as a full-width row under the pair.
                    ForEach([pair.white, pair.black].compactMap { $0 }, id: \.self) { index in
                        ForEach(viewModel.exploredChildren(of: index), id: \.self) { branchRoot in
                            ForEach(viewModel.variationRows(startingAt: branchRoot, depth: 1), id: \.index) { row in
                                variationRow(index: row.index, depth: row.depth)
                            }
                        }
                    }
                }

                // Variations exploring off the start position.
                if let start = viewModel.moveIndices.first {
                    ForEach(viewModel.exploredChildren(of: start), id: \.self) { branchRoot in
                        ForEach(viewModel.variationRows(startingAt: branchRoot, depth: 1), id: \.index) { row in
                            variationRow(index: row.index, depth: row.depth)
                        }
                    }
                }
            }
            .padding(DesignSpacing.sm)
        }
    }

    @ViewBuilder
    private func moveCell(_ index: MoveIndex?) -> some View {
        if let index, let san = viewModel.san(at: index) {
            Button {
                viewModel.jump(to: index)
            } label: {
                HStack(spacing: DesignSpacing.xs) {
                    if let classification = viewModel.classification(at: index) {
                        classificationMark(classification)
                    }
                    Text(san).font(.dsNotation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSpacing.xs)
                .padding(.vertical, 3)
                .background(
                    index == viewModel.currentIndex
                        ? DesignColors.selection : Color.clear
                )
                .overlay(alignment: .leading) {
                    if index == viewModel.currentIndex {
                        Rectangle().fill(DesignColors.accent).frame(width: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                viewModel.classification(at: index).map {
                    "\(san), \($0.abbreviation)"
                } ?? san
            )
            .contextMenu {
                Button("Ask the coach about this move") {
                    guard let ply = viewModel.moveIndices.firstIndex(of: index) else { return }
                    onAskCoach(ply)
                }
            }
        } else {
            Spacer().frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func classificationMark(_ classification: MoveClassification) -> some View {
        Group {
            switch classification.compactMark {
            case .systemImage(let name):
                Image(systemName: name)
                    .imageScale(.small)
            case .text(let mark):
                Text(mark)
                    .monospaced()
            }
        }
        .font(.dsSecondary.weight(.semibold))
        .foregroundStyle(classification.color)
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    private func variationRow(index: MoveIndex, depth: Int) -> some View {
        HStack(spacing: DesignSpacing.xs) {
            Button {
                viewModel.jump(to: index)
            } label: {
                Text(viewModel.san(at: index) ?? "")
                    .font(.dsNotation.italic())
                    .foregroundStyle(DesignColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSpacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        index == viewModel.currentIndex
                            ? DesignColors.selection : Color.clear
                    )
                    .overlay(alignment: .leading) {
                        if index == viewModel.currentIndex {
                            Rectangle().fill(DesignColors.accent).frame(width: 2)
                        }
                    }
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.deleteVariation(at: index) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("delete-variation-\(viewModel.san(at: index) ?? "")")
        }
        .padding(.leading, CGFloat(depth) * 16)
    }
}
