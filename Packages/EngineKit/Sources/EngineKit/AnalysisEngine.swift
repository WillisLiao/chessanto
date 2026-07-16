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
    }

    public enum EngineUpdate: Sendable {
        case info(EngineInfo)
        case bestMove(generation: Int, move: String)
    }

    private let engine: Engine
    private var generation = 0
    private let updatesContinuation: AsyncStream<EngineUpdate>.Continuation
    public nonisolated let updates: AsyncStream<EngineUpdate>
    private var listenTask: Task<Void, Never>?

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
                let gen = await self.generation
                switch response {
                case let .info(info):
                    updatesContinuation.yield(
                        .info(
                            EngineInfo(
                                generation: gen,
                                depth: info.depth,
                                scoreCentipawns: info.score?.cp.map(Int.init),
                                mateIn: info.score?.mate,
                                principalVariation: info.pv ?? []
                            )
                        )
                    )
                case let .bestmove(move, _):
                    updatesContinuation.yield(.bestMove(generation: gen, move: move))
                default:
                    break
                }
            }
        }
    }

    /// Stops any current search, sets a new position, and bumps the
    /// generation counter. Callers should tag any subsequent `go` with the
    /// returned generation and drop `EngineUpdate`s from earlier generations.
    @discardableResult
    public func setPosition(fen: String, moves: [String] = []) async -> Int {
        generation += 1
        await engine.send(command: .stop)
        await engine.send(command: .position(.fen(fen), moves: moves.isEmpty ? nil : moves))
        return generation
    }

    public func goInfinite() async {
        await engine.send(command: .go(infinite: true))
    }

    public func go(depth: Int) async {
        await engine.send(command: .go(depth: depth))
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
