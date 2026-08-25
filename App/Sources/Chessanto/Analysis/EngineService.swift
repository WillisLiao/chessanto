import AnalysisKit
import ChessCore
import CoachKit
import EngineKit
import Foundation
import Persistence

/// One bounded search's budget: search to `depth`, spending no more than
/// `movetimeCeilingMilliseconds` on it.
///
/// A depth of 0 means "no depth limit", which is how the interactive
/// searches (the coach's `evaluate` tool, practice-move grading) express a
/// pure movetime budget - those are latency-bound, not reproducibility-bound.
public struct SearchBudget: Sendable, Equatable {
    public let depth: Int
    public let movetimeCeilingMilliseconds: Int

    public init(depth: Int, movetimeCeilingMilliseconds: Int) {
        self.depth = depth
        self.movetimeCeilingMilliseconds = movetimeCeilingMilliseconds
    }

    /// A pure movetime budget, for interactive searches where a bounded
    /// wait matters more than a reproducible depth.
    public static func movetime(_ milliseconds: Int) -> SearchBudget {
        SearchBudget(depth: 0, movetimeCeilingMilliseconds: milliseconds)
    }
}

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

    /// The search depth every position in a batch is analyzed to.
    ///
    /// Game analysis is budgeted by depth, not by movetime. The classifier
    /// resolves a 9-point mover win-probability drop from an 11-point one,
    /// and a fixed-movetime search does not hold its evaluation steady to
    /// anywhere near that precision: the reached depth varies with machine
    /// load, so the same game re-analyzed produces different
    /// classifications, different key moments, and a churning practice
    /// queue.
    ///
    /// These numbers are measured rather than chosen. A 50-position game at
    /// depth 18 with a 4-second ceiling reached 18 on only 14% of its
    /// positions, the rest cut off between 14 and 17 - reintroducing exactly
    /// the machine-dependent spread the scheme exists to remove. The depth
    /// has to be one the search reaches comfortably, with the ceiling as a
    /// rare backstop. MultiPV is 3, so each of these costs roughly three
    /// single-line searches.
    ///
    /// Expect the depth actually reached to be this or one less: Stockfish
    /// under MultiPV sometimes terminates having last reported the previous
    /// iteration, which `engine-smoke` pins down. That is why the UI reports
    /// the depth stored rather than the depth requested.
    var depth: Int {
        switch self {
        case .fast: return 12
        case .standard: return 16
        case .deep: return 20
        }
    }

    /// The wall-clock ceiling on any single position's search, so one
    /// pathological position cannot stall a whole-game batch.
    ///
    /// Deliberately generous relative to the depth above: if the ceiling
    /// binds routinely then the stored depth is really a function of how
    /// busy the machine was, and reproducibility is lost. It should fire
    /// for the occasional tactical thicket, not for ordinary positions.
    var movetimeCeilingMilliseconds: Int {
        switch self {
        case .fast: return 5000
        case .standard: return 20000
        case .deep: return 60000
        }
    }

    var searchBudget: SearchBudget {
        SearchBudget(depth: depth, movetimeCeilingMilliseconds: movetimeCeilingMilliseconds)
    }

    var provenance: AnalysisQualityProvenance {
        switch self {
        case .fast: return .fast
        case .standard: return .standard
        case .deep: return .deep
        }
    }
}

/// The app's single owner of the in-process Stockfish engine (only one
/// `Engine.start()` may exist per process - see EngineKit's AnalysisEngine
/// docs). Live infinite analysis while scrubbing and batch game analysis
/// share this one engine and are mutually exclusive.
@MainActor
public final class EngineService: ObservableObject {
    private static let engineIdentifier =
        "Stockfish 17 via chesskit-engine 0.7.0"

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

    /// The one bounded search currently in flight, if any. Routing dispatches
    /// to it while it exists; `nil` means no batch/one-shot search is
    /// running and updates route to the live-analysis path instead.
    private var activeSearch: BoundedSearchSession?

    /// FIFO chokepoint for `coachEvaluate` (M7 fact 3): `searchOneShot`'s
    /// `activeSearch` is a single field, so two interleaved `coachEvaluate`
    /// calls (a narration tool call and a chat tool call, both legal once
    /// chat exists) would clobber each other across suspension points. Holds
    /// a task that completes only once the *previous* call's actual engine
    /// work (not just its own wait) has finished, so each call truly waits
    /// its turn rather than racing on a chain of instantly-resolving
    /// placeholders. Shared by `coachEvaluate` and `evaluateTrainingPosition`
    /// so both kinds of one-shot search serialize against each other too.
    private var coachEvaluateTail: Task<Void, Never>?

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
        if let session = activeSearch {
            routeToActiveSearch(update, session: session)
        } else {
            routeLive(update)
        }
    }

    private func routeToActiveSearch(_ update: AnalysisEngine.EngineUpdate, session: BoundedSearchSession) {
        switch update {
        case .info(let info):
            session.record(info)
        case .bestMove(let gen, let move):
            session.complete(generation: gen, bestMove: move)
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
            liveGeneration = await engine.setPosition(
                fen: fen,
                chess960: Chess960.requiresChess960EngineMode(fen: fen)
            )
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
        terminalMateWhiteWins: Bool? = nil,
        progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil
    ) async throws {
        guard isStarted else { return }

        stopLive()
        isAnalyzing = true
        defer {
            isAnalyzing = false
            batchProgress = nil
            resumeLiveIfPending()
        }

        let analyzedPlies = try await store.analyzedPlyIndices(
            gameId: gameId,
            satisfying: quality.provenance,
            minimumDepth: quality.depth
        )
        let total = fens.count
        batchProgress = (done: 0, total: total)
        progress?(0, total)

        for (plyIndex, fen) in fens.enumerated() {
            try Task.checkCancellation()

            if analyzedPlies.contains(plyIndex) {
                batchProgress = (done: plyIndex + 1, total: total)
                progress?(plyIndex + 1, total)
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
                        multiPVRank: 1,
                        qualityPreset: quality.provenance,
                        analyzedAt: Date(),
                        engineIdentifier: Self.engineIdentifier
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
            progress?(plyIndex + 1, total)
        }
    }

    private func searchPly(
        gameId: Int64,
        plyIndex: Int,
        fen: String,
        quality: AnalysisQuality
    ) async throws -> [AnalysisRecord] {
        let infos = try await searchOneShot(fen: fen, budget: quality.searchBudget)
        return infos.map { info in
            AnalysisRecord(
                gameId: gameId,
                plyIndex: plyIndex,
                fen: fen,
                depth: info.depth ?? 0,
                scoreCentipawns: EngineScoreNormalizer.whitePerspectiveScore(info.scoreCentipawns, fen: fen),
                mateIn: EngineScoreNormalizer.whitePerspectiveMate(info.mateIn, fen: fen),
                principalVariation: info.principalVariation.joined(separator: " "),
                multiPVRank: info.multiPVRank ?? 1,
                qualityPreset: quality.provenance,
                analyzedAt: Date(),
                engineIdentifier: Self.engineIdentifier
            )
        }
    }

    /// The shared one-shot batch-search core: set position, search for a
    /// fixed movetime, await the terminating bestmove, return the ranked
    /// MultiPV infos (side-to-move perspective, un-normalized). Used by
    /// `searchPly` (game analysis), `coachEvaluate` (the coach's engine
    /// tool), and `evaluateTrainingPosition` alike - all are sequential
    /// one-shot searches, safe by construction per `AnalysisEngine
    /// .setPosition`'s generation-counter fix (M2) and this method's own
    /// `BoundedSearchSession` (installed before `go` is ever sent, so F1's
    /// hang - a terminating bestmove arriving before anything was waiting
    /// for it - cannot happen: the session latches completion regardless of
    /// arrival order).
    ///
    /// Every search carries a deadline derived from its movetime ceiling:
    /// `deadlineMultiplier` absorbs a loaded machine, `deadlineFloorMilliseconds`
    /// absorbs process scheduling. The deadline is a backstop against the
    /// engine never terminating at all - the search's own ceiling is what
    /// normally bounds it. On timeout or cancellation the session is failed
    /// with a typed error, the engine is told to stop, and the active
    /// session is cleared so any later, now-irrelevant update is dropped by
    /// `route`.
    private static let deadlineMultiplier = 4
    private static let deadlineFloorMilliseconds = 3000

    func searchOneShot(fen: String, budget: SearchBudget) async throws -> [AnalysisEngine.EngineInfo] {
        let generation = await engine.setPosition(
            fen: fen,
            chess960: Chess960.requiresChess960EngineMode(fen: fen)
        )
        let session = BoundedSearchSession(generation: generation)
        activeSearch = session
        let engineRef = engine
        // A depth-limited search is bounded by `stop` at the ceiling rather
        // than by a combined UCI limit, because combining the two costs an
        // iteration (see `AnalysisEngine.go(depth:)`'s note). Stockfish
        // answers `stop` with a normal `bestmove`, so a ceiling hit resolves
        // the session with the deepest lines it did finish instead of
        // throwing away the position's analysis entirely.
        let ceilingTask: Task<Void, Never>?
        if budget.depth > 0 {
            await engine.go(depth: budget.depth)
            ceilingTask = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(budget.movetimeCeilingMilliseconds) * 1_000_000
                )
                guard !Task.isCancelled else { return }
                await engineRef.stop()
            }
        } else {
            await engine.go(movetimeMilliseconds: budget.movetimeCeilingMilliseconds)
            ceilingTask = nil
        }

        let deadlineMilliseconds =
            budget.movetimeCeilingMilliseconds * Self.deadlineMultiplier
            + Self.deadlineFloorMilliseconds
        let deadlineTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(deadlineMilliseconds) * 1_000_000)
            session.fail(.timedOut(milliseconds: deadlineMilliseconds))
        }

        do {
            let infos = try await withTaskCancellationHandler {
                try await session.value()
            } onCancel: {
                Task { @MainActor in session.fail(.cancelled) }
            }
            ceilingTask?.cancel()
            deadlineTask.cancel()
            clearActiveSearch(session)
            return infos
        } catch {
            ceilingTask?.cancel()
            deadlineTask.cancel()
            clearActiveSearch(session)
            Task { await engineRef.stop() }
            throw error
        }
    }

    private func clearActiveSearch(_ session: BoundedSearchSession) {
        if activeSearch === session {
            activeSearch = nil
        }
    }

    /// Runs a one-shot search and normalizes its rank-one line to
    /// white-perspective, shared by `coachEvaluate` and
    /// `evaluateTrainingPosition`.
    private func searchRankOne(
        resultingFEN: String,
        budget: SearchBudget
    ) async throws -> (info: AnalysisEngine.EngineInfo, scoreCentipawns: Int?, mateIn: Int?) {
        let infos = try await searchOneShot(fen: resultingFEN, budget: budget)
        guard let rank1 = infos.first(where: { ($0.multiPVRank ?? 1) == 1 }) ?? infos.first else {
            throw EngineToolArgumentError("engine returned no analysis for \(resultingFEN)")
        }
        let scoreCentipawns = EngineScoreNormalizer.whitePerspectiveScore(rank1.scoreCentipawns, fen: resultingFEN)
        let mateIn = EngineScoreNormalizer.whitePerspectiveMate(rank1.mateIn, fen: resultingFEN)
        return (rank1, scoreCentipawns, mateIn)
    }

    /// The coach's `evaluate` tool runs inside an LLM tool loop, so it is
    /// latency-sensitive, but a cited evaluation that disagrees with the
    /// stored analysis it sits beside reads as the coach contradicting the
    /// report. A depth limit close to `.standard` keeps the two comparable
    /// without an unbounded wait.
    private static let coachEvaluateBudget = SearchBudget(
        depth: 16,
        movetimeCeilingMilliseconds: 2500
    )

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

        return try await runOnFIFOTail {
            try await self.runCoachEvaluateSearch(resultingFEN: resultingFEN)
        }
    }

    /// Chains `work` onto `coachEvaluateTail` (M7's FIFO guarantee) and
    /// propagates the caller's cancellation into `work` (the F4 fix): the
    /// unstructured task backing the FIFO slot is cancelled explicitly,
    /// which - because `work` calls directly into `searchOneShot` rather
    /// than spawning its own further unstructured task - reaches
    /// `BoundedSearchSession` and resolves it with `.cancelled` instead of
    /// leaving it to run to completion unobserved. `coachEvaluateTail` is
    /// reassigned to a task that awaits the work task's outcome regardless
    /// of success, failure, or cancellation, so the FIFO always advances and
    /// can never wedge behind a call the caller gave up on.
    private func runOnFIFOTail<Result: Sendable>(
        _ work: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        let previousTail = coachEvaluateTail
        let workTask = Task<Result, Error> {
            await previousTail?.value
            try Task.checkCancellation()
            return try await work()
        }
        coachEvaluateTail = Task { _ = try? await workTask.value }

        return try await withTaskCancellationHandler {
            try await workTask.value
        } onCancel: {
            workTask.cancel()
        }
    }

    private func runCoachEvaluateSearch(resultingFEN: String) async throws -> EngineToolResult {
        stopLive()
        defer { resumeLiveIfPending() }

        let (rank1, scoreCentipawns, mateIn) = try await searchRankOne(
            resultingFEN: resultingFEN,
            budget: Self.coachEvaluateBudget
        )
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

    // MARK: - Training evaluation

    /// The training domain's engine boundary (fact 2's typed-score plan):
    /// validates the attempted move by `ChessCore` replay, then searches the
    /// resulting position. Deliberately does not route through
    /// `coachEvaluate` - the training domain should not be coupled to the
    /// Coach tool's `EngineToolResult` shape - but shares `coachEvaluateTail`
    /// so a narration/chat evaluation and a training evaluation still
    /// serialize against each other on the single shared engine.
    func evaluateTrainingPosition(_ request: TrainingPositionRequest) async throws -> WhitePerspectiveScore {
        guard isStarted else {
            throw EngineToolArgumentError("engine is not running")
        }
        guard ChessGame.isValidFEN(request.preMoveFEN) else {
            throw EngineToolArgumentError("'\(request.preMoveFEN)' is not a valid FEN")
        }
        let replay = ChessGame.replayLine(fromUCI: [request.attemptedMoveUCI], startingFEN: request.preMoveFEN)
        guard replay.count == 1 else {
            throw EngineToolArgumentError(
                "illegal move \(request.attemptedMoveUCI) from position \(request.preMoveFEN)"
            )
        }
        let resultingFEN = replay[0].resultingFEN
        guard !isAnalyzing else {
            throw EngineToolArgumentError("a batch analysis is already running")
        }

        let budget = Self.trainingBudget(referenceDepth: request.referenceDepth)
        return try await runOnFIFOTail {
            try await self.runTrainingEvaluationSearch(
                resultingFEN: resultingFEN,
                budget: budget
            )
        }
    }

    /// One ply shallower than the card's own stored search, floored so a
    /// card carrying a missing or nonsensical depth still gets a usable
    /// search rather than an instant one.
    private static func trainingBudget(referenceDepth: Int) -> SearchBudget {
        SearchBudget(
            depth: max(referenceDepth - 1, 12),
            movetimeCeilingMilliseconds: 6000
        )
    }

    private func runTrainingEvaluationSearch(
        resultingFEN: String,
        budget: SearchBudget
    ) async throws -> WhitePerspectiveScore {
        stopLive()
        defer { resumeLiveIfPending() }

        let (_, scoreCentipawns, mateIn) = try await searchRankOne(
            resultingFEN: resultingFEN,
            budget: budget
        )
        guard let score = WhitePerspectiveScore(scoreCentipawns: scoreCentipawns, mateIn: mateIn) else {
            throw EngineSearchError.noAnalysis
        }
        return score
    }

    // MARK: - Live game opponent move generation

    /// Generates an engine opponent reply for `fen` at the given `strength`.
    /// Sets Stockfish UCI `Skill Level` (0-20), runs a depth-bounded search
    /// with movetime ceiling, returns the engine's terminating best move in
    /// UCI format, and restores full `Skill Level` (20) upon completion.
    public func generateOpponentMove(
        in fen: String,
        strength: EngineStrength
    ) async throws -> String {
        guard isStarted else {
            throw EngineSearchError.engineUnavailable("engine is not running")
        }
        guard ChessGame.isValidFEN(fen) else {
            throw EngineToolArgumentError("'\(fen)' is not a valid FEN")
        }
        guard !isAnalyzing else {
            throw EngineToolArgumentError("a batch analysis is already running")
        }

        return try await runOnFIFOTail {
            try await self.runOpponentMoveSearch(fen: fen, strength: strength)
        }
    }

    private func runOpponentMoveSearch(
        fen: String,
        strength: EngineStrength
    ) async throws -> String {
        stopLive()
        defer {
            resumeLiveIfPending()
        }

        await engine.setOption(name: "Skill Level", value: "\(strength.skillLevel)")
        defer {
            let engineRef = engine
            Task {
                await engineRef.setOption(name: "Skill Level", value: "20")
            }
        }

        let generation = await engine.setPosition(fen: fen)
        let session = BoundedSearchSession(generation: generation)
        activeSearch = session
        let engineRef = engine

        let ceilingTask: Task<Void, Never>?
        if strength.depth > 0 {
            await engine.go(depth: strength.depth)
            ceilingTask = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(strength.movetimeCeilingMilliseconds) * 1_000_000
                )
                guard !Task.isCancelled else { return }
                await engineRef.stop()
            }
        } else {
            await engine.go(movetimeMilliseconds: strength.movetimeCeilingMilliseconds)
            ceilingTask = nil
        }

        let deadlineMilliseconds =
            strength.movetimeCeilingMilliseconds * Self.deadlineMultiplier
            + Self.deadlineFloorMilliseconds
        let deadlineTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(deadlineMilliseconds) * 1_000_000)
            session.fail(.timedOut(milliseconds: deadlineMilliseconds))
        }

        do {
            let move = try await withTaskCancellationHandler {
                try await session.bestMove()
            } onCancel: {
                Task { @MainActor in session.fail(.cancelled) }
            }
            ceilingTask?.cancel()
            deadlineTask.cancel()
            clearActiveSearch(session)
            return move
        } catch {
            ceilingTask?.cancel()
            deadlineTask.cancel()
            clearActiveSearch(session)
            Task { await engineRef.stop() }
            throw error
        }
    }
}

extension EngineService: EngineToolExecutor {
    public func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
        try await coachEvaluate(fen: fen, movesUCI: movesUCI)
    }
}

extension EngineService: EngineOpponent {
    public func generateMove(in fen: String, strength: EngineStrength) async throws -> String {
        try await generateOpponentMove(in: fen, strength: strength)
    }
}

/// `EngineService` is `@MainActor`; every access to its mutable state
/// happens on that actor, and `coachEvaluate` is only ever invoked (from
/// `CoachNarrator`, off the main actor) via the async `EngineToolExecutor`
/// protocol, which hops back to the main actor for the call itself - the
/// same cross-actor pattern SwiftUI's `ObservableObject` classes already
/// rely on.
extension EngineService: @unchecked Sendable {}
