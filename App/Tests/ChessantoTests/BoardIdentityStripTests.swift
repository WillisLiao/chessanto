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

    @Test func testAccuracySummaryFormatterWithoutUser() {
        let white = AccuracySummaryFormatter.format(side: "White", accuracy: 93.8, isUser: false)
        #expect(white == "White 93.8%")

        let black = AccuracySummaryFormatter.format(side: "Black", accuracy: 90.8, isUser: false)
        #expect(black == "Black 90.8%")
    }

    @Test func testAccuracySummaryFormatterWithUser() {
        let white = AccuracySummaryFormatter.format(side: "White", accuracy: 93.8, isUser: true)
        #expect(white == "White (You) 93.8%")

        let black = AccuracySummaryFormatter.format(side: "Black", accuracy: 90.8, isUser: true)
        #expect(black == "Black (You) 90.8%")
    }

    @Test func testIsUserMatchesCaseInsensitively() {
        #expect(BoardIdentityStrip.isUser(name: "WillisLiao", username: "willisliao"))
        #expect(BoardIdentityStrip.isUser(name: "willisliao", username: "WillisLiao"))
        #expect(!BoardIdentityStrip.isUser(name: "Alice", username: "Bob"))
        #expect(!BoardIdentityStrip.isUser(name: "Alice", username: ""))
        #expect(!BoardIdentityStrip.isUser(name: "Alice", username: "   "))
    }
}
