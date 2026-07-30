import SwiftUI

/// The batch run's presence in the sidebar: a progress strip while it runs,
/// a short result line when it ends, and nothing at all when idle.
///
/// It sits above the sidebar's bottom bar rather than in a sheet because a
/// fifty-game run takes long enough that the user should be able to keep
/// reading games while it works.
struct BatchAnalysisBar: View {
    @ObservedObject var coordinator: BatchAnalysisCoordinator

    var body: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .running(let progress):
            running(progress)
        case .finished(let summary):
            finished(summary)
        }
    }

    private func running(_ progress: BatchAnalysisCoordinator.Progress) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            HStack {
                Text("Analyzing \(progress.completed + 1) of \(progress.total)")
                    .font(.dsSectionHeader)
                    .foregroundStyle(DesignColors.textPrimary)
                Spacer()
                Button("Stop") { coordinator.cancel() }
                    .buttonStyle(.borderless)
                    .font(.dsSecondary)
            }
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(DesignColors.accent)
            Text(progress.currentTitle)
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .top) { Rectangle().fill(DesignColors.hairline).frame(height: 1) }
    }

    private func finished(_ summary: BatchAnalysisCoordinator.Summary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(for: summary))
                    .font(.dsSectionHeader)
                    .foregroundStyle(DesignColors.textPrimary)
                if let first = summary.failures.first {
                    // Name the first game that failed rather than only
                    // counting them: "1 game could not be analyzed" gives
                    // the user nothing to act on.
                    Text(
                        summary.failures.count == 1
                            ? "\(first.title): \(first.reason)"
                            : "\(first.title) and \(summary.failures.count - 1) more could not be analyzed."
                    )
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button("Done") { coordinator.acknowledge() }
                .buttonStyle(.borderless)
                .font(.dsSecondary)
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .top) { Rectangle().fill(DesignColors.hairline).frame(height: 1) }
    }

    private func headline(for summary: BatchAnalysisCoordinator.Summary) -> String {
        let games = summary.analyzed == 1 ? "game" : "games"
        if summary.wasCancelled {
            return "Stopped after \(summary.analyzed) \(games)"
        }
        if summary.failures.isEmpty {
            return "Analyzed \(summary.analyzed) \(games)"
        }
        return "Analyzed \(summary.analyzed) \(games), \(summary.failures.count) failed"
    }
}
