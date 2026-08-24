import SwiftUI
import ChessCore
import EngineKit
import Persistence

/// The primary Play vs Engine screen.
/// Supports new-game setup, live interactive play with the engine using the
/// standard BoardView component, live game controls, and seamless transition
/// into the existing game report view upon completion.
struct PlayVsEngineView: View {
    @StateObject private var viewModel = PlayVsEngineViewModel()
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var engineService: EngineService
    @Environment(\.moveNotation) private var moveNotation

    let store: GameStore
    let engineOpponent: any EngineOpponent
    let onReviewGame: (GameRecord) -> Void

    private var userProfile: UserProfileRecord? {
        try? store.userProfile()
    }

    var body: some View {
        Group {
            switch viewModel.stage {
            case .setup:
                PlayVsEngineSetupView(
                    selectedSide: $viewModel.selectedSide,
                    selectedStrength: $viewModel.selectedStrength,
                    onStartGame: {
                        Task {
                            await viewModel.startGame(
                                store: store,
                                userProfile: userProfile,
                                engineOpponent: engineOpponent
                            )
                        }
                    }
                )
            case .playing, .completed:
                liveGameInterface
            }
        }
        .alert("Resign Game?", isPresented: $viewModel.isResignConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Resign", role: .destructive) {
                viewModel.resign()
            }
        } message: {
            Text("Resigning will end this game and award the win to Stockfish.")
        }
        .alert("Draw Claim", isPresented: $viewModel.isDrawClaimAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.drawClaimAlertMessage ?? "No draw condition has been reached.")
        }
        .onKeyPress("f") {
            viewModel.toggleFlip()
            return .handled
        }
    }

    private var liveGameInterface: some View {
        HSplitView {
            boardColumn
                .frame(minWidth: 420)

            rightColumn
                .frame(minWidth: 260, maxWidth: 340)
        }
    }

    // MARK: - Board Column

    private var boardColumn: some View {
        VStack(spacing: DesignSpacing.sm) {
            VStack(spacing: DesignSpacing.xs) {
                topIdentityStrip

                BoardView(
                    position: viewModel.position,
                    lastMove: viewModel.lastMove,
                    flipped: viewModel.isFlipped,
                    theme: library.boardTheme,
                    selectedSquare: viewModel.selectedSquare,
                    legalDestinations: viewModel.legalDestinations,
                    pendingPromotion: viewModel.pendingPromotion,
                    onSquareTapped: { square in
                        Task { await viewModel.handleSquareTapped(square) }
                    },
                    onPieceDragStarted: { square in
                        viewModel.handleDragStarted(square)
                    },
                    onPieceDropped: { from, to in
                        Task { await viewModel.handleDrop(from: from, to: to) }
                    },
                    onPromotionChosen: { kind in
                        Task { await viewModel.handlePromotionChosen(kind) }
                    },
                    onPromotionCancelled: {
                        viewModel.handlePromotionCancelled()
                    }
                )

                bottomIdentityStrip
            }
            .padding()

            boardControls
        }
    }

    private var topIdentityStrip: some View {
        let strips = identityStrips(flipped: viewModel.isFlipped)
        return HStack {
            BoardIdentityStripView(info: strips.top)
            Spacer()
            if viewModel.isEngineThinking && !isTopUser {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Calculating...")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
        }
    }

    private var bottomIdentityStrip: some View {
        let strips = identityStrips(flipped: viewModel.isFlipped)
        return HStack {
            BoardIdentityStripView(info: strips.bottom)
            Spacer()
            if viewModel.isUserTurn && isBottomUser && !viewModel.isGameOver {
                Text("Your turn")
                    .font(.dsSecondary.weight(.semibold))
                    .foregroundStyle(DesignColors.accentText)
            }
        }
    }

    private var isTopUser: Bool {
        let strips = identityStrips(flipped: viewModel.isFlipped)
        return strips.top.isUser
    }

    private var isBottomUser: Bool {
        let strips = identityStrips(flipped: viewModel.isFlipped)
        return strips.bottom.isUser
    }

    private func identityStrips(flipped: Bool) -> (top: BoardIdentityStripInfo, bottom: BoardIdentityStripInfo) {
        guard let session = viewModel.session else {
            return (
                top: BoardIdentityStripInfo(name: "Stockfish", rating: nil, isUser: false),
                bottom: BoardIdentityStripInfo(name: "Player", rating: nil, isUser: true)
            )
        }

        let userName = userProfile?.chessComUsername?.isEmpty == false ? userProfile!.chessComUsername! : "Player"
        let engineName = "Stockfish (\(session.engineStrength.name))"

        let whiteName = session.userColor == .white ? userName : engineName
        let blackName = session.userColor == .black ? userName : engineName
        let whiteRating = session.userColor == .white ? nil : session.engineStrength.estimatedElo
        let blackRating = session.userColor == .black ? nil : session.engineStrength.estimatedElo

        return BoardIdentityStrip.strips(
            whiteName: whiteName,
            blackName: blackName,
            whiteRating: whiteRating,
            blackRating: blackRating,
            flipped: flipped,
            username: userName
        )
    }

    private var boardControls: some View {
        HStack(spacing: DesignSpacing.md) {
            Button {
                viewModel.toggleFlip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Flip board")

            if viewModel.isCheck && !viewModel.isGameOver {
                Chip("Check", color: DesignColors.error)
            }

            Spacer()

            if viewModel.isGameOver {
                Button("New Game") {
                    viewModel.resetToSetup()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(spacing: 0) {
            statusHeader

            Divider()

            moveScoresheet

            Divider()

            controlsFooter
        }
        .background(DesignColors.surface0)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            if viewModel.isGameOver, let outcome = viewModel.outcome {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(outcome.resultString)
                            .font(.dsTitle)
                            .foregroundStyle(DesignColors.textPrimary)
                        Spacer()
                        Chip(outcomeStatusLabel(outcome), color: outcomeChipColor(outcome))
                    }
                    Text(outcome.terminationDescription)
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            } else if viewModel.isEngineThinking {
                HStack(spacing: DesignSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Stockfish is thinking...")
                        .font(.dsBody.weight(.medium))
                        .foregroundStyle(DesignColors.textSecondary)
                }
            } else if viewModel.isUserTurn {
                HStack(spacing: DesignSpacing.xs) {
                    Circle()
                        .fill(DesignColors.accent)
                        .frame(width: 8, height: 8)
                    Text("Your turn")
                        .font(.dsBody.weight(.semibold))
                        .foregroundStyle(DesignColors.textPrimary)
                }
            } else {
                Text("Waiting...")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding(DesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.surface1)
    }

    private func outcomeStatusLabel(_ outcome: GameOutcome) -> String {
        guard let winner = outcome.winner else {
            return "Draw"
        }
        if let session = viewModel.session {
            return winner == session.userColor ? "Victory" : "Defeat"
        }
        return "\(winner.rawValue.capitalized) Won"
    }

    private func outcomeChipColor(_ outcome: GameOutcome) -> Color {
        guard let winner = outcome.winner else {
            return DesignColors.textSecondary
        }
        if let session = viewModel.session {
            return winner == session.userColor ? DesignColors.accentText : DesignColors.error
        }
        return DesignColors.accentText
    }

    private var moveScoresheet: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(movePairs, id: \.number) { pair in
                        HStack(spacing: 0) {
                            Text("\(pair.number).")
                                .font(.dsNotation)
                                .foregroundStyle(DesignColors.textSecondary)
                                .frame(width: 32, alignment: .leading)

                            Text(moveNotation.move(pair.whiteSAN).visual)
                                .font(.dsNotation.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)

                            if let blackSAN = pair.blackSAN {
                                Text(moveNotation.move(blackSAN).visual)
                                    .font(.dsNotation.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                            } else {
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                        .id(pair.number)
                    }
                }
                .padding(DesignSpacing.sm)
            }
            .onChange(of: viewModel.playedMovesSAN.count) { _, _ in
                if let lastMoveNumber = movePairs.last?.number {
                    withAnimation {
                        proxy.scrollTo(lastMoveNumber, anchor: .bottom)
                    }
                }
            }
        }
    }

    private struct MovePair: Identifiable {
        let number: Int
        let whiteSAN: String
        let blackSAN: String?

        var id: Int { number }
    }

    private var movePairs: [MovePair] {
        let moves = viewModel.playedMovesSAN
        var pairs: [MovePair] = []
        for i in stride(from: 0, to: moves.count, by: 2) {
            let moveNumber = (i / 2) + 1
            let whiteSAN = moves[i]
            let blackSAN = (i + 1 < moves.count) ? moves[i + 1] : nil
            pairs.append(MovePair(number: moveNumber, whiteSAN: whiteSAN, blackSAN: blackSAN))
        }
        return pairs
    }

    private var controlsFooter: some View {
        VStack(spacing: DesignSpacing.sm) {
            if viewModel.isGameOver {
                if let record = viewModel.persistedRecord {
                    Button {
                        onReviewGame(record)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Review Game & Report")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("review-game-button")
                }

                Button {
                    viewModel.resetToSetup()
                } label: {
                    Text("New Game")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("play-again-button")
            } else {
                HStack(spacing: DesignSpacing.sm) {
                    Button("Resign") {
                        viewModel.isResignConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("resign-button")

                    Button("Claim Draw") {
                        viewModel.claimDraw()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("claim-draw-button")

                    Spacer()

                    Button("New Game") {
                        viewModel.resetToSetup()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(DesignSpacing.md)
        .background(DesignColors.surface1)
    }
}
