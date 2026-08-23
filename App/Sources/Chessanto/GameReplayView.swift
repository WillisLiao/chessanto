import SwiftUI
import ChessCore
import Persistence
import AnalysisKit
import CoachKit
import CompanionDomain

struct GameReplayView: View {
    @StateObject private var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var coachService: CoachService
    @EnvironmentObject private var companion: MacCompanionManager
    private let game: GameRecord
    private let store: GameStore

    @State private var quality: AnalysisQuality = .standard
    @State private var analysisTask: Task<Void, Never>?
    @State private var interaction = BoardInteraction()
    /// A game-review app should open on the review. The scoresheet is one
    /// click away; the report was two plus knowing it existed.
    @State private var rightPaneTab: RightPaneTab = .report
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

    /// Below this content width the Coach panel slides over the Moves/Report
    /// pane instead of docking as a third column (decision A).
    ///
    /// This is the *detail pane's* width, not the window's, and the sidebar
    /// takes about 300 of the window before this is measured. At the old
    /// 1100 the Coach could therefore never dock on a laptop: a 13-inch Air
    /// gives roughly 980 points here, so the panel always covered the move
    /// list it is supposed to sit beside. 960 clears that, and the board is
    /// the element that gives up the difference - it already sizes itself
    /// from leftover space through `aspectRatio(.fit)`, so it shrinks rather
    /// than forcing anything to overflow.
    private static let coachDockWidthThreshold: CGFloat = 960

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
            case .down: jumpToKeyMoment(.next)
            case .up: jumpToKeyMoment(.previous)
            @unknown default: break
            }
        }
        // Single-key shortcuts match the muscle memory of every online
        // board. They only fire while the board has focus, so the Game menu
        // carries a modifier equivalent of each that always works.
        .onKeyPress("f") {
            flipped.toggle()
            return .handled
        }
        .onKeyPress(.space) {
            toggleLinePlayback()
            return .handled
        }
        .onExitCommand {
            if isCoachOpen { isCoachOpen = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stepForwardRequested)) { _ in
            viewModel.stepForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stepBackwardRequested)) { _ in
            viewModel.stepBackward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextKeyMomentRequested)) { _ in
            jumpToKeyMoment(.next)
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousKeyMomentRequested)) { _ in
            jumpToKeyMoment(.previous)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flipBoardRequested)) { _ in
            flipped.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLinePlaybackRequested)) { _ in
            toggleLinePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .analyzeGameRequested)) { _ in
            guard engineService.isStarted, !engineService.isAnalyzing else { return }
            startAnalysis(reanalyze: viewModel.report != nil)
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
            interaction.reset()
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
                            pendingPromotion: interaction.pendingPromotion,
                            onSquareTapped: handleSquareTapped,
                            onPieceDragStarted: handleDragStarted,
                            onPieceDropped: handleDrop(from:to:),
                            onPromotionChosen: { kind in
                                play(interaction.choosePromotion(kind))
                            },
                            onPromotionCancelled: { interaction.cancelPromotion() }
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
                        onSelectMoment: {
                            handleKeyMoment($0, intent: .selectOnly)
                        },
                        onPlayBetterLine: {
                            handleKeyMoment($0, intent: .playBetterLine)
                        },
                        onPlayContinuation: playContinuation(moment:),
                        onAnalyze: { startAnalysis(reanalyze: false) }
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
            if !isCoachOpen {
                viewModel.unpinChat()
            }
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

    private func handleKeyMoment(
        _ moment: KeyMoment,
        intent: KeyMomentInteractionIntent
    ) {
        guard moment.ply < viewModel.moveIndices.count else { return }
        if intent == .selectOnly, linePreview != nil {
            endLinePreview()
        }
        coachMomentPly = moment.ply
        viewModel.jump(to: viewModel.moveIndices[moment.ply])
        if intent.startsBetterLinePreview, moment.betterMove != nil {
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
        interaction.reset()
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
                source: "Engine verified",
                emotion: .resting
            )
        }
        let narration = coachService.narrationsByPly[ply]
        let summary = viewModel.report.map { ReportText.momentSummary(moment, report: $0, includingMoveLabel: false) } ?? ""
        return CoachStageContent(
            eyebrow: "\(moveNumberLabel(ply: ply)) \(moment.evalSwing.playedSAN)",
            headline: CoachStageText.headline(for: moment.evalSwing.classification),
            message: CoachStageText.condensed(narration?.text ?? summary),
            source: narration?.source == .coach ? "Local Coach" : "Engine verified",
            emotion: coachEmotion(for: moment.evalSwing.classification)
        )
    }

    private func coachEmotion(for classification: MoveClassification) -> CoachEmotion {
        switch classification {
        case .blunder, .mistake:
            return .concerned
        case .inaccuracy, .missedWin:
            return .encouraging
        case .brilliant:
            return .delighted
        case .best, .excellent, .good:
            return .instructive
        case .book, .forced:
            return .instructive
        }
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

    /// The board knowledge the shared interaction machine needs, read off
    /// the currently displayed position.
    private var interactionContext: BoardInteraction.Context {
        BoardInteraction.Context(
            position: viewModel.position,
            legalDestinations: { square in
                Set(
                    viewModel.legalDestinations(from: SquareCoordinate(notation: square.algebraic))
                        .compactMap { BoardSquare(algebraic: $0.notation) }
                )
            },
            isPromotion: { from, to in
                viewModel.isPromotion(
                    from: SquareCoordinate(notation: from.algebraic),
                    to: SquareCoordinate(notation: to.algebraic)
                )
            }
        )
    }

    private var selectedSquare: BoardSquare? { interaction.selectedSquare }

    private var legalDestinations: Set<BoardSquare> {
        interaction.legalDestinations(context: interactionContext)
    }

    private func handleSquareTapped(_ square: BoardSquare) {
        play(interaction.select(square, context: interactionContext))
    }

    private func handleDragStarted(_ square: BoardSquare) {
        interaction.beginDrag(from: square, context: interactionContext)
    }

    private func handleDrop(from: BoardSquare, to: BoardSquare) {
        play(interaction.drop(from: from, to: to, context: interactionContext))
    }

    /// Plays a settled move. A promotion resolves to
    /// `.awaitingPromotionPiece` instead and nothing is played until the
    /// picker is answered.
    private func play(_ resolution: BoardInteraction.Resolution) {
        guard case .play(let move) = resolution else { return }
        let from = SquareCoordinate(notation: move.from.algebraic)
        let to = SquareCoordinate(notation: move.to.algebraic)
        Task { await viewModel.playMove(from: from, to: to, promotion: move.promotion ?? .queen) }
    }

    private enum KeyMomentDirection {
        case next
        case previous
    }

    /// Walks the report's key moments from wherever the board is, selecting
    /// the moment without starting its better-line playback - stepping
    /// through mistakes should not auto-play a line each time.
    private func jumpToKeyMoment(_ direction: KeyMomentDirection) {
        guard let moments = viewModel.report?.keyMoments, !moments.isEmpty else { return }
        // Key moments are indexed by position in `moveIndices`, the same
        // mapping `handleKeyMoment` uses to jump, so navigation has to speak
        // that and not a raw move index.
        let currentPly = viewModel.moveIndices.firstIndex(of: viewModel.currentIndex) ?? -1
        let target = direction == .next
            ? KeyMomentNavigator.next(after: currentPly, in: moments)
            : KeyMomentNavigator.previous(before: currentPly, in: moments)
        guard let target else { return }
        rightPaneTab = .report
        handleKeyMoment(target, intent: .selectOnly)
    }

    /// Space pauses or resumes whichever line is playing, and does nothing
    /// when no line is on the board.
    private func toggleLinePlayback() {
        guard let linePreview else { return }
        if linePreview.isPlaying {
            linePreview.pause()
        } else {
            linePreview.play()
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
                    Text("\(progress.done) of \(progress.total)")
                        .font(.dsSecondary.monospacedDigit())
                        .foregroundStyle(DesignColors.textSecondary)
                        .fixedSize()
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
                        Text(analyzedLabel)
                            .font(.dsSecondary.weight(.semibold))
                            .foregroundStyle(DesignColors.textPrimary)
                        Spacer()
                        if companion.canSendReports {
                            Button {
                                startSendToPhone()
                            } label: {
                                Image(systemName: "iphone.and.arrow.forward")
                            }
                            .buttonStyle(.borderless)
                            .help("Send this report to iPhone")
                            .accessibilityLabel("Send report to iPhone")
                            .disabled(companion.isSendingReport)
                        }
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
                        if companion.canSendReports {
                            Button {
                                startSendToPhone()
                            } label: {
                                Image(systemName: "iphone.and.arrow.forward")
                            }
                            .buttonStyle(.bordered)
                            .help("Analyze on this Mac and send to iPhone")
                            .accessibilityLabel(
                                "Analyze on this Mac and send to iPhone"
                            )
                            .disabled(companion.isSendingReport)
                        }
                    }
                }
            }
        }
        .padding(DesignSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
    }

    /// Reports the depth the stored analysis actually reached, not the depth
    /// the currently selected preset stands for. A game analyzed under the
    /// old fixed-movetime presets carries its preset name with whatever
    /// depth the machine managed, and re-analysing at the same preset now
    /// deepens it - so the two figures genuinely differ, and the honest one
    /// is what was measured.
    private var analyzedLabel: String {
        guard let depth = viewModel.analyzedDepth else {
            return "Analyzed · \(quality.label)"
        }
        return "Analyzed · depth \(depth)"
    }

    private func startAnalysis(reanalyze: Bool) {
        analysisTask?.cancel()
        analysisTask = Task {
            do {
                try await companion.analyzeLocally(
                    game: game,
                    quality: quality,
                    reanalyze: reanalyze
                )
            } catch is CancellationError {
                return
            } catch {
                viewModel.analysisError = error.localizedDescription
            }
            await viewModel.refreshAnalysisAfterExternalRun()
            library.reload()
        }
    }

    private func startSendToPhone() {
        analysisTask?.cancel()
        analysisTask = Task {
            await companion.analyzeAndSend(game: game, quality: quality)
            await viewModel.refreshAnalysisAfterExternalRun()
            library.reload()
        }
    }

    @ViewBuilder
    private var accuracySummary: some View {
        if let white = viewModel.whiteAccuracy, let black = viewModel.blackAccuracy {
            let isWhiteUser = BoardIdentityStrip.isUser(name: game.white, username: library.chessComUsername)
            let isBlackUser = BoardIdentityStrip.isUser(name: game.black, username: library.chessComUsername)
            HStack(spacing: DesignSpacing.xs) {
                Text(AccuracySummaryFormatter.format(side: "White", accuracy: white, isUser: isWhiteUser))
                    .foregroundStyle(isWhiteUser ? DesignColors.textPrimary : DesignColors.textSecondary)
                Text("·").foregroundStyle(DesignColors.textSecondary)
                Text(AccuracySummaryFormatter.format(side: "Black", accuracy: black, isUser: isBlackUser))
                    .foregroundStyle(isBlackUser ? DesignColors.textPrimary : DesignColors.textSecondary)
            }
            .font(.dsNotation.weight(.semibold))
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
            .accessibilityLabel("Ask Coach about current position (pins position)")
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

enum KeyMomentInteractionIntent: Equatable {
    case selectOnly
    case playBetterLine

    var startsBetterLinePreview: Bool {
        self == .playBetterLine
    }
}

/// Two-column notation table (move number | White | Black) - the standard
/// analysis-board layout, replacing the single tall column of M1-M8 (also
/// closes an M3 debt: variation rows sit inline in the same table).
/// Classification stops being a full capsule on every move (visual noise on
/// a 55-ply game); it's a quiet colored dot inline, with a chip reserved for
/// anything worth a second look (inaccuracy and worse, plus brilliancies).
private struct MoveListView: View {
    @Environment(\.moveNotation) private var moveNotation
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
                moveRows

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
    private var moveRows: some View {
        if moveNotation.style == .pieceNames {
            ForEach(
                Array(viewModel.moveIndices.dropFirst().enumerated()),
                id: \.element
            ) { offset, index in
                HStack(spacing: 0) {
                    Text(
                        offset.isMultiple(of: 2)
                            ? "\(offset / 2 + 1)."
                            : "\(offset / 2 + 1)..."
                    )
                    .font(.dsNotation)
                    .foregroundStyle(DesignColors.textSecondary)
                    .frame(width: 40, alignment: .leading)
                    moveCell(index)
                }
                variations(after: index)
            }
        } else {
            ForEach(pairs, id: \.number) { pair in
                HStack(spacing: 0) {
                    Text("\(pair.number).")
                        .font(.dsNotation)
                        .foregroundStyle(DesignColors.textSecondary)
                        .frame(width: 28, alignment: .leading)
                    moveCell(pair.white)
                    moveCell(pair.black)
                }

                ForEach([pair.white, pair.black].compactMap { $0 }, id: \.self) { index in
                    variations(after: index)
                }
            }
        }
    }

    @ViewBuilder
    private func variations(after index: MoveIndex) -> some View {
        ForEach(viewModel.exploredChildren(of: index), id: \.self) { branchRoot in
            ForEach(
                viewModel.variationRows(startingAt: branchRoot, depth: 1),
                id: \.index
            ) { row in
                variationRow(index: row.index, depth: row.depth)
            }
        }
    }

    @ViewBuilder
    private func moveCell(_ index: MoveIndex?) -> some View {
        if let index, let san = viewModel.san(at: index) {
            let isCurrent = index == viewModel.currentIndex
            let isPinned = viewModel.isMovePinned(index)
            Button {
                viewModel.jump(to: index)
            } label: {
                HStack(spacing: DesignSpacing.xs) {
                    if let classification = viewModel.classification(at: index) {
                        classificationMark(classification)
                    }
                    Text(moveNotation.move(san).visual)
                        .font(.dsNotation)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignColors.accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSpacing.xs)
                .padding(.vertical, 3)
                .background(
                    isCurrent
                        ? DesignColors.selection
                        : (isPinned ? DesignColors.selection.opacity(0.4) : Color.clear)
                )
                .overlay(alignment: .leading) {
                    if isCurrent {
                        Rectangle().fill(DesignColors.accent).frame(width: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                moveAccessibilityLabel(index: index, san: san, isPinned: isPinned)
            )
            .contextMenu {
                Button("Ask Coach about this move") {
                    guard let ply = viewModel.moveIndices.firstIndex(of: index) else { return }
                    onAskCoach(ply)
                }
            }
        } else {
            Spacer().frame(maxWidth: .infinity)
        }
    }

    private func moveAccessibilityLabel(index: MoveIndex, san: String, isPinned: Bool) -> String {
        let base = viewModel.classification(at: index).map {
            "\(moveNotation.move(san).spoken), \($0.abbreviation)"
        } ?? moveNotation.move(san).spoken
        return isPinned ? "\(base), pinned in Coach" : base
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
        let isCurrent = index == viewModel.currentIndex
        let isPinned = viewModel.isMovePinned(index)
        let san = viewModel.san(at: index) ?? ""
        return HStack(spacing: DesignSpacing.xs) {
            Button {
                viewModel.jump(to: index)
            } label: {
                HStack(spacing: DesignSpacing.xs) {
                    Text(
                        viewModel.san(at: index)
                            .map { moveNotation.move($0).visual } ?? ""
                    )
                        .font(.dsNotation.italic())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(DesignColors.textSecondary)
                    Spacer(minLength: 0)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignColors.accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSpacing.xs)
                .padding(.vertical, 2)
                .background(
                    isCurrent
                        ? DesignColors.selection
                        : (isPinned ? DesignColors.selection.opacity(0.4) : Color.clear)
                )
                .overlay(alignment: .leading) {
                    if isCurrent {
                        Rectangle().fill(DesignColors.accent).frame(width: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isPinned ? "\(moveNotation.move(san).spoken), pinned in Coach" : moveNotation.move(san).spoken
            )
            .contextMenu {
                Button("Ask Coach about this move") {
                    guard let ply = viewModel.moveIndices.firstIndex(of: index) else { return }
                    onAskCoach(ply)
                }
            }

            Button {
                Task { await viewModel.deleteVariation(at: index) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("delete-variation-\(san)")
        }
        .padding(.leading, CGFloat(depth) * 16)
    }
}
