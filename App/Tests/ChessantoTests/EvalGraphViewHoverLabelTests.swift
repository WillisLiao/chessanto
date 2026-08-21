import Testing
@testable import Chessanto

/// P4.1: the eval-graph hover readout used to say "Ply N", which nobody
/// actually counts by. `hoverLabel` must speak in real move numbers instead,
/// matching `ReportText.moveNumberLabel`'s "N." / "N..." convention.
struct EvalGraphViewHoverLabelTests {
    @Test func startPlyNeverSaysPly() {
        let label = EvalGraphView.hoverLabel(ply: 0, winPercentForWhite: 50)
        #expect(!label.contains("Ply"))
        #expect(label == "Start · 50% for White")
    }

    @Test func startPlyUnanalyzedIsHandledGracefully() {
        let label = EvalGraphView.hoverLabel(ply: 0, winPercentForWhite: nil)
        #expect(!label.contains("Ply"))
        #expect(label.contains("not analyzed"))
    }

    @Test func whiteMovePlyUsesDotConvention() {
        // Ply 1 is White's first move: move number 1.
        let label = EvalGraphView.hoverLabel(ply: 1, winPercentForWhite: 62)
        #expect(label == "1. · 62% for White")
    }

    @Test func blackMovePlyUsesEllipsisConvention() {
        // Ply 2 is Black's first move: move number 1...
        let label = EvalGraphView.hoverLabel(ply: 2, winPercentForWhite: 58)
        #expect(label == "1... · 58% for White")
    }

    @Test func laterWhiteMovePlyComputesTheCorrectMoveNumber() {
        // Ply 7 is White's 4th move.
        let label = EvalGraphView.hoverLabel(ply: 7, winPercentForWhite: 40)
        #expect(label == "4. · 40% for White")
    }

    @Test func unanalyzedPlySaysNotAnalyzedWithoutTheWordPly() {
        let label = EvalGraphView.hoverLabel(ply: 5, winPercentForWhite: nil)
        #expect(!label.contains("Ply"))
        #expect(label.contains("not analyzed"))
        #expect(label.hasPrefix("3."))
    }
}
