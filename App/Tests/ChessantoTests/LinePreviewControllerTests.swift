import Testing
@testable import Chessanto

@MainActor
struct LinePreviewControllerTests {
    private let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    @Test
    func startsAtTheSourcePositionWithoutALastMove() throws {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5"]
        )

        #expect(controller.stepIndex == 0)
        #expect(controller.stepCount == 3)
        #expect(controller.current.lastMove == nil)
        #expect(controller.current.san == nil)
        #expect(controller.canStepForward)
        #expect(!controller.canStepBackward)
    }

    @Test
    func steppingTracksThePositionMoveAndNotation() throws {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5"]
        )

        controller.stepForward()

        #expect(controller.stepIndex == 1)
        #expect(controller.current.san == "e4")
        #expect(controller.current.lastMove?.from.algebraic == "e2")
        #expect(controller.current.lastMove?.to.algebraic == "e4")

        controller.stepForward()

        #expect(controller.stepIndex == 2)
        #expect(controller.current.san == "e5")
        #expect(!controller.canStepForward)

        controller.stepBackward()

        #expect(controller.stepIndex == 1)
        #expect(controller.current.san == "e4")
    }

    @Test
    func anIllegalMoveTruncatesThePreviewWithoutCrashing() {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5", "e2e3", "g1f3"]
        )

        #expect(controller.stepCount == 3)
        controller.jumpToEnd()
        #expect(controller.current.san == "e5")
    }

    @Test
    func automaticPlaybackAdvancesAndStopsAtTheEnd() {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5"]
        )

        controller.play()
        #expect(controller.isPlaying)

        controller.autoplayTick()
        #expect(controller.stepIndex == 1)
        #expect(controller.isPlaying)

        controller.autoplayTick()
        #expect(controller.stepIndex == 2)
        #expect(!controller.isPlaying)
    }

    @Test
    func replayReturnsToTheStartAndBeginsPlaying() {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5"]
        )
        controller.jumpToEnd()

        controller.replay()

        #expect(controller.stepIndex == 0)
        #expect(controller.isPlaying)
    }

    @Test
    func manualNavigationPausesAutomaticPlayback() {
        let controller = LinePreviewController(
            label: "Better line",
            startingFEN: startingFEN,
            uciMoves: ["e2e4", "e7e5"]
        )
        controller.play()

        controller.stepForward()

        #expect(controller.stepIndex == 1)
        #expect(!controller.isPlaying)
    }
}
