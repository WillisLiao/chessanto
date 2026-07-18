import AnalysisKit
import CoachKit
import SwiftUI

/// The M5 rule-based coaching report - the "Report" tab of the game replay
/// pane. States: not analyzed (point at the Analyze button), analyzing
/// (progress), and the rendered report. Every key moment is a real `Button`
/// (native control, AX-drivable) that jumps the board to that ply.
struct GameReportView: View {
    @ObservedObject var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var coachService: CoachService
    /// Opens the Coach panel pinned to a ply - the Report key-moment entry
    /// point (decision A).
    let onAskCoach: (Int) -> Void
    let onPractice: (Int?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                if let report = viewModel.report {
                    reportContent(report)
                } else if engineService.isAnalyzing {
                    ProgressView("Analyzing...")
                        .padding()
                } else if viewModel.loadError != nil {
                    Text("This game couldn't be parsed, so no report is available.")
                        .foregroundStyle(DesignColors.textSecondary)
                        .padding()
                } else {
                    Text("Analyze this game (see the Analyze button above the board) to see the coaching report.")
                        .foregroundStyle(DesignColors.textSecondary)
                        .padding()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: viewModel.report) {
            await maybeGenerateNarrations()
        }
    }

    private var isCoachEnabled: Bool {
        viewModel.userProfile()?.coachEnabled == true
    }

    @MainActor
    private func maybeGenerateNarrations() async {
        guard let report = viewModel.report, let input = viewModel.reportInput,
            let profile = viewModel.userProfile(), profile.coachEnabled
        else { return }
        coachService.generateNarrations(
            report: report, input: input, userProfile: profile,
            userRating: viewModel.userRatingInThisGame, executor: engineService
        )
    }

    @ViewBuilder
    private func narrationView(_ narration: CoachNarration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(narration.text)
                .font(.dsBody)
            Text(narration.source == .coach ? "Coach" : "Rule-based")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
        }
    }

    @ViewBuilder
    private func reportContent(_ report: GameReport) -> some View {
        Card {
            Text("\(report.whiteName) vs \(report.blackName) - \(report.result)")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
            HStack(spacing: DesignSpacing.xs) {
                Text("White \(String(format: "%.1f", report.whiteAccuracy))%")
                    .foregroundStyle(DesignColors.accent)
                Text("·").foregroundStyle(DesignColors.textSecondary)
                Text("Black \(String(format: "%.1f", report.blackAccuracy))%")
                    .foregroundStyle(DesignColors.accent)
            }
            .font(.dsNotation)

            Divider()

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                classificationRow(name: report.whiteName, counts: report.whiteClassificationCounts)
                classificationRow(name: report.blackName, counts: report.blackClassificationCounts)
            }
        }

        if let opening = report.opening {
            Card {
                SectionHeader(title: "Opening")
                Text("\(opening.name) (\(opening.eco))")
                    .font(.dsBody)
                if let deviationSAN = opening.deviationSAN, let deviationPly = opening.deviationPly {
                    Text("Left book on move \(bareMoveNumber(ply: deviationPly)) with \(deviationSAN).")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
        }

        Card {
            SectionHeader(title: "Key moments")
            if report.keyMoments.isEmpty {
                Text("No significant mistakes at this analysis depth.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
            } else {
                if viewModel.isTrainingReady, viewModel.trainingCardCount == 0 {
                    Label(
                        "No practice moments for your side in this report.",
                        systemImage: "checkmark.circle"
                    )
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                } else {
                    Button {
                        if viewModel.isTrainingReady {
                            onPractice(nil)
                        } else if viewModel.trainingCardError != nil {
                            viewModel.retryTrainingCardReconciliation()
                        }
                    } label: {
                        Group {
                            if viewModel.isTrainingReady {
                                Label("Practice key moments", systemImage: "target")
                            } else if viewModel.trainingCardError != nil {
                                Label("Retry practice preparation", systemImage: "arrow.clockwise")
                            } else {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Preparing practice...")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.isTrainingReady && viewModel.trainingCardError == nil)
                    .accessibilityLabel(
                        viewModel.isTrainingReady
                            ? "Practice key moments from this report"
                            : viewModel.trainingCardError == nil
                                ? "Preparing practice key moments"
                                : "Retry preparing practice key moments"
                    )
                }

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    ForEach(Array(report.keyMoments.enumerated()), id: \.element.ply) { offset, moment in
                        if offset > 0 { Divider() }
                        keyMomentRow(moment)
                    }
                }
            }
        }

        Card {
            SectionHeader(title: "Takeaways")
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(report.takeaways, id: \.self) { takeaway in
                    Text("- \(takeaway)").font(.dsBody)
                }
            }
        }

        if isCoachEnabled {
            Card {
                SectionHeader(title: "Coach summary")
                if let narration = coachService.summaryNarration {
                    narrationView(narration)
                } else if coachService.isGenerating {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Coach is writing…").foregroundStyle(DesignColors.textSecondary)
                    }
                }
            }
        }
    }

    /// A per-player row of classification chips that must never wrap
    /// mid-word or wrap a chip's own text, even in the narrowest (260pt)
    /// right-pane width (fact 3) - an adaptive grid wraps whole chips onto a
    /// second line instead of letting `HStack` overflow.
    private func classificationRow(name: String, counts: [ClassificationCount]) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(name).font(.dsBody.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: DesignSpacing.xs)], alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(counts, id: \.classification) { count in
                    ClassificationChip(classification: count.classification, count: count.count)
                }
            }
        }
    }

    @ViewBuilder
    private func keyMomentRow(_ moment: KeyMoment) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Button {
                guard moment.ply < viewModel.moveIndices.count else { return }
                viewModel.jump(to: viewModel.moveIndices[moment.ply])
            } label: {
                HStack(spacing: DesignSpacing.xs) {
                    Text(moveNumberLabel(ply: moment.ply))
                        .font(.dsNotation)
                        .foregroundStyle(DesignColors.textSecondary)
                    Text(moment.evalSwing.playedSAN)
                        .font(.dsNotation.weight(.semibold))
                    ClassificationChip(classification: moment.evalSwing.classification)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Key moment, move \(moveNumberLabel(ply: moment.ply)), \(moment.evalSwing.playedSAN). \(momentSummary(moment))")
            .contextMenu {
                Button("Ask the coach about this moment") {
                    onAskCoach(moment.ply)
                }
            }

            Text(momentSummary(moment))
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)

            if isCoachEnabled {
                if let narration = coachService.narrationsByPly[moment.ply] {
                    narrationView(narration)
                } else if coachService.isGenerating {
                    HStack(spacing: DesignSpacing.xs) {
                        ProgressView().controlSize(.mini)
                        Text("Coach is writing…").font(.dsSecondary).foregroundStyle(DesignColors.textSecondary)
                    }
                }
            }

            if viewModel.trainingCardSourcePlies.contains(moment.ply) {
                Button {
                    onPractice(moment.ply)
                } label: {
                    Label("Practice", systemImage: "target")
                }
                .font(.dsSecondary.weight(.semibold))
                .buttonStyle(.bordered)
                .accessibilityLabel("Practice this key moment")
            }
        }
    }

    private func momentSummary(_ moment: KeyMoment) -> String {
        var parts: [String] = []
        parts.append("Drops winning chances from \(Int(moment.evalSwing.moverWinProbabilityBefore.rounded()))% to \(Int(moment.evalSwing.moverWinProbabilityAfter.rounded()))%.")
        if let betterMove = moment.betterMove {
            parts.append("Better was \(betterMove.bestMoveSAN).")
        }
        if let punishment = moment.punishment {
            parts.append("\(punishment.refutingSAN) punishes this.")
        }
        if let missedMate = moment.missedMate {
            parts.append("Missed a forced mate in \(missedMate.mateInN).")
        }
        if let allowedMate = moment.allowedMate {
            parts.append("Allowed a forced mate in \(allowedMate.mateInN).")
        }
        return parts.joined(separator: " ")
    }

    private func moveNumberLabel(ply: Int) -> String {
        let moveNumber = (ply + 1) / 2
        let isWhite = ply % 2 == 1
        return isWhite ? "\(moveNumber)." : "\(moveNumber)..."
    }

    /// Bare move number (no trailing "." / "...") for mid-sentence use, so
    /// the opening-deviation sentence doesn't collide two periods together
    /// (fact 11: "Left book on move 3. with Nc3.").
    private func bareMoveNumber(ply: Int) -> String {
        String((ply + 1) / 2)
    }
}
