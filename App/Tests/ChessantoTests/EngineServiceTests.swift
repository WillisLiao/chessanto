import Testing
import EngineKit
@testable import Chessanto

struct LiveGenerationFilterTests {
    @Test func onlyCurrentGenerationPasses() {
        let filter = LiveGenerationFilter(liveGeneration: 3)
        #expect(filter.isCurrent(3))
        #expect(!filter.isCurrent(2))
        #expect(!filter.isCurrent(4))
    }
}

struct BatchCollectorTests {
    private func info(rank: Int?, cp: Int) -> AnalysisEngine.EngineInfo {
        AnalysisEngine.EngineInfo(
            generation: 0, depth: 10, scoreCentipawns: cp, mateIn: nil,
            principalVariation: [], multiPVRank: rank
        )
    }

    @Test func nilRankIsTreatedAsRankOne() {
        var collector = BatchCollector()
        collector.record(info(rank: nil, cp: 10))
        #expect(collector.rankedInfos.count == 1)
        #expect(collector.rankedInfos[0].scoreCentipawns == 10)
    }

    @Test func keepsLatestInfoPerRankOrderedByRank() {
        var collector = BatchCollector()
        collector.record(info(rank: 2, cp: 5))
        collector.record(info(rank: 1, cp: 20))
        collector.record(info(rank: 1, cp: 25)) // supersedes the first rank-1 info
        collector.record(info(rank: 3, cp: -5))

        let ranked = collector.rankedInfos
        #expect(ranked.map(\.scoreCentipawns) == [25, 5, -5])
    }
}

struct EngineScoreNormalizerTests {
    @Test func whiteToMoveScoresAreUnchanged() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        #expect(EngineScoreNormalizer.whitePerspectiveScore(50, fen: fen) == 50)
        #expect(EngineScoreNormalizer.whitePerspectiveMate(2, fen: fen) == 2)
    }

    @Test func blackToMoveScoresAreNegated() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
        #expect(EngineScoreNormalizer.whitePerspectiveScore(50, fen: fen) == -50)
        #expect(EngineScoreNormalizer.whitePerspectiveMate(2, fen: fen) == -2)
    }

    @Test func nilScoresStayNil() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
        #expect(EngineScoreNormalizer.whitePerspectiveScore(nil, fen: fen) == nil)
        #expect(EngineScoreNormalizer.whitePerspectiveMate(nil, fen: fen) == nil)
    }
}
