import AnalysisKit
import ChessCore
import CoachKit
import EngineKit
import Foundation

/// A standalone `EngineToolExecutor` driving a real in-process Stockfish,
/// the same one-shot-search-plus-white-perspective-normalization shape as
/// the app's `EngineService.coachEvaluate` (this executable can't import
/// the App target, so the ~15 lines of normalization are duplicated rather
/// than shared - see `EngineScoreNormalizer` in the App target for the
/// canonical version). Owns the single consumer of `AnalysisEngine.updates`
/// (an `AsyncStream`, not a broadcast stream) for the whole process
/// lifetime, exactly like `engine-smoke`.
actor GroundingEngine: EngineToolExecutor {
    private let engine = AnalysisEngine()
    private var iterator: AsyncStream<AnalysisEngine.EngineUpdate>.AsyncIterator?

    func start(bigNetPath: String, smallNetPath: String) async {
        await engine.start(multipv: 3)
        await engine.setOption(name: "EvalFile", value: bigNetPath)
        await engine.setOption(name: "EvalFileSmall", value: smallNetPath)
        await engine.setOption(name: "Hash", value: "256")
        iterator = engine.updates.makeAsyncIterator()
    }

    func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult {
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

        let infos = await search(fen: resultingFEN, movetimeMilliseconds: 500)
        guard let rank1 = infos.first(where: { ($0.multiPVRank ?? 1) == 1 }) ?? infos.first else {
            throw EngineToolArgumentError("engine returned no analysis for \(resultingFEN)")
        }
        let cp = whitePerspective(rank1.scoreCentipawns, fen: resultingFEN)
        let mate = whitePerspective(rank1.mateIn, fen: resultingFEN)
        return EngineToolResult(
            resultingFEN: resultingFEN,
            scoreCentipawnsWhitePerspective: cp,
            mateInWhitePerspective: mate,
            evalLabel: EvalLabel.format(scoreCentipawns: cp, mateIn: mate),
            principalVariationUCI: rank1.principalVariation,
            principalVariationSAN: ChessGame.sanLine(fromUCI: rank1.principalVariation, startingFEN: resultingFEN),
            depth: rank1.depth ?? 0
        )
    }

    private func search(fen: String, movetimeMilliseconds: Int) async -> [AnalysisEngine.EngineInfo] {
        guard var localIterator = iterator else { return [] }
        let generation = await engine.setPosition(fen: fen)
        await engine.go(movetimeMilliseconds: movetimeMilliseconds)
        var infosByRank: [Int: AnalysisEngine.EngineInfo] = [:]
        defer { iterator = localIterator }
        while let update = await localIterator.next() {
            switch update {
            case .info(let info):
                guard info.generation == generation else { continue }
                infosByRank[info.multiPVRank ?? 1] = info
            case .bestMove(let gen, _):
                guard gen == generation else { continue }
                return infosByRank.keys.sorted().compactMap { infosByRank[$0] }
            }
        }
        return infosByRank.keys.sorted().compactMap { infosByRank[$0] }
    }

    private func isBlackToMove(fen: String) -> Bool {
        let fields = fen.split(separator: " ", maxSplits: 2)
        return fields.count > 1 && fields[1] == "b"
    }

    private func whitePerspective(_ value: Int?, fen: String) -> Int? {
        guard let value else { return nil }
        return isBlackToMove(fen: fen) ? -value : value
    }
}
