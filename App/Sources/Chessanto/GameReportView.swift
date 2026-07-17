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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let report = viewModel.report {
                    reportContent(report)
                    if isCoachEnabled {
                        Divider()
                        coachSummarySection
                    }
                } else if engineService.isAnalyzing {
                    ProgressView("Analyzing...")
                        .padding()
                } else if viewModel.loadError != nil {
                    Text("This game couldn't be parsed, so no report is available.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Text("Analyze this game (see the Analyze button in the toolbar) to see the coaching report.")
                        .foregroundStyle(.secondary)
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
    private var coachSummarySection: some View {
        Text("Coach summary").font(.subheadline.bold())
        if let narration = coachService.summaryNarration {
            narrationView(narration)
        } else if coachService.isGenerating {
            HStack {
                ProgressView().controlSize(.small)
                Text("Coach is writing…").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func narrationView(_ narration: CoachNarration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(narration.text)
                .font(.callout)
            Text(narration.source == .coach ? "Coach" : "Rule-based")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reportContent(_ report: GameReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(report.whiteName) vs \(report.blackName) - \(report.result)")
                .font(.headline)
            HStack {
                Text("White: \(String(format: "%.1f", report.whiteAccuracy))% accuracy")
                Text("·").foregroundStyle(.secondary)
                Text("Black: \(String(format: "%.1f", report.blackAccuracy))% accuracy")
            }
            .font(.callout)
        }

        VStack(alignment: .leading, spacing: 2) {
            classificationRow(name: report.whiteName, counts: report.whiteClassificationCounts)
            classificationRow(name: report.blackName, counts: report.blackClassificationCounts)
        }

        if let opening = report.opening {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Opening").font(.subheadline.bold())
                Text("\(opening.name) (\(opening.eco))")
                if let deviationSAN = opening.deviationSAN, let deviationPly = opening.deviationPly {
                    Text("Left book on move \(moveNumberLabel(ply: deviationPly)) with \(deviationSAN).")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Divider()
        Text("Key moments").font(.subheadline.bold())
        if report.keyMoments.isEmpty {
            Text("No significant mistakes at this analysis depth.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(report.keyMoments, id: \.ply) { moment in
                keyMomentRow(moment)
            }
        }

        Divider()
        Text("Takeaways").font(.subheadline.bold())
        VStack(alignment: .leading, spacing: 4) {
            ForEach(report.takeaways, id: \.self) { takeaway in
                Text("- \(takeaway)")
            }
        }
    }

    private func classificationRow(name: String, counts: [ClassificationCount]) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.callout.bold())
            ForEach(counts, id: \.classification) { count in
                HStack(spacing: 2) {
                    ClassificationBadge(classification: count.classification)
                    Text("\(count.count)").font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func keyMomentRow(_ moment: KeyMoment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                guard moment.ply < viewModel.moveIndices.count else { return }
                viewModel.jump(to: viewModel.moveIndices[moment.ply])
            } label: {
                Text("\(moveNumberLabel(ply: moment.ply)) \(moment.evalSwing.playedSAN)\n\(momentSummary(moment))")
                    .font(.callout)
                    .foregroundStyle(moment.evalSwing.classification.color)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Key moment, move \(moveNumberLabel(ply: moment.ply)), \(moment.evalSwing.playedSAN). \(momentSummary(moment))")

            if isCoachEnabled {
                if let narration = coachService.narrationsByPly[moment.ply] {
                    narrationView(narration)
                        .padding(.leading, 8)
                } else if coachService.isGenerating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Coach is writing…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 8)
                }
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
}
