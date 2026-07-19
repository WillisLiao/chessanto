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
}
