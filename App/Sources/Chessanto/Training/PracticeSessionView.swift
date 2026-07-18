import SwiftUI

struct PracticeSessionView: View {
    @StateObject private var viewModel: PracticeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    let backToGame: (() -> Void)?

    init(viewModel: PracticeSessionViewModel, backToGame: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.backToGame = backToGame
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignColors.hairline)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(DesignColors.surface0)
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice key moments")
                    .font(.dsTitle)
                    .foregroundStyle(DesignColors.textPrimary)
                if let card = viewModel.currentCard {
                    Text("Card \(viewModel.currentIndex + 1) of \(viewModel.cards.count) - move \(moveNumberLabel(ply: card.sourcePly))")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
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
        case .prompt, .evaluating, .feedback:
            practiceBody
        case .completed(let summary):
            completion(summary)
        }
    }

    private var practiceBody: some View {
        HStack(alignment: .top, spacing: DesignSpacing.lg) {
            BoardView(
                position: viewModel.position,
                flipped: viewModel.flipped,
                selectedSquare: viewModel.selectedSquare,
                legalDestinations: viewModel.legalDestinations,
                arrows: viewModel.revealArrow,
                onSquareTapped: viewModel.select(square:)
            )
            .frame(width: 420, height: 420)
            .padding()

            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                promptCard
                Spacer()
            }
            .frame(minWidth: 260, maxWidth: 320)
            .padding(.vertical)
            .padding(.trailing)
        }
    }

    @ViewBuilder
    private var promptCard: some View {
        Card {
            Text("Find the move you wish you had played.")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)

            if let card = viewModel.currentCard {
                ClassificationChip(classification: card.classification)
                if viewModel.hintCount >= 1 {
                    Text(card.themes.first ?? "Look for the forcing idea.")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                if viewModel.hintCount >= 2, let best = card.bestMoveUCI {
                    Text("Start from \(String(best.prefix(2))).")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
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
                    .disabled(viewModel.hintCount >= 2)
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
            Text(feedback.explanation)
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)

            if let loss = feedback.lossCentipawns, feedback.outcome != .strong {
                Text("Engine loss: \(loss) centipawns.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }

            HStack(spacing: DesignSpacing.sm) {
                if feedback.outcome == .incorrect {
                    Button("Try again") { viewModel.tryAgain() }
                        .buttonStyle(.bordered)
                }
                Button(feedback.outcome == .incorrect ? "Skip" : "Next") {
                    Task { await viewModel.next() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func completion(_ summary: PracticeSessionViewModel.SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
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
                HStack {
                    Button("Back to game") {
                        dismiss()
                        backToGame?()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .frame(width: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moveNumberLabel(ply: Int) -> String {
        let moveNumber = (ply + 1) / 2
        return ply % 2 == 1 ? "\(moveNumber)." : "\(moveNumber)..."
    }
}
