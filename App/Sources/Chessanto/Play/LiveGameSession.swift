import Combine
import Foundation
import ChessCore
import EngineKit
import Persistence

/// State machine for a live game against an engine opponent.
///
/// Handles player side selection, turn transitions, move legality validation,
/// game-end detection (checkmate, stalemate, repetition, fifty-move rule,
/// insufficient material, resignation), and game persistence into `GameStore`.
@MainActor
final class LiveGameSession: ObservableObject {
    enum LiveGameStatus: Equatable, Sendable {
        case notStarted
        case userTurn
        case engineThinking
        case completed(GameOutcome)

        var isTerminal: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    let userSideSelection: PlayerSideSelection
    let userColor: ChessCore.PieceColor
    let engineColor: ChessCore.PieceColor
    let engineStrength: EngineStrength
    let engineOpponent: any EngineOpponent
    let store: GameStore
    let userProfile: UserProfileRecord?
    let startedAt: Date

    @Published private(set) var status: LiveGameStatus = .notStarted
    @Published private(set) var currentFEN: String
    @Published private(set) var position: BoardPosition
    @Published private(set) var lastMove: (from: BoardSquare, to: BoardSquare)?
    @Published private(set) var playedMovesSAN: [String] = []
    @Published private(set) var playedMovesUCI: [String] = []
    @Published private(set) var isCheck: Bool = false
    @Published private(set) var outcome: GameOutcome?
    @Published private(set) var persistedRecord: GameRecord?
    @Published private(set) var errorMessage: String?

    private(set) var chessGame: ChessGame
    private(set) var currentIndex: MoveIndex
    private(set) var historyFENs: [String] = []

    var isGameOver: Bool {
        status.isTerminal
    }

    var isEngineThinking: Bool {
        status == .engineThinking
    }

    var moveCount: Int {
        playedMovesSAN.count
    }

    var sanAtCurrent: String? {
        chessGame.san(at: currentIndex)
    }

    init(
        userSideSelection: PlayerSideSelection = .white,
        engineStrength: EngineStrength = .intermediate,
        engineOpponent: any EngineOpponent,
        store: GameStore,
        userProfile: UserProfileRecord? = nil,
        startedAt: Date = Date(),
        fixedColor: ChessCore.PieceColor? = nil
    ) {
        self.userSideSelection = userSideSelection
        let resolvedUserColor = fixedColor ?? userSideSelection.resolveColor()
        self.userColor = resolvedUserColor
        self.engineColor = resolvedUserColor.opposite
        self.engineStrength = engineStrength
        self.engineOpponent = engineOpponent
        self.store = store
        self.userProfile = userProfile
        self.startedAt = startedAt

        let initialGame = ChessGame()
        self.chessGame = initialGame
        self.currentIndex = initialGame.startIndex
        let startingFEN = initialGame.fen(at: initialGame.startIndex) ?? "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        self.currentFEN = startingFEN
        self.historyFENs = [startingFEN]
        self.position = BoardPositionMapper.position(fromFEN: startingFEN) ?? .empty
        self.isCheck = false
    }

    func start() async {
        guard status == .notStarted else { return }
        if userColor == .white {
            status = .userTurn
        } else {
            status = .engineThinking
            await triggerEngineTurn()
        }
    }

    @discardableResult
    func playUserMove(
        from start: SquareCoordinate,
        to end: SquareCoordinate,
        promotion: PromotionKind = .queen
    ) async -> Bool {
        guard status == .userTurn else { return false }
        let isCapture = hasEnemyPiece(at: end)
        guard let newIndex = chessGame.playMove(from: start, to: end, at: currentIndex, promotion: promotion) else {
            return false
        }
        applyMove(newIndex: newIndex, fromSquare: start.notation, toSquare: end.notation, isCapture: isCapture)

        if let detectedOutcome = ChessGame.detectOutcome(currentFEN: currentFEN, historyFENs: historyFENs) {
            completeGame(with: detectedOutcome)
            return true
        }

        status = .engineThinking
        await triggerEngineTurn()
        return true
    }

    @discardableResult
    func playUserMove(uci: String) async -> Bool {
        guard status == .userTurn else { return false }
        guard let parsed = parseUCISquares(uci: uci) else { return false }
        let isCapture = hasEnemyPiece(at: parsed.to)
        guard let newIndex = chessGame.playMove(uci: uci, at: currentIndex) else {
            return false
        }
        applyMove(newIndex: newIndex, fromSquare: parsed.from, toSquare: parsed.to, isCapture: isCapture)

        if let detectedOutcome = ChessGame.detectOutcome(currentFEN: currentFEN, historyFENs: historyFENs) {
            completeGame(with: detectedOutcome)
            return true
        }

        status = .engineThinking
        await triggerEngineTurn()
        return true
    }

    @discardableResult
    func playUserMove(san: String) async -> Bool {
        guard status == .userTurn else { return false }
        guard let newIndex = chessGame.playMove(san: san, at: currentIndex) else {
            return false
        }
        let uci = chessGame.uciMove(at: newIndex)
        let parsed = uci.flatMap { parseUCISquares(uci: $0) }
        let isCapture = san.contains("x")
        applyMove(
            newIndex: newIndex,
            fromSquare: parsed?.from,
            toSquare: parsed?.to,
            isCapture: isCapture
        )

        if let detectedOutcome = ChessGame.detectOutcome(currentFEN: currentFEN, historyFENs: historyFENs) {
            completeGame(with: detectedOutcome)
            return true
        }

        status = .engineThinking
        await triggerEngineTurn()
        return true
    }

    func resign() {
        guard !status.isTerminal else { return }
        let outcome = GameOutcome.resignation(resignedBy: userColor)
        completeGame(with: outcome)
    }

    func claimDraw() -> Bool {
        guard !status.isTerminal else { return false }
        if ChessGame.isThreefoldRepetition(fens: historyFENs) {
            completeGame(with: .repetition)
            return true
        }
        if ChessGame.isFiftyMoveDraw(fen: currentFEN) {
            completeGame(with: .fiftyMoveRule)
            return true
        }
        return false
    }

    func legalDestinations(from square: SquareCoordinate) -> [SquareCoordinate] {
        guard status == .userTurn else { return [] }
        return chessGame.legalMoves(from: square, at: currentIndex)
    }

    func isPromotion(from start: SquareCoordinate, to end: SquareCoordinate) -> Bool {
        chessGame.isPromotion(from: start, to: end, at: currentIndex)
    }

    // MARK: - Private Engine Turn & Move Handling

    private func triggerEngineTurn() async {
        do {
            let engineMoveUCI = try await engineOpponent.generateMove(in: currentFEN, strength: engineStrength)
            guard let parsed = parseUCISquares(uci: engineMoveUCI) else {
                errorMessage = "Engine generated malformed move: \(engineMoveUCI)"
                return
            }
            let isCapture = hasEnemyPiece(at: parsed.to)
            guard let newIndex = chessGame.playMove(uci: engineMoveUCI, at: currentIndex) else {
                errorMessage = "Engine attempted illegal move: \(engineMoveUCI)"
                return
            }
            applyMove(newIndex: newIndex, fromSquare: parsed.from, toSquare: parsed.to, isCapture: isCapture)

            if let detectedOutcome = ChessGame.detectOutcome(currentFEN: currentFEN, historyFENs: historyFENs) {
                completeGame(with: detectedOutcome)
            } else {
                status = .userTurn
            }
        } catch {
            errorMessage = "Engine error: \(error.localizedDescription)"
        }
    }

    private func applyMove(
        newIndex: MoveIndex,
        fromSquare: String?,
        toSquare: String?,
        isCapture: Bool
    ) {
        currentIndex = newIndex
        guard let fen = chessGame.fen(at: newIndex) else { return }
        currentFEN = fen
        historyFENs.append(fen)
        position = BoardPositionMapper.position(fromFEN: fen) ?? .empty

        if let san = chessGame.san(at: newIndex) {
            playedMovesSAN.append(san)
        }
        if let uci = chessGame.uciMove(at: newIndex) {
            playedMovesUCI.append(uci)
        }

        if let fromSquare, let toSquare,
            let fromBoardSquare = BoardSquare(algebraic: fromSquare),
            let toBoardSquare = BoardSquare(algebraic: toSquare)
        {
            lastMove = (from: fromBoardSquare, to: toBoardSquare)
        } else {
            lastMove = nil
        }

        isCheck = ChessGame.isCheck(fen: fen)
        BoardSounds.shared.play(isCapture ? .capture : .move)
    }

    private func completeGame(with outcome: GameOutcome) {
        self.outcome = outcome
        self.status = .completed(outcome)
        persistFinishedGame(outcome: outcome)
    }

    private func persistFinishedGame(outcome: GameOutcome) {
        let pgn = buildPGN(outcome: outcome)
        let whiteName = userColor == .white ? userName : engineName
        let blackName = userColor == .black ? userName : engineName
        let whiteRating = userColor == .white ? userEstimatedElo : engineStrength.estimatedElo
        let blackRating = userColor == .black ? userEstimatedElo : engineStrength.estimatedElo

        let record = GameRecord(
            source: .vsEngine,
            sourceURL: nil,
            pgn: pgn,
            white: whiteName,
            black: blackName,
            whiteRating: whiteRating,
            blackRating: blackRating,
            result: outcome.resultString,
            timeControl: nil,
            playedAt: startedAt,
            importedAt: Date()
        )

        do {
            let saved = try store.save(record)
            self.persistedRecord = saved
        } catch {
            errorMessage = "Failed to persist game: \(error.localizedDescription)"
        }
    }

    func buildPGN(outcome: GameOutcome) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let dateString = dateFormatter.string(from: startedAt)

        let whiteName = userColor == .white ? userName : engineName
        let blackName = userColor == .black ? userName : engineName

        var tags = [
            "[Event \"Play vs Engine\"]",
            "[Site \"Chessanto\"]",
            "[Date \"\(dateString)\"]",
            "[Round \"-\"]",
            "[White \"\(whiteName)\"]",
            "[Black \"\(blackName)\"]",
            "[Result \"\(outcome.resultString)\"]"
        ]

        if let whiteRating = userColor == .white ? userEstimatedElo : engineStrength.estimatedElo {
            tags.append("[WhiteElo \"\(whiteRating)\"]")
        }
        if let blackRating = userColor == .black ? userEstimatedElo : engineStrength.estimatedElo {
            tags.append("[BlackElo \"\(blackRating)\"]")
        }
        tags.append("[Termination \"\(outcome.terminationDescription)\"]")

        let header = tags.joined(separator: "\n")
        let moveText = formatPGNMoves(playedMovesSAN, result: outcome.resultString)

        return "\(header)\n\n\(moveText)\n"
    }

    private var userName: String {
        if let username = userProfile?.chessComUsername, !username.isEmpty {
            return username
        }
        return "Player"
    }

    private var engineName: String {
        "Stockfish (\(engineStrength.name))"
    }

    private var userEstimatedElo: Int? {
        nil
    }

    private func formatPGNMoves(_ moves: [String], result: String) -> String {
        var parts: [String] = []
        for (i, move) in moves.enumerated() {
            if i % 2 == 0 {
                let moveNumber = (i / 2) + 1
                parts.append("\(moveNumber). \(move)")
            } else {
                parts.append(move)
            }
        }
        if !result.isEmpty {
            parts.append(result)
        }
        return parts.joined(separator: " ")
    }

    private func parseUCISquares(uci: String) -> (from: String, to: String)? {
        guard uci.count >= 4 else { return nil }
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        return (from, to)
    }

    private func hasEnemyPiece(at square: String) -> Bool {
        guard let boardSquare = BoardSquare(algebraic: square),
            let piece = position.pieces[boardSquare]
        else { return false }
        let activeSide = ChessGame.sideToMove(fen: currentFEN)
        return piece.color.rawValue != activeSide.rawValue
    }

    private func hasEnemyPiece(at coordinate: SquareCoordinate) -> Bool {
        hasEnemyPiece(at: coordinate.notation)
    }
}
