import Testing
@testable import Chessanto

@Suite("Key moment interaction intent")
struct KeyMomentInteractionIntentTests {
    @Test("selecting a key moment never starts line playback")
    func selectionDoesNotPlay() {
        #expect(
            KeyMomentInteractionIntent.selectOnly
                .startsBetterLinePreview == false
        )
    }

    @Test("the explicit better-line action starts playback")
    func explicitActionPlays() {
        #expect(
            KeyMomentInteractionIntent.playBetterLine
                .startsBetterLinePreview
        )
    }
}
