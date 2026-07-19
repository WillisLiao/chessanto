import SwiftUI

struct LinePreviewBoardSection: View {
    @ObservedObject var controller: LinePreviewController
    let flipped: Bool
    let theme: BoardTheme
    let identityStrips: (top: BoardIdentityStripInfo, bottom: BoardIdentityStripInfo)
    let coachContent: CoachStageContent
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: DesignSpacing.xs) {
            BoardIdentityStripView(info: identityStrips.top)
            BoardView(
                position: controller.current.position,
                lastMove: controller.current.lastMove,
                flipped: flipped,
                theme: theme
            )
            BoardIdentityStripView(info: identityStrips.bottom)
            LinePreviewControlsView(controller: controller, onDone: onDone)
            CoachPlaybackStageView(
                playback: controller,
                fallback: coachContent
            )
        }
    }
}
