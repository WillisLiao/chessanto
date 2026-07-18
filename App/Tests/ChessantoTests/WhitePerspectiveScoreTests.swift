import Testing
import ChessCore
@testable import Chessanto

struct WhitePerspectiveScoreTests {
    @Test func mateWinsOverCentipawnsWhenBothArePresent() {
        let score = WhitePerspectiveScore(scoreCentipawns: 50, mateIn: 3)
        #expect(score == .mate(3))
    }

    @Test func absentValuesProduceNoScore() {
        let score = WhitePerspectiveScore(scoreCentipawns: nil, mateIn: nil)
        #expect(score == nil)
    }

    @Test func blackToMoveOrientationNegatesBothForms() {
        #expect(WhitePerspectiveScore.centipawns(50).oriented(forMover: .black) == .centipawns(-50))
        #expect(WhitePerspectiveScore.mate(3).oriented(forMover: .black) == .mate(-3))
        #expect(WhitePerspectiveScore.centipawns(50).oriented(forMover: .white) == .centipawns(50))
        #expect(WhitePerspectiveScore.mate(3).oriented(forMover: .white) == .mate(3))
    }
}
