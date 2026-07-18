import AnalysisKit
import Testing
@testable import Chessanto

struct MoveClassificationStyleTests {
    @Test func compactMarksFollowFamiliarChessReviewNotation() {
        #expect(MoveClassification.best.compactMark == .systemImage("star.fill"))
        #expect(MoveClassification.excellent.compactMark == .systemImage("hand.thumbsup.fill"))
        #expect(MoveClassification.good.compactMark == .systemImage("checkmark"))
        #expect(MoveClassification.inaccuracy.compactMark == .text("?!"))
        #expect(MoveClassification.mistake.compactMark == .text("?"))
        #expect(MoveClassification.blunder.compactMark == .text("??"))
        #expect(MoveClassification.brilliant.compactMark == .text("!!"))
        #expect(MoveClassification.missedWin.compactMark == .systemImage("xmark"))
    }
}
