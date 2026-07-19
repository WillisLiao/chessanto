import Testing
@testable import Chessanto

struct BoardIdentityStripTests {
    @Test func testBottomStripIsWhiteWhenNotFlipped() {
        let strips = BoardIdentityStrip.strips(
            whiteName: "Alice",
            blackName: "Bob",
            whiteRating: 1500,
            blackRating: 1600,
            flipped: false,
            username: ""
        )
        #expect(strips.bottom.name == "Alice")
        #expect(strips.top.name == "Bob")
    }

    @Test func testBottomStripIsBlackWhenFlipped() {
        let strips = BoardIdentityStrip.strips(
            whiteName: "Alice",
            blackName: "Bob",
            whiteRating: 1500,
            blackRating: 1600,
            flipped: true,
            username: ""
        )
        #expect(strips.bottom.name == "Bob")
        #expect(strips.top.name == "Alice")
    }

    @Test func testMarksConfiguredUserCaseInsensitively() {
        let strips = BoardIdentityStrip.strips(
            whiteName: "adamzainuri",
            blackName: "WillisLiao",
            whiteRating: nil,
            blackRating: nil,
            flipped: false,
            username: "willisliao"
        )
        #expect(strips.top.isUser == true)
        #expect(strips.bottom.isUser == false)
    }

    @Test func testNoUserMarkWhenUsernameIsEmpty() {
        let strips = BoardIdentityStrip.strips(
            whiteName: "Alice",
            blackName: "Bob",
            whiteRating: nil,
            blackRating: nil,
            flipped: false,
            username: ""
        )
        #expect(strips.top.isUser == false)
        #expect(strips.bottom.isUser == false)
    }

    @Test func testOmitsRatingWhenAbsent() {
        let strips = BoardIdentityStrip.strips(
            whiteName: "Alice",
            blackName: "Bob",
            whiteRating: nil,
            blackRating: 1600,
            flipped: false,
            username: ""
        )
        #expect(strips.bottom.rating == nil)
        #expect(strips.top.rating == 1600)
    }
}
