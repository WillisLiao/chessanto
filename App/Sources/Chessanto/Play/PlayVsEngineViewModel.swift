import Combine
import Foundation
import ChessCore
import EngineKit
import Persistence

/// View model managing the Play vs Engine flow: new game setup, active live game
/// turn loop and board interaction, live player controls (resign, claim draw),
/// and game completion transitions.
@MainActor
final class PlayVsEngineViewModel: ObservableObject {
    enum Stage: Equatable {
        case setup
        case playing
        case completed(GameOutcome)
    }

    @Published var stage: Stage = .setup
    @Published var selectedSide: PlayerSideSelection = .white
    @Published var selectedStrength: EngineStrength = .intermediate
    @Published var isFlipped: Bool = false
    @Published var isResignConfirmationPresented: Bool = false
    @Published var isDrawClaimAlertPresented: Bool = false
    @Published var drawClaimAlertMessage: String?
    @Published private(set) var session: LiveGameSession?
    @Published private(set) var interaction = BoardInteraction()

    private var cancellables = Set<AnyCancellable>()

    var isGameActive: Bool {
        stage == .playing && session?.isGameOver == false
    }

    var isGameOver: Bool {
        if case .completed = stage { return true }
        return session?.isGameOver == true
    }

    var isEngineThinking: Bool {
        session?.isEngineThinking == true
    }

    var isUserTurn: Bool {
        session?.status == .userTurn
    }

    var position: BoardPosition {
        session?.position ?? .empty
    }

    var lastMove: (from: BoardSquare, to: BoardSquare)? {
        session?.lastMove
    }

    var playedMovesSAN: [String] {
        session?.playedMovesSAN ?? []
    }

    var currentFEN: String? {
        session?.currentFEN
    }

    var isCheck: Bool {
        session?.isCheck == true
    }

    var persistedRecord: GameRecord? {
        session?.persistedRecord
    }

    var outcome: GameOutcome? {
        if case .completed(let outcome) = stage {
            return outcome
        }
        return session?.outcome
    }

    var userColor: ChessCore.PieceColor {
        session?.userColor ?? (selectedSide == .black ? ChessCore.PieceColor.black : ChessCore.PieceColor.white)
    }

    var engineColor: ChessCore.PieceColor {
        session?.engineColor ?? (userColor == .white ? ChessCore.PieceColor.black : ChessCore.PieceColor.white)
    }

    var canClaimDraw: Bool {
        guard let session, !session.isGameOver else { return false }
        return ChessGame.isThreefoldRepetition(fens: session.historyFENs) ||
            ChessGame.isFiftyMoveDraw(fen: session.currentFEN)
    }

    var selectedSquare: BoardSquare? {
        interaction.selectedSquare
    }

    var pendingPromotion: BoardInteraction.PendingPromotion? {
        interaction.pendingPromotion
    }

    var legalDestinations: Set<BoardSquare> {
        interaction.legalDestinations(context: boardInteractionContext)
    }

    var boardInteractionContext: BoardInteraction.Context {
        guard let session else {
            return BoardInteraction.Context(
                position: .empty,
                legalDestinations: { _ in [] },
                isPromotion: { _, _ in false }
            )
        }
        return BoardInteraction.Context(
            position: session.position,
            legalDestinations: { square in
                Set(
                    session.legalDestinations(from: SquareCoordinate(notation: square.algebraic))
                        .compactMap { BoardSquare(algebraic: $0.notation) }
                )
            },
            isPromotion: { from, to in
                session.isPromotion(
                    from: SquareCoordinate(notation: from.algebraic),
                    to: SquareCoordinate(notation: to.algebraic)
                )
            }
        )
    }

    init(
        selectedSide: PlayerSideSelection = .white,
        selectedStrength: EngineStrength = .intermediate
    ) {
        self.selectedSide = selectedSide
        self.selectedStrength = selectedStrength
    }

    func startGame(
        store: GameStore,
        userProfile: UserProfileRecord? = nil,
        engineOpponent: any EngineOpponent,
        startedAt: Date = Date(),
        fixedColor: ChessCore.PieceColor? = nil
    ) async {
        let liveSession = LiveGameSession(
            userSideSelection: selectedSide,
            engineStrength: selectedStrength,
            engineOpponent: engineOpponent,
            store: store,
            userProfile: userProfile,
            startedAt: startedAt,
            fixedColor: fixedColor
        )
        self.session = liveSession
        self.isFlipped = (liveSession.userColor == ChessCore.PieceColor.black)
        self.interaction.reset()
        self.stage = .playing

        liveSession.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] (status: LiveGameSession.LiveGameStatus) in
                if case .completed(let outcome) = status {
                    self?.stage = .completed(outcome)
                }
            }
            .store(in: &cancellables)

        await liveSession.start()
        if let outcome = liveSession.outcome {
            self.stage = .completed(outcome)
        }
    }

    func handleSquareTapped(_ square: BoardSquare) async {
        guard let session, session.status == .userTurn else { return }
        let resolution = interaction.select(square, context: boardInteractionContext)
        await applyResolution(resolution)
    }

    func handleDragStarted(_ square: BoardSquare) {
        guard let session, session.status == .userTurn else { return }
        interaction.beginDrag(from: square, context: boardInteractionContext)
    }

    func handleDrop(from: BoardSquare, to: BoardSquare) async {
        guard let session, session.status == .userTurn else { return }
        let resolution = interaction.drop(from: from, to: to, context: boardInteractionContext)
        await applyResolution(resolution)
    }

    func handlePromotionChosen(_ kind: PromotionKind) async {
        let resolution = interaction.choosePromotion(kind)
        await applyResolution(resolution)
    }

    func handlePromotionCancelled() {
        interaction.cancelPromotion()
    }

    func resign() {
        guard let session, !session.isGameOver else { return }
        session.resign()
        if let outcome = session.outcome {
            stage = .completed(outcome)
        }
    }

    func claimDraw() {
        guard let session, !session.isGameOver else { return }
        let success = session.claimDraw()
        if success, let outcome = session.outcome {
            stage = .completed(outcome)
        } else {
            drawClaimAlertMessage = "No draw condition (3-fold repetition or 50-move rule) is currently met."
            isDrawClaimAlertPresented = true
        }
    }

    func resetToSetup() {
        cancellables.removeAll()
        session = nil
        interaction.reset()
        stage = .setup
    }

    func toggleFlip() {
        isFlipped.toggle()
    }

    private func applyResolution(_ resolution: BoardInteraction.Resolution) async {
        guard case .play(let move) = resolution, let session else { return }
        let from = SquareCoordinate(notation: move.from.algebraic)
        let to = SquareCoordinate(notation: move.to.algebraic)
        _ = await session.playUserMove(from: from, to: to, promotion: move.promotion ?? .queen)
        if let outcome = session.outcome {
            stage = .completed(outcome)
        }
    }
}
