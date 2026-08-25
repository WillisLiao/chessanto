import SwiftUI

/// Practice as a right-pane mode of `GameReplayView` (DD1) - no modal sheet,
/// no fixed frame. The board itself is driven directly from `viewModel` by
/// `GameReplayView.boardColumn`; this view owns only the prompt, hints,
/// feedback, and session progress, in the same `Card` idiom the Report uses.
struct PracticeContentView: View {
    @ObservedObject var viewModel: PracticeSessionViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignColors.hairline)
            ScrollView {
                content
                    .padding()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice").font(.dsTitle).foregroundStyle(DesignColors.textPrimary)
                if let card = viewModel.currentCard {
                    Text("Card \(viewModel.currentIndex + 1) of \(viewModel.cards.count) - move \(moveNumberLabel(ply: card.sourcePly))")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                    Text(viewModel.stepProgressText)
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
            Spacer()
            Button("Exit practice") { onExit() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading practice...")
        case .empty:
            ContentUnavailableView(
                "No key moments ready",
                systemImage: "target",
                description: Text("Analyze a game with key moments, then start practice from the Report.")
            )
        case .failed(let message):
            ContentUnavailableView("Practice unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        case .prompt, .evaluating, .replying, .feedback:
            promptCard
        case .completed(let summary):
            completion(summary)
        }
    }

    @ViewBuilder
    private var promptCard: some View {
        Card {
            Text("Find the move you wish you had played.")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)

            if let card = viewModel.currentCard {
                HStack(spacing: DesignSpacing.xs) {
                    ClassificationChip(classification: card.classification)
                    if let label = viewModel.classificationLabel {
                        Text(label)
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                }

                // All three hint lines reserve their final space from the
                // start of the card (DD6). Opacity changes never move the
                // controls, including while the level-one threat is shown.
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(viewModel.threatHintTextIgnoringHintCount)
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                        .opacity(viewModel.hintCount >= 1 ? 1 : 0)
                        .accessibilityHidden(viewModel.hintCount < 1)
                    Text(viewModel.themeHintTextIgnoringHintCount)
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                        .opacity(viewModel.hintCount >= 2 ? 1 : 0)
                        .accessibilityHidden(viewModel.hintCount < 2)
                    Text(viewModel.originHintTextIgnoringHintCount)
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                        .opacity(viewModel.hintCount >= 3 ? 1 : 0)
                        .accessibilityHidden(viewModel.hintCount < 3)
                }
            }

            switch viewModel.state {
            case .evaluating:
                HStack(spacing: DesignSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Checking with the engine...")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            case .replying(let san):
                Text("Opponent replies \(san)")
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                    .accessibilityLabel("Opponent replies \(san)")
                    .accessibilityAddTraits(.updatesFrequently)
            case .feedback(let feedback):
                feedbackView(feedback)
            default:
                promptControls
            }
        }
    }

    private var promptControls: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            if let promptError = viewModel.promptError {
                Text(promptError)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.error)
            }
            HStack(spacing: DesignSpacing.sm) {
                Button("Hint") { viewModel.hint() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.hintCount >= 3)
                    .accessibilityLabel("Show hint")
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reveal best move")
            }
        }
    }

    private func feedbackView(_ feedback: TrainingEvaluation) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: feedback.outcome == .strong ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(feedback.outcome == .strong ? DesignColors.accent : DesignColors.textSecondary)
                Text(feedback.outcome.title)
                    .font(.dsBody.weight(.semibold))
            }
            Text("The Coach is demonstrating the verified line beside the board.")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)

            if let loss = feedback.lossCentipawns, feedback.outcome != .strong {
                Text("About \(String(format: "%.1f", Double(loss) / 100)) pawns worse than the best move.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }

            HStack(spacing: DesignSpacing.sm) {
                Button("Replay better line") {
                    viewModel.startBetterLinePreview()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Replay the engine's better line automatically on the board")
                if feedback.outcome == .incorrect {
                    Button("Try again") { viewModel.tryAgain() }
                        .buttonStyle(.bordered)
                }
                Button(feedback.outcome == .incorrect ? "Skip" : "Next") {
                    Task { await viewModel.next() }
                }
                // The app's own primary style, not `.borderedProminent`:
                // the system style renders a white label on the brass tint,
                // which fails contrast in both modes.
                .buttonStyle(.dsPrimary)
            }
        }
    }

    private func completion(_ summary: PracticeSessionViewModel.SessionSummary) -> some View {
        Card {
            SectionHeader(title: "Session complete")
            Text("\(summary.cardsCompleted) card\(summary.cardsCompleted == 1 ? "" : "s") completed")
                .font(.dsBody)
            Text("\(summary.firstAttemptSuccesses) successful first attempt\(summary.firstAttemptSuccesses == 1 ? "" : "s")")
                .font(.dsBody)
            if let recurringTheme = summary.recurringTheme {
                Text("Recurring theme: \(recurringTheme)")
                    .font(.dsBody)
            }
            if let nextDue = summary.nextDueDate {
                Text("Next review: \(nextDue.formatted(date: .abbreviated, time: .omitted))")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            Button("Back to game") { onExit() }
                .buttonStyle(.dsPrimary)
        }
    }

    private func moveNumberLabel(ply: Int) -> String {
        let moveNumber = (ply + 1) / 2
        return ply % 2 == 1 ? "\(moveNumber)." : "\(moveNumber)..."
    }
}
