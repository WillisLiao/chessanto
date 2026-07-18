import ChessKitEngine
import Foundation

/// Thin wrapper around chesskit-engine's in-process Stockfish.
///
/// chesskit-engine's `Engine.start(coreCount:)` defaults to `min(1, cores - 1)`,
/// which evaluates to 1 on every machine with 2+ cores - Stockfish would always
/// run single-threaded unless we pass an explicit core count ourselves.
public actor AnalysisEngine {
    public struct EngineInfo: Sendable {
        public let generation: Int
        public let depth: Int?
        public let scoreCentipawns: Int?
        public let mateIn: Int?
        public let principalVariation: [String]
        /// 1-based MultiPV rank (1 = best line). Stockfish omits it when
        /// MultiPV is 1, so treat `nil` as rank 1.
        public let multiPVRank: Int?

        public init(
            generation: Int,
            depth: Int?,
            scoreCentipawns: Int?,
            mateIn: Int?,
            principalVariation: [String],
            multiPVRank: Int?
        ) {
            self.generation = generation
            self.depth = depth
            self.scoreCentipawns = scoreCentipawns
            self.mateIn = mateIn
            self.principalVariation = principalVariation
            self.multiPVRank = multiPVRank
        }
    }

    public enum EngineUpdate: Sendable {
        case info(EngineInfo)
        case bestMove(generation: Int, move: String)
    }

    private let engine: Engine
    private var generation = 0
    private var isSearching = false
    /// The generation the *current search* started under, `0` when no
    /// search is active. Stamped onto updates instead of `generation`
    /// because `generation` reflects delivery time, and a trailing update
    /// from a just-stopped search can otherwise be delivered after
    /// `setPosition` has already bumped `generation` for the next search.
    private var searchGeneration = 0
    private let updatesContinuation: AsyncStream<EngineUpdate>.Continuation
    public nonisolated let updates: AsyncStream<EngineUpdate>
    private var listenTask: Task<Void, Never>?
    /// Continuations waiting on the engine's next `readyok`. chesskit-engine
    /// dispatches each raw response through its own unstructured `Task`, so
    /// responses are not guaranteed to reach `responseStream` in the order
    /// Stockfish emitted them - a stray `info` from a just-stopped search can
    /// still be pending when the next search's `go` is sent. Stockfish
    /// processes `isready` only after every previously queued command has
    /// been fully handled, so waiting for `readyok` drains that backlog
    /// before the next generation is used.
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    public init() {
        engine = Engine(type: .stockfish)
        var continuation: AsyncStream<EngineUpdate>.Continuation!
        updates = AsyncStream { continuation = $0 }
        updatesContinuation = continuation
    }

    /// Starts the engine and begins forwarding responses to `updates`.
    /// Must complete before `setPosition`/`go` are called.
    public func start(multipv: Int = 3) async {
        let cores = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)
        await engine.start(coreCount: cores, multipv: multipv)

        while await !engine.isRunning {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        listenTask = Task { [weak self, engine, updatesContinuation] in
            guard let stream = await engine.responseStream else { return }
            for await response in stream {
                guard let self else { return }
                let gen = await self.searchGeneration
                switch response {
                case let .info(info):
                    updatesContinuation.yield(
                        .info(
                            EngineInfo(
                                generation: gen,
                                depth: info.depth,
                                scoreCentipawns: info.score?.cp.map(Int.init),
                                mateIn: info.score?.mate,
                                principalVariation: info.pv ?? [],
                                multiPVRank: info.multipv
                            )
                        )
                    )
                case let .bestmove(move, _):
                    await self.markSearchEnded()
                    updatesContinuation.yield(.bestMove(generation: gen, move: move))
                case .readyok:
                    await self.resumeReady()
                default:
                    break
                }
            }
        }
    }

    private func markSearchEnded() {
        isSearching = false
        searchGeneration = 0
    }

    private func resumeReady() {
        let continuations = readyContinuations
        readyContinuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }

    /// Sends `isready` and suspends until the matching `readyok` is
    /// observed, guaranteeing every command and response queued before this
    /// call has been fully processed by the engine.
    private func waitUntilReady() async {
        await engine.send(command: .isready)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readyContinuations.append(continuation)
        }
    }

    /// Stops any current search, sets a new position, and bumps the
    /// generation counter. Callers should tag any subsequent `go` with the
    /// returned generation and drop `EngineUpdate`s from earlier generations.
    ///
    /// If a search is in flight, waits up to ~300ms (10ms polls, capped at
    /// 300 iterations) for its terminating `bestmove` before bumping the
    /// generation. Stamping updates with `searchGeneration` (the generation
    /// the search actually started under, read once per delivered update)
    /// rather than `generation` (which reflects delivery time) closes most
    /// of the cross-search misattribution window, but chesskit-engine
    /// dispatches each response through its own unstructured `Task`, so a
    /// trailing response can still reach `responseStream` after this method
    /// has already returned. `waitUntilReady()` closes the remainder by
    /// waiting for `readyok`, which Stockfish only sends after every
    /// previously queued command and its output have been fully processed.
    @discardableResult
    public func setPosition(fen: String, moves: [String] = []) async -> Int {
        if isSearching {
            await engine.send(command: .stop)
            var waited = 0
            while isSearching && waited < 300 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                waited += 10
            }
        }
        // Unconditional, not gated on the `isSearching` branch above: the
        // reproduced race had `isSearching` already false by the time this
        // method was entered (the prior search's bestmove, which resets it,
        // had already been observed by the caller), yet stray trailing
        // content from that same just-finished search still contaminated
        // the next one. Gating this on `isSearching` would reopen exactly
        // the race it exists to close.
        await waitUntilReady()
        // `readyok`'s own delivery races the same unstructured-Task dispatch
        // as everything else, so observing it does not, by itself, guarantee
        // every earlier response has already reached `responseStream`. This
        // settle window closed the residual race in repeated live testing
        // (`engine-smoke`'s generation-isolation assertion); it is a
        // mitigation, not a proof.
        try? await Task.sleep(nanoseconds: 30_000_000)
        generation += 1
        await engine.send(command: .position(.fen(fen), moves: moves.isEmpty ? nil : moves))
        return generation
    }

    /// Sends a UCI `setoption` (e.g. "Hash", "EvalFile"). Only call between
    /// searches; engines ignore option changes while searching.
    public func setOption(name: String, value: String) async {
        await engine.send(command: .setoption(id: name, value: value))
    }

    public func goInfinite() async {
        isSearching = true
        searchGeneration = generation
        await engine.send(command: .go(infinite: true))
    }

    public func go(depth: Int) async {
        isSearching = true
        searchGeneration = generation
        await engine.send(command: .go(depth: depth))
    }

    public func go(movetimeMilliseconds: Int) async {
        isSearching = true
        searchGeneration = generation
        await engine.send(command: .go(movetime: movetimeMilliseconds))
    }

    public func stop() async {
        await engine.send(command: .stop)
    }

    public func shutdown() async {
        listenTask?.cancel()
        await engine.stop()
        updatesContinuation.finish()
    }
}
