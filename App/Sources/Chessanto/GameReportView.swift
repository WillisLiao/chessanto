import AnalysisKit
import SwiftUI

/// The M5 rule-based coaching report - the "Report" tab of the game replay
/// pane. States: not analyzed (point at the Analyze button), analyzing
/// (progress), and the rendered report. Every key moment is a real `Button`
/// (native control, AX-drivable) that jumps the board to that ply.
struct GameReportView: View {
    @ObservedObject var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @Environment(\.moveNotation) private var moveNotation
    /// Opens the Coach panel pinned to a ply - the Report key-moment entry
    /// point (decision A).
    let onAskCoach: (Int) -> Void
    let onPractice: (Int?) -> Void
    let onSelectMoment: (KeyMoment) -> Void
    let onPlayBetterLine: (KeyMoment) -> Void
    let onPlayContinuation: (KeyMoment) -> Void
    /// Starts analysis from inside the empty report. The tab that exists to
    /// show the report is the natural place to ask for one; pointing at a
    /// control elsewhere on screen made the primary surface a dead end.
    var onAnalyze: (() -> Void)?
    @State private var isClassificationLegendExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                if let report = viewModel.report {
                    reportContent(report)
                } else if engineService.isAnalyzing,
                    let progress = engineService.batchProgress
                {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        ProgressView(
                            value: Double(progress.done),
                            total: Double(max(progress.total, 1))
                        )
                        Text(
                            "Analyzing \(progress.done) of \(progress.total) positions"
                        )
                        .font(.dsSecondary.monospacedDigit())
                        .foregroundStyle(DesignColors.textSecondary)
                    }
                    .padding()
                } else if engineService.isAnalyzing {
                    ProgressView("Preparing analysis...")
                        .padding()
                } else if viewModel.loadError != nil {
                    Text("This game couldn't be parsed, so no report is available.")
                        .foregroundStyle(DesignColors.textSecondary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: DesignSpacing.md) {
                        Text("This game has not been analyzed yet.")
                            .font(.dsBody)
                            .foregroundStyle(DesignColors.textPrimary)
                        Text("Analysis finds the moments that decided the game and explains them.")
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let onAnalyze {
                            Button("Analyze this game", action: onAnalyze)
                                .buttonStyle(.dsPrimary)
                                .disabled(!engineService.isStarted)
                            if !engineService.isStarted {
                                Text(engineService.unavailableReason ?? "Starting the engine…")
                                    .font(.dsSecondary)
                                    .foregroundStyle(DesignColors.textSecondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func reportContent(_ report: GameReport) -> some View {
        Card {
            SectionHeader(title: "Game audit")
            Text("\(report.whiteName) vs \(report.blackName) · \(report.result)")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
            let isWhiteUser = BoardIdentityStrip.isUser(name: report.whiteName, username: report.chessComUsername ?? "")
            let isBlackUser = BoardIdentityStrip.isUser(name: report.blackName, username: report.chessComUsername ?? "")
            HStack(spacing: DesignSpacing.xs) {
                Text(AccuracySummaryFormatter.format(side: "White", accuracy: report.whiteAccuracy, isUser: isWhiteUser))
                    .foregroundStyle(isWhiteUser ? DesignColors.accentText : DesignColors.textSecondary)
                Text("·").foregroundStyle(DesignColors.textSecondary)
                Text(AccuracySummaryFormatter.format(side: "Black", accuracy: report.blackAccuracy, isUser: isBlackUser))
                    .foregroundStyle(isBlackUser ? DesignColors.accentText : DesignColors.textSecondary)
            }
            .font(.dsNotation)

            Divider()

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                classificationRow(name: report.whiteName, counts: report.whiteClassificationCounts)
                classificationRow(name: report.blackName, counts: report.blackClassificationCounts)
            }

            Divider()

            classificationLegend
        }

        if let opening = report.opening {
            Card {
                SectionHeader(title: "Opening")
                Text("\(opening.name) (\(opening.eco))")
                    .font(.dsBody)
                if let deviationSAN = opening.deviationSAN, let deviationPly = opening.deviationPly {
                    Text("Left book on move \(bareMoveNumber(ply: deviationPly)) with \(moveNotation.move(deviationSAN).visual).")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
        }

        Card {
            SectionHeader(title: "Key-moment register")
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
                    }
                    .buttonStyle(.dsPrimary)
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
                        keyMomentRow(moment, report: report)
                    }
                }
            }
        }

        Card {
            SectionHeader(title: "Review notes")
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(report.takeaways, id: \.self) { takeaway in
                    Text("- \(moveNotation.text(takeaway))").font(.dsBody)
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

    private var classificationLegend: some View {
        DisclosureGroup(
            isExpanded: $isClassificationLegendExpanded,
            content: {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    ForEach(MoveClassification.allCases, id: \.self) { classification in
                        VStack(alignment: .leading, spacing: 2) {
                            ClassificationChip(classification: classification)
                            Text(ChessGlossary.gloss(for: classification))
                                .font(.dsSecondary)
                                .foregroundStyle(DesignColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(.top, DesignSpacing.xs)
            },
            label: {
                Text("Classification marks legend")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        )
    }

    @ViewBuilder
    private func keyMomentRow(_ moment: KeyMoment, report: GameReport) -> some View {
        let summary = ReportText.momentSummary(moment, report: report, includingMoveLabel: false)
        let isPinned = viewModel.isPlyPinned(moment.ply)
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Button {
                onSelectMoment(moment)
            } label: {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    HStack(spacing: DesignSpacing.xs) {
                        Text(moveNumberLabel(ply: moment.ply))
                            .font(.dsNotation)
                            .foregroundStyle(DesignColors.textSecondary)
                        Text(moveNotation.move(moment.evalSwing.playedSAN).visual)
                            .font(.dsNotation.weight(.semibold))
                        ClassificationChip(classification: moment.evalSwing.classification)
                        if isPinned {
                            HStack(spacing: 2) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Pinned in Coach")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(DesignColors.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DesignColors.selection)
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }

                    Text(moveNotation.text(summary))
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)

                    if report.register == .beginner, let match = ChessGlossary.match(in: summary) {
                        Text("\(match.term) - \(match.gloss)")
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                    }

                }
                .padding(DesignSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyMomentRowButtonStyle())
            .accessibilityLabel(
                isPinned
                    ? "Key moment, move \(moveNumberLabel(ply: moment.ply)), \(moveNotation.move(moment.evalSwing.playedSAN).spoken), pinned in Coach. \(moveNotation.accessibilityText(summary))"
                    : "Key moment, move \(moveNumberLabel(ply: moment.ply)), \(moveNotation.move(moment.evalSwing.playedSAN).spoken). \(moveNotation.accessibilityText(summary))"
            )
            .contextMenu {
                Button("Ask Coach about this moment") {
                    onAskCoach(moment.ply)
                }
            }

            HStack(spacing: DesignSpacing.sm) {
                if moment.betterMove != nil {
                    Button {
                        onPlayBetterLine(moment)
                    } label: {
                        Label("Show better line", systemImage: "play.fill")
                    }
                    .font(.dsSecondary.weight(.semibold))
                    .buttonStyle(.bordered)
                }

                Button {
                    onPlayContinuation(moment)
                } label: {
                    Label("What happened", systemImage: "arrow.right")
                }
                .font(.dsSecondary.weight(.semibold))
                .buttonStyle(.bordered)

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

/// A chrome-free button style, equivalent to `.plain` in that it paints no
/// system border or fill, but adds a hover/pressed `surface1` background so
/// the whole key-moment block reads as clickable (DD4) - which a bare
/// `.plain` style, by design, never does.
private struct KeyMomentRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(configuration.isPressed || isHovering ? DesignColors.surface1 : Color.clear)
            )
            .onHover { isHovering = $0 }
    }
}
