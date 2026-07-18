import Testing
@testable import Chessanto

struct GameRowMetadataTests {
    @Test
    func preservesIncrementAndSpeedCategory() {
        #expect(GameRowMetadata.formattedTimeControl("180+2") == "3+2 · Blitz")
        #expect(GameRowMetadata.formattedTimeControl("600+5") == "10+5 · Rapid")
    }

    @Test
    func formatsPlainAndNonstandardControls() {
        #expect(GameRowMetadata.formattedTimeControl("180") == "3 min · Blitz")
        #expect(GameRowMetadata.formattedTimeControl("60+1") == "60+1 sec")
        #expect(GameRowMetadata.formattedTimeControl("1/259200") == "1/259200")
        #expect(GameRowMetadata.formattedTimeControl(nil) == nil)
    }
}
