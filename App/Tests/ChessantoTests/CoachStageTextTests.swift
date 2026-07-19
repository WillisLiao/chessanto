import AnalysisKit
import Testing
@testable import Chessanto

struct CoachStageTextTests {
    @Test
    func usesAFocusedHeadlineForEachInstructionalClassification() {
        #expect(CoachStageText.headline(for: .inaccuracy) == "A quieter move kept the edge.")
        #expect(CoachStageText.headline(for: .mistake) == "This is where the position turned.")
        #expect(CoachStageText.headline(for: .blunder) == "This move changed the game.")
        #expect(CoachStageText.headline(for: .missedWin) == "The win was here.")
    }

    @Test
    func keepsShortExplanationsIntact() {
        let text = "The knight belongs on c3 because it controls d5."

        #expect(CoachStageText.condensed(text) == text)
    }

    @Test
    func boundsLongExplanationsWithoutBreakingTheLastWord() {
        let text = String(repeating: "This move gives the center away and leaves the king exposed. ", count: 10)

        let result = CoachStageText.condensed(text, maxCharacters: 100)

        #expect(result.count <= 100)
        #expect(result.hasSuffix("…") || result.hasSuffix("."))
    }
}
