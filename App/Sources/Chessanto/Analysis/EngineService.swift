import AnalysisKit
import ChessCore
import CoachKit
import EngineKit
import Foundation
import Persistence

public enum AnalysisQuality: String, CaseIterable, Sendable, Identifiable {
    case fast, standard, deep

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fast: return "Fast"
        case .standard: return "Standard"
        case .deep: return "Deep"
        }
    }

    var movetimeMilliseconds: Int {
        switch self {
        case .fast: return 100
        case .standard: return 350
        case .deep: return 2000
        }
    }
}

/// The app's single owner of the in-process Stockfish engine (only one
/// `Engine.start()` may exist per process - see EngineKit's AnalysisEngine
/// docs). Live infinite analysis while scrubbing and batch game analysis
/// share this one engine and are mutually exclusive.
@MainActor
public final class EngineService: ObservableObject {
    public struct LiveEvaluation: Sendable {
        public let generation: Int
        public let fen: String
        public let depth: Int?
        /// White-perspective.
        public let scoreCentipawns: Int?
        /// White-perspective.
        public let mateIn: Int?
        /// Rank-ordered MultiPV lines (raw, side-to-move perspective PVs).
        public let lines: [AnalysisEngine.EngineInfo]
    }

    @Published public private(set) var unavailableReason: String?
    @Published public private(set) var isStarted = false
    @Published public private(set) var liveEvaluation: LiveEvaluation?
    @Published public private(set) var isAnalyzing = false
    @Published public private(set) var batchProgress: (done: Int, total: Int)?

    private let engine = AnalysisEngine()
    private var routingTask: Task<Void, Never>?

    private var liveGeneration = 0
    private var liveFEN: String?
    private var liveLinesByRank: [Int: AnalysisEngine.EngineInfo] = [:]
    private var showPositionTask: Task<Void, Never>?
    private var lastLivePublish: Date = .distantPast
    private var pendingLiveFEN: String?

    private var batchCollector: BatchCollector?
    private var batchGeneration: Int?
    private var batchContinuation: CheckedContinuation<Void, Never>?

    public init() {}

    /// Starts the engine, if not already started. No-op (and never boots
    /// Stockfish) if the required NNUE networks aren't in the app bundle,
    /// since a search with no network loaded kills the whole process.
    public func start() async {
        guard !isStarted, unavailableReason == nil else { return }

        guard
            let bigNet = Bundle.main.url(forResource: "nn-1111cefa1111", withExtension: "nnue"),
            let smallNet = Bundle.main.url(forResource: "nn-37f18f62d772", withExtension: "nnue"),
            FileManager.default.fileExists(atPath: bigNet.path),
            FileManager.default.fileExists(atPath: smallNet.path)
        else {
            unavailableReason = "Analysis is unavailable: the engine's neural network files are missing from the app bundle."
            return
        }

        await engine.start(multipv: 3)
        await engine.setOption(name: "Hash", value: "256")
        isStarted = true

        routingTask = Task { [weak self, engine] in
            for await update in engine.updates {
                guard let self else { return }
                self.route(update)
            }
        }
    }

    // MARK: - Routing

    private func route(_ update: AnalysisEngine.EngineUpdate) {
        if batchCollector != nil {
            routeBatch(update)
        } else {
            routeLive(update)
        }
    }

    private func routeBatch(_ update: AnalysisEngine.EngineUpdate) {
        guard let generation = batchGeneration else { return }
        switch update {
        case .info(let info):
            guard info.generation == generation else { return }
            batchCollector?.record(info)
        case .bestMove(let gen, _):
            guard gen == generation else { return }
            batchContinuation?.resume()
            batchContinuation = nil
        }
    }

    private func routeLive(_ update: AnalysisEngine.EngineUpdate) {
        let filter = LiveGenerationFilter(liveGeneration: liveGeneration)
        switch update {
        case .info(let info):
            guard filter.isCurrent(info.generation), let fen = liveFEN else { return }
            liveLinesByRank[info.multiPVRank ?? 1] = info
            let now = Date()
            guard now.timeIntervalSince(lastLivePublish) > 0.1 else { return }
            publishLiveEvaluation(generation: info.generation, fen: fen)
            lastLivePublish = now
        case .bestMove:
            break
        }
    }

    private func publishLiveEvaluation(generation: Int, fen: String) {
        let lines = liveLinesByRank.keys.sorted().compactMap { liveLinesByRank[$0] }
        guard let rank1 = liveLinesByRank[1] else { return }
        liveEvaluation = LiveEvaluation(
            generation: generation,
            fen: fen,
            depth: rank1.depth,
            scoreCentipawns: EngineScoreNormalizer.whitePerspectiveScore(rank1.scoreCentipawns, fen: fen),
            mateIn: EngineScoreNormalizer.whitePerspectiveMate(rank1.mateIn, fen: fen),
            lines: lines
        )
    }

    // MARK: - Live API

    /// Debounces (200ms) then sets the position and starts an infinite
    /// search. If a batch analysis is running, only records the desired
    /// position - live analysis resumes once the batch finishes.
    public func showPosition(fen: String) {
        guard isStarted else { return }
        if isAnalyzing {
            pendingLiveFEN = fen
            return
        }

        showPositionTask?.cancel()
        showPositionTask = Task { [engine] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            liveLinesByRank = [:]
            liveEvaluation = nil
            liveFEN = fen
            liveGeneration = await engine.setPosition(fen: fen)
            await engine.goInfinite()
        }
    }

    public func stopLive() {
        showPositionTask?.cancel()
        showPositionTask = nil
        let engine = engine
        Task { await engine.stop() }
    }

    private func resumeLiveIfPending() {
        guard let fen = pendingLiveFEN else { return }
        pendingLiveFEN = nil
        showPosition(fen: fen)
    }

    // MARK: - Batch API

    /// Analyzes every ply in `fens` not already cached at `(gameId, plyIndex)`,
    /// saving each ply's ranked lines as it completes (so cancel/crash resumes
    /// for free). Stops live analysis first; live resumes afterwards.
    ///
    /// - parameter terminalMateWhiteWins: if the game's last ply is a mated
    ///   position, whether White delivered the mate - the position is not
    ///   searched, a synthetic terminal record is written instead.
    public func analyze(
        gameId: Int64,
        fens: [String],
        quality: AnalysisQuality,
        store: GameStore,
        terminalMateWhiteWins: Bool? = nil
    ) async throws {
        guard isStarted else { return }

        stopLive()
        isAnalyzing = true
        defer {
            isAnalyzing = false
            batchProgress = nil
            resumeLiveIfPending()
        }

        let analyzedPlies = try await store.analyzedPlyIndices(gameId: gameId)
        let total = fens.count
        batchProgress = (done: 0, total: total)

        for (plyIndex, fen) in fens.enumerated() {
            try Task.checkCancellation()

            if analyzedPlies.contains(plyIndex) {
                batchProgress = (done: plyIndex + 1, total: total)
                continue
            }

            let records: [AnalysisRecord]
            if plyIndex == fens.count - 1, let whiteWins = terminalMateWhiteWins {
                records = [
                    AnalysisRecord(
                        gameId: gameId,
                        plyIndex: plyIndex,
                        fen: fen,
                        depth: 0,
                        scoreCentipawns: nil,
                        mateIn: whiteWins ? 99 : -99,
                        principalVariation: "",
                        multiPVRank: 1
                    )
                ]
            } else {
                records = try await searchPly(gameId: gameId, plyIndex: plyIndex, fen: fen, quality: quality)
            }

            do {
                try await store.saveAnalysis(records, gameId: gameId, plyIndex: plyIndex)
            } catch {
                throw error
            }
            batchProgress = (done: plyIndex + 1, total: total)
        }
    }

    private func searchPly(
        gameId: Int64,
        plyIndex: Int,
        fen: String,
        quality: AnalysisQuality
    ) async throws -> [AnalysisRecord] {
        let infos = try await searchOneShot(fen: fen, movetimeMilliseconds: quality.movetimeMilliseconds)
        return infos.map { info in
            AnalysisRecord(
                gameId: gameId,
                plyIndex: plyIndex,
                fen: fen,
                depth: info.depth ?? 0,
                scoreCentipawns: EngineScoreNormalizer.whitePerspectiveScore(info.scoreCentipawns, fen: fen),
                mateIn: EngineScoreNormalizer.whitePerspectiveMate(info.mateIn, fen: fen),
                principalVariation: info.principalVariation.joined(separator: " "),
                multiPVRank: info.multiPVRank ?? 1
            )
        }
    }

    /// The shared one-shot batch-search core: set position, search for a
    /// fixed movetime, await the terminating bestmove, return the ranked
    /// MultiPV infos (side-to-move perspective, un-normalized). Used by
    /// `searchPly` (game analysis) and `coachEvaluate` (the coach's engine
    /// tool) alike - both are sequential one-shot searches, safe by
    /// construction per `AnalysisEngine.setPosition`'s generation-counter
    /// fix (M2).
    func searchOneShot(fen: String, movetimeMilliseconds: Int) async throws -> [AnalysisEngine.EngineInfo] {
        batchCollector = BatchCollector()
        let generation = await engine.setPosition(fen: fen)
        batchGeneration = generation
        await engine.go(movetimeMilliseconds: movetimeMilliseconds)

        do {
            try await awaitBatchSearch()
        } catch {
            batchCollector = nil
            batchGeneration = nil
            throw error
        }

        let infos = batchCollector?.rankedInfos ?? []
        batchCollector = nil
        batchGeneration = nil
        return infos
    }

    /// Waits for the current batch search's terminating bestmove. If the
    /// enclosing task is cancelled, stops the engine and lets that
    /// terminating bestmove resume this continuation before rethrowing.
    private func awaitBatchSearch() async throws {
        let engine = engine
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.batchContinuation = continuation
            }
        } onCancel: {
            Task { await engine.stop() }
        }
        try Task.checkCancellation()
    }

    // MARK: - EngineToolExecutor (the coach's `evaluate` tool, Layer 3)

    /// The tool-loop core (fact 20's step 2): validate the args by ChessCore
    /// replay first (fact 10 - small models mangle tool arguments routinely,
    /// so the engine must never see garbage), search the replay's resulting
    /// FEN, normalize white-perspective, resume any pending live analysis.
    /// Refuses while a batch analysis is running - narration only ever
    /// triggers on fully-analyzed games, so this is belt-and-braces.
    public func coachEvaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
        guard isStarted else {
            throw EngineToolArgumentError("engine is not running")
        }
        guard ChessGame.isValidFEN(fen) else {
            throw EngineToolArgumentError("'\(fen)' is not a valid FEN")
        }
        let resultingFEN: String
        if movesUCI.isEmpty {
            resultingFEN = fen
        } else {
            let replay = ChessGame.replayLine(fromUCI: movesUCI, startingFEN: fen)
            guard replay.count == movesUCI.count else {
                throw EngineToolArgumentError("illegal move in \(movesUCI) from position \(fen)")
            }
            resultingFEN = replay.last!.resultingFEN
        }
        guard !isAnalyzing else {
            throw EngineToolArgumentError("a batch analysis is already running")
        }

        stopLive()
        defer { resumeLiveIfPending() }

        let infos = try await searchOneShot(fen: resultingFEN, movetimeMilliseconds: 500)
        guard let rank1 = infos.first(where: { ($0.multiPVRank ?? 1) == 1 }) ?? infos.first else {
            throw EngineToolArgumentError("engine returned no analysis for \(resultingFEN)")
        }
        let scoreCentipawns = EngineScoreNormalizer.whitePerspectiveScore(rank1.scoreCentipawns, fen: resultingFEN)
        let mateIn = EngineScoreNormalizer.whitePerspectiveMate(rank1.mateIn, fen: resultingFEN)
        return EngineToolResult(
            resultingFEN: resultingFEN,
            scoreCentipawnsWhitePerspective: scoreCentipawns,
            mateInWhitePerspective: mateIn,
            evalLabel: EvalLabel.format(scoreCentipawns: scoreCentipawns, mateIn: mateIn),
            principalVariationUCI: rank1.principalVariation,
            principalVariationSAN: ChessGame.sanLine(fromUCI: rank1.principalVariation, startingFEN: resultingFEN),
            depth: rank1.depth ?? 0
        )
    }
}

extension EngineService: EngineToolExecutor {
    public func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
        try await coachEvaluate(fen: fen, movesUCI: movesUCI)
    }
}

/// `EngineService` is `@MainActor`; every access to its mutable state
/// happens on that actor, and `coachEvaluate` is only ever invoked (from
/// `CoachNarrator`, off the main actor) via the async `EngineToolExecutor`
/// protocol, which hops back to the main actor for the call itself - the
/// same cross-actor pattern SwiftUI's `ObservableObject` classes already
/// rely on.
extension EngineService: @unchecked Sendable {}
