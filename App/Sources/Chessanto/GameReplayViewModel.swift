import Foundation
import ChessCore
import Persistence
import AnalysisKit

struct EvalDisplay: Equatable {
    let whiteWinProbability: Double
    let label: String
    let isLive: Bool
    let depth: Int?
    let isGameOver: Bool
}

@MainActor
final class GameReplayViewModel: ObservableObject {
    @Published private(set) var position: BoardPosition = .empty
    @Published private(set) var moveIndices: [MoveIndex] = []
    @Published private(set) var currentIndex: MoveIndex
    @Published var loadError: String?

    /// Classification of mainline move `p`, at `classifications[p - 1]`.
    @Published private(set) var classifications: [MoveClassification] = []
    @Published private(set) var whiteAccuracy: Double?
    @Published private(set) var blackAccuracy: Double?
    @Published private(set) var isAnalyzed = false
    @Published var analysisError: String?

    private var chessGame: ChessGame?
    private let gameId: Int64?
    private let store: GameStore

    /// FENs aligned with `moveIndices` (index 0 = starting position).
    private(set) var fens: [String] = []
    /// UCI of the mainline move that produced `moveIndices[i]`; `nil` at index 0.
    private(set) var playedUCIs: [String?] = []

    /// Rank-1 analysis rows, keyed by ply index.
    private var cachedEvaluationsByPly: [Int: AnalysisRecord] = [:]

    init(record: GameRecord, store: GameStore) {
        self.store = store
        self.gameId = record.id
        do {
            let game = try ChessGame(pgn: record.pgn)
            self.chessGame = game
            self.currentIndex = game.startIndex
            self.moveIndices = [game.startIndex] + game.mainlineIndices
            self.fens = moveIndices.map { game.fen(at: $0) ?? "" }
            self.playedUCIs = moveIndices.map { game.uciMove(at: $0) }
            refreshPosition()
        } catch {
            self.currentIndex = .start
            self.loadError = "Couldn't parse this game's PGN: \(error.localizedDescription)"
        }

        if let gameId {
            Task { await loadCachedAnalysis(gameId: gameId) }
        }
    }

    var sanAtCurrent: String? {
        chessGame?.san(at: currentIndex)
    }

    func san(at index: MoveIndex) -> String? {
        chessGame?.san(at: index)
    }

    /// Classification for the mainline move at `index`, if analyzed.
    func classification(at index: MoveIndex) -> MoveClassification? {
        guard let position = moveIndices.firstIndex(of: index), position >= 1, position - 1 < classifications.count else {
            return nil
        }
        return classifications[position - 1]
    }

    func jump(to index: MoveIndex) {
        currentIndex = index
        refreshPosition()
    }

    func stepForward() {
        guard let chessGame else { return }
        let next = chessGame.next(after: currentIndex)
        guard moveIndices.contains(next) else { return }
        jump(to: next)
    }

    func stepBackward() {
        guard let chessGame else { return }
        let previous = chessGame.previous(before: currentIndex)
        jump(to: previous)
    }

    var canStepForward: Bool {
        guard let chessGame else { return false }
        return moveIndices.contains(chessGame.next(after: currentIndex))
    }

    var canStepBackward: Bool {
        currentIndex != chessGame?.startIndex
    }

    var currentFEN: String? {
        guard let ply = moveIndices.firstIndex(of: currentIndex), ply < fens.count else { return nil }
        return fens[ply]
    }

    private func refreshPosition() {
        guard let chessGame, let fen = chessGame.fen(at: currentIndex) else {
            position = .empty
            return
        }
        position = BoardPositionMapper.position(fromFEN: fen) ?? .empty
    }

    // MARK: - Analysis

    func evalDisplay(forPly ply: Int, live: EngineService.LiveEvaluation?) -> EvalDisplay? {
        guard ply < fens.count else { return nil }
        if let live, live.fen == fens[ply] {
            return makeEvalDisplay(scoreCentipawns: live.scoreCentipawns, mateIn: live.mateIn, isLive: true, depth: live.depth)
        }
        guard let cached = cachedEvaluationsByPly[ply] else { return nil }
        return makeEvalDisplay(
            scoreCentipawns: cached.scoreCentipawns, mateIn: cached.mateIn, isLive: false, depth: cached.depth
        )
    }

    func currentEvalDisplay(live: EngineService.LiveEvaluation?) -> EvalDisplay? {
        guard let ply = moveIndices.firstIndex(of: currentIndex) else { return nil }
        return evalDisplay(forPly: ply, live: live)
    }

    /// White win-probability at each ply, for the eval graph; `nil` for
    /// unanalyzed plies.
    var evalGraphSeries: [Double?] {
        fens.indices.map { ply in
            guard let record = cachedEvaluationsByPly[ply] else { return nil }
            return WinProbability.whiteWinProbability(scoreCentipawns: record.scoreCentipawns, mateIn: record.mateIn)
        }
    }

    private func makeEvalDisplay(scoreCentipawns: Int?, mateIn: Int?, isLive: Bool, depth: Int?) -> EvalDisplay {
        if let mateIn, abs(mateIn) == 99 {
            return EvalDisplay(
                whiteWinProbability: mateIn > 0 ? 100 : 0,
                label: mateIn > 0 ? "1-0" : "0-1",
                isLive: isLive, depth: depth, isGameOver: true
            )
        }
        let whiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: scoreCentipawns, mateIn: mateIn)
        let label: String
        if let mateIn {
            label = mateIn > 0 ? "M\(mateIn)" : "-M\(abs(mateIn))"
        } else if let cp = scoreCentipawns {
            label = String(format: "%+.1f", Double(cp) / 100)
        } else {
            label = "--"
        }
        return EvalDisplay(whiteWinProbability: whiteWinP, label: label, isLive: isLive, depth: depth, isGameOver: false)
    }

    private func loadCachedAnalysis(gameId: Int64) async {
        guard let records = try? await store.analysis(gameId: gameId) else { return }
        var byPly: [Int: AnalysisRecord] = [:]
        for record in records where record.multiPVRank == 1 {
            byPly[record.plyIndex] = record
        }
        cachedEvaluationsByPly = byPly
        isAnalyzed = !fens.isEmpty && fens.indices.allSatisfy { byPly[$0] != nil }
        deriveClassifications()
    }

    private func deriveClassifications() {
        guard isAnalyzed, moveIndices.count > 1 else {
            classifications = []
            whiteAccuracy = nil
            blackAccuracy = nil
            return
        }

        let evaluations: [PlyEvaluation] = (0..<moveIndices.count).map { ply in
            guard let record = cachedEvaluationsByPly[ply] else {
                return PlyEvaluation(scoreCentipawns: nil, mateIn: nil, bestMoveUCI: nil)
            }
            let bestUCI = record.principalVariation.split(separator: " ").first.map(String.init)
            return PlyEvaluation(scoreCentipawns: record.scoreCentipawns, mateIn: record.mateIn, bestMoveUCI: bestUCI)
        }

        let moveUCIs = Array(playedUCIs.dropFirst()).compactMap { $0 }
        let whiteToMove = (1..<moveIndices.count).map { $0 % 2 == 1 }

        guard moveUCIs.count == moveIndices.count - 1 else {
            classifications = []
            return
        }

        classifications = MoveClassifier.classify(
            positionEvaluations: evaluations, playedUCIs: moveUCIs, whiteToMove: whiteToMove
        )

        var whiteAccuracies: [Double] = []
        var blackAccuracies: [Double] = []
        for p in 1..<moveIndices.count {
            let before = evaluations[p - 1]
            let after = evaluations[p]
            let isWhite = whiteToMove[p - 1]
            let beforeWhiteWinP = WinProbability.whiteWinProbability(
                scoreCentipawns: before.scoreCentipawns, mateIn: before.mateIn
            )
            let afterWhiteWinP = WinProbability.whiteWinProbability(
                scoreCentipawns: after.scoreCentipawns, mateIn: after.mateIn
            )
            let moverBefore = WinProbability.moverWinProbability(whiteWinProbability: beforeWhiteWinP, whiteToMove: isWhite)
            let moverAfter = WinProbability.moverWinProbability(whiteWinProbability: afterWhiteWinP, whiteToMove: isWhite)
            let drop = max(0, moverBefore - moverAfter)
            let accuracy = Accuracy.perMove(drop: drop)
            if isWhite {
                whiteAccuracies.append(accuracy)
            } else {
                blackAccuracies.append(accuracy)
            }
        }
        whiteAccuracy = whiteAccuracies.isEmpty ? nil : Accuracy.average(whiteAccuracies)
        blackAccuracy = blackAccuracies.isEmpty ? nil : Accuracy.average(blackAccuracies)
    }

    /// Whether the game's last mainline move is checkmate, and if so, who
    /// delivered it - used to skip searching a terminal position.
    private var terminalMateWhiteWins: Bool? {
        guard let chessGame, let last = moveIndices.last, let san = chessGame.san(at: last), san.hasSuffix("#") else {
            return nil
        }
        let ply = moveIndices.count - 1
        return ply % 2 == 1
    }

    func analyze(engineService: EngineService, quality: AnalysisQuality) async {
        guard let gameId else { return }
        do {
            try await engineService.analyze(
                gameId: gameId, fens: fens, quality: quality, store: store,
                terminalMateWhiteWins: terminalMateWhiteWins
            )
        } catch is CancellationError {
            // Cancelled analysis leaves whatever plies finished cached; nothing to surface.
        } catch {
            analysisError = error.localizedDescription
        }
        await loadCachedAnalysis(gameId: gameId)
    }

    func reanalyze(engineService: EngineService, quality: AnalysisQuality) async {
        guard let gameId else { return }
        try? await store.deleteAnalysis(gameId: gameId)
        cachedEvaluationsByPly = [:]
        isAnalyzed = false
        classifications = []
        whiteAccuracy = nil
        blackAccuracy = nil
        await analyze(engineService: engineService, quality: quality)
    }
}
