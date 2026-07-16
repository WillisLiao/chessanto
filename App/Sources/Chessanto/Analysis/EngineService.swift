import Foundation
import EngineKit
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
        batchCollector = BatchCollector()
        let generation = await engine.setPosition(fen: fen)
        batchGeneration = generation
        await engine.go(movetimeMilliseconds: quality.movetimeMilliseconds)

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
}
