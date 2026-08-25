import CompanionDomain
import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var model: MobileAppModel

    var body: some View {
        Group {
            if model.reports.isEmpty && activeJobs.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No saved reports",
                        systemImage: "doc.text.magnifyingglass"
                    )
                } description: {
                    Text(
                        model.isOnline
                            ? "Request analysis in Games, or send a report from your Mac."
                            : "You are offline. Saved reports will remain readable here."
                    )
                }
            } else {
                List {
                    if !activeJobs.isEmpty {
                        Section("Analysis progress") {
                            ForEach(
                                activeJobs,
                                id: \.requestID
                            ) { job in
                                AnalysisJobRow(job: job) {
                                    Task { await model.cancel(job) }
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(model.reports) { report in
                            NavigationLink {
                                OfflineReportReader(report: report)
                            } label: {
                                ReportRow(report: report)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await model.deleteReport(report) }
                                } label: {
                                    Label("Delete download", systemImage: "trash")
                                }
                            }
                            .accessibilityAction(named: "Delete download") {
                                Task { await model.deleteReport(report) }
                            }
                        }
                    } header: {
                        if !model.isOnline {
                            Label(
                                "Offline - saved reports are available",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(MobileColors.success)
                            .textCase(nil)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Reports")
        .companionBackground()
    }

    private var activeJobs: [AnalysisJobSnapshot] {
        model.jobs.filter { !$0.state.isTerminal }
    }
}

private struct ReportRow: View {
    let report: PortableAnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(report.metadata.white) vs \(report.metadata.black)")
                        .font(.headline)
                    Spacer()
                    Text(report.metadata.result)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.metadata.white) vs \(report.metadata.black)")
                        .font(.headline)
                    Text(report.metadata.result)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
            HStack {
                Text(report.generatedAt, style: .date)
                Text("·")
                Text(report.analysisQuality.rawValue.capitalized)
                Spacer()
                Label("Offline", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(MobileColors.success)
            }
            .font(.caption)
            .foregroundStyle(MobileColors.graphiteSoft)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(report.metadata.white) versus \(report.metadata.black), result \(report.metadata.result), \(report.analysisQuality.rawValue) quality, saved for offline reading"
        )
        .accessibilityHint("Opens offline game report")
    }
}
