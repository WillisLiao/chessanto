import Foundation
import ChessCore
import CoachKit
import Persistence
import AnalysisKit

struct EvalDisplay: Equatable {
    let whiteWinProbability: Double
    let label: String
    let isLive: Bool
    let depth: Int?
    let isGameOver: Bool
}

/// A single played move inside a user-explored variation branch, kept in
/// memory alongside its persisted row id (`nil` until the insert completes).
struct VariationNode: Equatable {
    let index: MoveIndex
    var dbId: Int64?
    let parentIndex: MoveIndex
    let san: String
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
    private let record: GameRecord

    /// FENs aligned with `moveIndices` (index 0 = starting position).
    private(set) var fens: [String] = []
    /// UCI of the mainline move that produced `moveIndices[i]`; `nil` at index 0.
    private(set) var playedUCIs: [String?] = []

    /// Rank-1 analysis rows, keyed by ply index.
    private var cachedEvaluationsByPly: [Int: AnalysisRecord] = [:]
    /// Every ranked row (rank 1-3) per ply - the M5 report needs the full
    /// engine lines, not just rank-1.
    private var cachedAllRanksByPly: [Int: [AnalysisRecord]] = [:]

    /// The M5 rule-based coaching report, built once the game is fully
    /// analyzed; invalidated (`nil`) while unanalyzed or re-analyzing.
    @Published private(set) var report: GameReport?
    /// The same `ReportInput` used to build `report` - kept so M6's coach
    /// can build its payloads from the exact same source values (one
    /// source of truth, no re-derivation).
    private(set) var reportInput: ReportInput?

    /// Children of each index that were reached by exploring a variation
    /// (mainline continuations are tracked separately via `moveIndices`).
    @Published private(set) var variationChildren: [MoveIndex: [MoveIndex]] = [:]
    private var variationNodes: [MoveIndex: VariationNode] = [:]
    private var resolvedVariationIndex: [Int64: MoveIndex] = [:]

    init(record: GameRecord, store: GameStore) {
        self.store = store
        self.record = record
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
            Task { await loadVariations(gameId: gameId) }
        }
    }

    var id: Int64? { gameId }

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

    /// The FEN of whatever position is displayed - mainline or a variation.
    var currentFEN: String? {
        chessGame?.fen(at: currentIndex)
    }

    /// Whether the displayed position is inside a user-explored variation.
    var isExploringVariation: Bool {
        guard let chessGame else { return false }
        return !chessGame.isMainline(currentIndex)
    }

    /// The mainline ply to highlight on the eval graph while exploring a
    /// variation - the ply the variation branched off from.
    var currentGraphPly: Int {
        guard let chessGame else { return 0 }
        return moveIndices.firstIndex(of: chessGame.mainlineAncestor(of: currentIndex)) ?? 0
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
        guard let fen = currentFEN else { return nil }
        if let live, live.fen == fen {
            return makeEvalDisplay(scoreCentipawns: live.scoreCentipawns, mateIn: live.mateIn, isLive: true, depth: live.depth)
        }
        guard let ply = moveIndices.firstIndex(of: currentIndex), let cached = cachedEvaluationsByPly[ply] else { return nil }
        return makeEvalDisplay(
            scoreCentipawns: cached.scoreCentipawns, mateIn: cached.mateIn, isLive: false, depth: cached.depth
        )
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
        let label = EvalLabel.format(scoreCentipawns: scoreCentipawns, mateIn: mateIn)
        if EvalLabel.isTerminalSentinel(mateIn: mateIn) {
            return EvalDisplay(
                whiteWinProbability: mateIn! > 0 ? 100 : 0,
                label: label,
                isLive: isLive, depth: depth, isGameOver: true
            )
        }
        let whiteWinP = WinProbability.whiteWinProbability(scoreCentipawns: scoreCentipawns, mateIn: mateIn)
        return EvalDisplay(whiteWinProbability: whiteWinP, label: label, isLive: isLive, depth: depth, isGameOver: false)
    }

    private func loadCachedAnalysis(gameId: Int64) async {
        guard let records = try? await store.analysis(gameId: gameId) else { return }
        var byPly: [Int: AnalysisRecord] = [:]
        var allRanksByPly: [Int: [AnalysisRecord]] = [:]
        for analysisRecord in records {
            allRanksByPly[analysisRecord.plyIndex, default: []].append(analysisRecord)
            if analysisRecord.multiPVRank == 1 {
                byPly[analysisRecord.plyIndex] = analysisRecord
            }
        }
        cachedEvaluationsByPly = byPly
        cachedAllRanksByPly = allRanksByPly
        isAnalyzed = !fens.isEmpty && fens.indices.allSatisfy { byPly[$0] != nil }
        deriveClassifications()
        buildReport()
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

    /// Builds the M5 coaching report from the cached analysis rows. The app
    /// maps `AnalysisRecord`s into `ReportInput` here so `AnalysisKit` stays
    /// DB-free; `nil` while unanalyzed.
    private func buildReport() {
        guard isAnalyzed, moveIndices.count > 1 else {
            report = nil
            reportInput = nil
            return
        }
        let plies: [PlyRecord] = fens.indices.map { ply in
            let lines = (cachedAllRanksByPly[ply] ?? [])
                .sorted { $0.multiPVRank < $1.multiPVRank }
                .map { record in
                    RankedLine(
                        rank: record.multiPVRank,
                        scoreCentipawns: record.scoreCentipawns,
                        mateIn: record.mateIn,
                        principalVariationUCI: record.principalVariation.isEmpty
                            ? [] : record.principalVariation.split(separator: " ").map(String.init),
                        depth: record.depth
                    )
                }
            return PlyRecord(fen: fens[ply], lines: lines, playedUCI: playedUCIs[ply])
        }
        let username = (try? store.userProfile())?.chessComUsername
        let input = ReportInput(
            plies: plies, whiteName: record.white, blackName: record.black,
            result: record.result ?? "*", chessComUsername: username
        )
        reportInput = input
        report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
    }

    /// The current user profile - read fresh each call since settings can
    /// change while a game is open.
    func userProfile() -> UserProfileRecord? {
        try? store.userProfile()
    }

    /// The user's numeric rating in *this* game (PLAN.md's adaptive rating
    /// register), matched by `chessComUsername` against white/black.
    var userRatingInThisGame: Int? {
        guard let username = userProfile()?.chessComUsername, !username.isEmpty else { return nil }
        if record.white.caseInsensitiveCompare(username) == .orderedSame { return record.whiteRating }
        if record.black.caseInsensitiveCompare(username) == .orderedSame { return record.blackRating }
        return nil
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
        cachedAllRanksByPly = [:]
        isAnalyzed = false
        classifications = []
        whiteAccuracy = nil
        blackAccuracy = nil
        report = nil
        reportInput = nil
        await analyze(engineService: engineService, quality: quality)
    }

    // MARK: - Exploration (variation play)

    /// Rebuilds the in-memory variation tree from persisted rows, replaying
    /// each move onto `chessGame` in insertion order (parents always precede
    /// their children, since a child can only be played after its parent).
    private func loadVariations(gameId: Int64) async {
        guard let records = try? await store.variations(gameId: gameId), !records.isEmpty else { return }
        guard var game = chessGame else { return }

        for record in records {
            guard let rowId = record.id else { continue }
            let parentIndex: MoveIndex?
            if let parentVariationId = record.parentVariationId {
                parentIndex = resolvedVariationIndex[parentVariationId]
            } else {
                parentIndex = record.parentPlyIndex < moveIndices.count ? moveIndices[record.parentPlyIndex] : nil
            }
            guard let parentIndex, let newIndex = game.playMove(san: record.moveSAN, at: parentIndex) else { continue }

            resolvedVariationIndex[rowId] = newIndex
            variationNodes[newIndex] = VariationNode(index: newIndex, dbId: rowId, parentIndex: parentIndex, san: record.moveSAN)
            variationChildren[parentIndex, default: []].append(newIndex)
        }

        chessGame = game
    }

    /// All children explored from `index`, whether it's a mainline ply or a
    /// variation node - for rendering the move-list tree.
    func exploredChildren(of index: MoveIndex) -> [MoveIndex] {
        variationChildren[index] ?? []
    }

    /// Flattens the variation tree rooted at `index` into rows for display:
    /// the principal (first-played) continuation stays at the same depth as
    /// its parent, while any additional child at a branch point starts a new,
    /// more deeply indented nested branch.
    func variationRows(startingAt index: MoveIndex, depth: Int) -> [(index: MoveIndex, depth: Int)] {
        var rows: [(index: MoveIndex, depth: Int)] = [(index, depth)]
        let children = exploredChildren(of: index)
        guard let first = children.first else { return rows }
        rows += variationRows(startingAt: first, depth: depth)
        for sibling in children.dropFirst() {
            rows += variationRows(startingAt: sibling, depth: depth + 1)
        }
        return rows
    }

    func isVariationNode(_ index: MoveIndex) -> Bool {
        variationNodes[index] != nil
    }

    /// Legal destinations for the piece at `square` in the currently displayed position.
    func legalDestinations(from square: SquareCoordinate) -> [SquareCoordinate] {
        guard let chessGame else { return [] }
        return chessGame.legalMoves(from: square, at: currentIndex)
    }

    /// Attempts to play a legal move at the currently displayed position.
    /// If it matches an existing mainline/variation continuation, just
    /// jumps there instead of creating a duplicate branch.
    @discardableResult
    func playMove(from start: SquareCoordinate, to end: SquareCoordinate, promotion: PromotionKind = .queen) async -> Bool {
        guard var game = chessGame else { return false }
        let parentIndex = currentIndex
        guard let newIndex = game.playMove(from: start, to: end, at: parentIndex, promotion: promotion) else { return false }
        chessGame = game
        await recordVariationMove(newIndex: newIndex, parentIndex: parentIndex)
        jump(to: newIndex)
        return true
    }

    /// Plays a sequence of already-legal SAN moves (e.g. an adopted engine
    /// line) as nested variation branches from the currently displayed
    /// position, one move deeper each time.
    func adoptLine(sanMoves: [String]) async {
        var parentIndex = currentIndex
        for san in sanMoves {
            guard var game = chessGame, let newIndex = game.playMove(san: san, at: parentIndex) else { break }
            chessGame = game
            await recordVariationMove(newIndex: newIndex, parentIndex: parentIndex)
            parentIndex = newIndex
        }
        jump(to: parentIndex)
    }

    /// Persists a newly played move as a variation row, unless it turned
    /// out to just replay an existing mainline/variation continuation.
    private func recordVariationMove(newIndex: MoveIndex, parentIndex: MoveIndex) async {
        guard let chessGame else { return }
        guard !moveIndices.contains(newIndex), variationNodes[newIndex] == nil else { return }
        guard let gameId, let san = chessGame.san(at: newIndex) else { return }

        let parentVariationId = variationNodes[parentIndex]?.dbId
        let parentPlyIndex = parentVariationId == nil ? (moveIndices.firstIndex(of: parentIndex) ?? 0) : 0
        let orderIndex = variationChildren[parentIndex]?.count ?? 0

        variationChildren[parentIndex, default: []].append(newIndex)
        variationNodes[newIndex] = VariationNode(index: newIndex, dbId: nil, parentIndex: parentIndex, san: san)

        guard let saved = try? await store.insertVariationMove(
            VariationRecord(
                gameId: gameId, parentPlyIndex: parentPlyIndex, moveSAN: san,
                orderIndex: orderIndex, parentVariationId: parentVariationId
            )
        ), let savedId = saved.id else { return }

        variationNodes[newIndex]?.dbId = savedId
        resolvedVariationIndex[savedId] = newIndex
    }

    /// Deletes a variation move and everything explored from it.
    func deleteVariation(at index: MoveIndex) async {
        guard let node = variationNodes[index], let dbId = node.dbId, let chessGame else { return }
        let mustJumpAway = isDescendant(currentIndex, of: index, in: chessGame)

        try? await store.deleteVariation(id: dbId)
        removeSubtree(at: index)

        if mustJumpAway {
            jump(to: chessGame.mainlineAncestor(of: index))
        }
    }

    /// Jumps back to the mainline position a variation branched off from.
    func backToGame() {
        guard let chessGame else { return }
        jump(to: chessGame.mainlineAncestor(of: currentIndex))
    }

    private func isDescendant(_ candidate: MoveIndex, of ancestor: MoveIndex, in chessGame: ChessGame) -> Bool {
        var current: MoveIndex? = candidate
        while let c = current {
            if c == ancestor { return true }
            current = chessGame.parent(of: c)
        }
        return false
    }

    // MARK: - Position chat (M7)

    /// The current key moment, if the displayed position's mainline
    /// ancestor ply is one of the report's key moments.
    var currentKeyMoment: KeyMoment? {
        report?.keyMoments.first { $0.ply == currentGraphPly }
    }

    /// The current position's ranked lines from cached analysis, when the
    /// displayed ply is an analyzed mainline ply - empty for a variation
    /// position or an unanalyzed game, in which case `CoachChat` seeds one
    /// live evaluation instead.
    var currentPositionRankedLines: [RankedLine] {
        guard !isExploringVariation, let ply = moveIndices.firstIndex(of: currentIndex),
            let records = cachedAllRanksByPly[ply]
        else { return [] }
        return records.sorted { $0.multiPVRank < $1.multiPVRank }.map {
            RankedLine(
                rank: $0.multiPVRank, scoreCentipawns: $0.scoreCentipawns, mateIn: $0.mateIn,
                principalVariationUCI: $0.principalVariation.isEmpty
                    ? [] : $0.principalVariation.split(separator: " ").map(String.init),
                depth: $0.depth
            )
        }
    }

    /// SAN of the path to `index`: the mainline prefix (up to the branch
    /// point, or the whole path if `index` is itself on the mainline), the
    /// branch ply, and the variation's own SAN segment beyond that branch
    /// (fact 6: `ChessGame.history(upTo:)` returns the full path from the
    /// start through `index`, variation branches included).
    private func chatMovePath(upTo index: MoveIndex) -> (mainlineSAN: [String], variationBranchPly: Int, variationSAN: [String]) {
        guard let chessGame else { return ([], 0, []) }
        let fullPath = chessGame.history(upTo: index)
        let branch = chessGame.mainlineAncestor(of: index)
        let branchPosition = fullPath.firstIndex(of: branch) ?? 0
        let mainlinePart = fullPath[0...branchPosition]
        let variationPart = branchPosition + 1 < fullPath.count ? fullPath[(branchPosition + 1)...] : []
        let mainlineSAN = mainlinePart.dropFirst().compactMap { san(at: $0) }
        let variationSAN = variationPart.compactMap { san(at: $0) }
        let branchPly = moveIndices.firstIndex(of: branch) ?? 0
        return (Array(mainlineSAN), branchPly, Array(variationSAN))
    }

    /// Assembles M7's chat payload input from the currently displayed
    /// position - `nil` only if the game failed to load.
    func chatContext() -> CoachChatContext? {
        guard let fen = currentFEN else { return nil }
        let path = chatMovePath(upTo: currentIndex)
        var oneLiner: String?
        var before: Double?
        var after: Double?
        if let report, let moment = currentKeyMoment {
            oneLiner = ReportText.momentSummary(moment, report: report)
            before = moment.evalSwing.moverWinProbabilityBefore
            after = moment.evalSwing.moverWinProbabilityAfter
        }
        return CoachChatContext(
            currentFEN: fen,
            isMainlinePosition: !isExploringVariation,
            mainlineMovesSAN: path.mainlineSAN,
            variationBranchPly: path.variationBranchPly,
            variationMovesSAN: path.variationSAN,
            currentPositionLines: currentPositionRankedLines,
            keyMomentOneLiner: oneLiner,
            keyMomentWinProbabilityBeforePercent: before,
            keyMomentWinProbabilityAfterPercent: after,
            whiteName: report?.whiteName,
            blackName: report?.blackName,
            result: report?.result,
            whiteAccuracy: report?.whiteAccuracy,
            blackAccuracy: report?.blackAccuracy
        )
    }

    /// A short label for what the chat is attached to ("Start position",
    /// "Move 12. Nf3", "Variation after 12...Nf3").
    var chatPositionLabel: String {
        guard let chessGame else { return "Current position" }
        guard currentIndex != chessGame.startIndex else { return "Start position" }
        guard let san = sanAtCurrent else { return "Current position" }
        let plyDepth = chessGame.history(upTo: currentIndex).count - 1
        let moveNumber = (plyDepth + 1) / 2
        let numberLabel = plyDepth % 2 == 1 ? "\(moveNumber)." : "\(moveNumber)..."
        return isExploringVariation ? "Variation after \(numberLabel) \(san)" : "Move \(numberLabel) \(san)"
    }

    private func removeSubtree(at index: MoveIndex) {
        for child in variationChildren[index] ?? [] {
            removeSubtree(at: child)
        }
        let node = variationNodes[index]
        if let dbId = node?.dbId {
            resolvedVariationIndex[dbId] = nil
        }
        variationNodes[index] = nil
        variationChildren[index] = nil
        if let parent = node?.parentIndex {
            variationChildren[parent]?.removeAll { $0 == index }
        }
    }
}
