import SwiftUI

/// The board half of inline practice mode (DD1) - observes
/// `PracticeSessionViewModel` directly so taps and hints repaint without
/// requiring `GameReplayView` itself to re-render. Kept separate from
/// `PracticeContentView` (the prompt/hints/feedback half) because the two
/// live in different `HSplitView` columns.
struct PracticeBoardSection: View {
    @ObservedObject var viewModel: PracticeSessionViewModel
    let theme: BoardTheme
    let identityStrips: (top: BoardIdentityStripInfo, bottom: BoardIdentityStripInfo)

    var body: some View {
        VStack(spacing: DesignSpacing.xs) {
            BoardIdentityStripView(info: identityStrips.top)
            BoardView(
                position: viewModel.position,
                flipped: viewModel.flipped,
                theme: theme,
                selectedSquare: viewModel.selectedSquare,
                legalDestinations: viewModel.legalDestinations,
                hintSquares: viewModel.hintSquares,
                arrows: viewModel.revealArrow,
                onSquareTapped: viewModel.select(square:)
            )
            BoardIdentityStripView(info: identityStrips.bottom)
        }
    }
}
