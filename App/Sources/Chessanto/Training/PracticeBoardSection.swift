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
            if let preview = viewModel.linePreview {
                BoardView(
                    position: preview.current.position,
                    lastMove: preview.current.lastMove,
                    flipped: viewModel.flipped,
                    theme: theme
                )
            } else {
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
            }
            BoardIdentityStripView(info: identityStrips.bottom)
            if let preview = viewModel.linePreview {
                LinePreviewControlsView(controller: preview) {
                    viewModel.endLinePreview()
                }
            }
            if let feedback {
                let stage = CoachStageContent(
                    eyebrow: feedback.outcome == .strong ? "Strong move" : "Coach’s line",
                    headline: feedback.outcome == .strong
                        ? "You found the idea."
                        : "Let’s put the better move on the board.",
                    message: CoachStageText.condensed(feedback.explanation),
                    source: "Engine verified"
                )
                if let preview = viewModel.linePreview {
                    CoachPlaybackStageView(playback: preview, fallback: stage)
                } else {
                    CoachStageView(
                        content: stage,
                        primaryActionTitle: "Replay better line",
                        onPrimaryAction: viewModel.startBetterLinePreview
                    )
                }
            }
        }
    }

    private var feedback: TrainingEvaluation? {
        guard case .feedback(let feedback) = viewModel.state else { return nil }
        return feedback
    }
}
