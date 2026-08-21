import AnalysisKit
import Testing
@testable import Chessanto

struct ChessGlossaryTests {
    @Test func testGlossesEveryTermThemeGenerationCanProduce() {
        #expect(ChessGlossary.gloss(for: "Material left en prise") != nil)
        #expect(ChessGlossary.gloss(for: "Missed forced mate") != nil)
        #expect(ChessGlossary.gloss(for: "Allowed forced mate") != nil)
    }

    @Test func testGlossesEveryMoveClassification() {
        for classification in MoveClassification.allCases {
            #expect(!ChessGlossary.gloss(for: classification).isEmpty)
        }
    }

    @Test func testGlossesCastlingNotation() {
        #expect(ChessGlossary.gloss(for: "O-O") != nil)
        #expect(ChessGlossary.gloss(for: "O-O-O") != nil)
        #expect(ChessGlossary.gloss(for: "O-O") != ChessGlossary.gloss(for: "O-O-O"))
    }

    @Test func testUnknownTermReturnsNil() {
        #expect(ChessGlossary.gloss(for: "Zwischenzug") == nil)
    }

    @Test func matchReturnsNilForProseWithNoKnownTerm() {
        #expect(ChessGlossary.match(in: "White is better now.") == nil)
    }

    @Test func matchReturnsTheTermAndGlossFromARealRenderedSentence() {
        let match = ChessGlossary.match(in: "This also left the bishop on c5 hanging: Bxc5 winning material.")
        #expect(match?.term == "hanging")
        #expect(match?.gloss == "left where the opponent can capture it for free")
    }

    @Test func matchPrefersTheLongerCastlingTokenOverItsSubstring() {
        let match = ChessGlossary.match(in: "0-0-0 castles the king queenside: O-O-O.")
        #expect(match?.term == "O-O-O")
    }
}
