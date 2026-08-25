import SwiftUI

/// The library filter popover: one control per `LibraryFilter` dimension.
/// Every picker shows what selecting it would match against the current
/// register, and unset means no constraint.
struct LibraryFilterPanel: View {
    @Binding var filter: LibraryFilter
    let options: LibraryFilterOptions
    let matchingCount: Int

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack {
                Text("Filter games").dsSectionHeaderStyle()
                Spacer()
                Text("\(matchingCount) of \(options.totalCount)")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .help("Games matching the current search and filters")
            }

            pickerRow("Opponent") {
                Picker("Opponent", selection: $filter.opponent) {
                    Text("Any opponent").tag(String?.none)
                    ForEach(options.opponents, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
            }

            pickerRow("Result") {
                Picker("Result", selection: $filter.outcome) {
                    Text("Any result").tag(LibraryOutcome?.none)
                    ForEach(LibraryOutcome.allCases, id: \.self) { outcome in
                        Text(outcome.label).tag(LibraryOutcome?.some(outcome))
                    }
                }
                .disabled(!options.outcomeAvailable)
                .help(
                    options.outcomeAvailable
                        ? "Your own wins, losses, and draws"
                        : "Set your account or player name first so Chessanto knows which side is yours"
                )
            }

            pickerRow("Opening") {
                Picker("Opening", selection: $filter.openingFamily) {
                    Text("Any opening").tag(String?.none)
                    ForEach(options.families, id: \.family) { entry in
                        Text(panelLabel("ECO \(entry.family)", count: entry.count))
                            .tag(String?.some(entry.family))
                    }
                }
            }

            pickerRow("Time control") {
                Picker("Time control", selection: $filter.timeControl) {
                    Text("Any time control").tag(TimeControlCategory?.none)
                    ForEach(options.timeControls, id: \.category) { entry in
                        Text(panelLabel(entry.category.label, count: entry.count))
                            .tag(TimeControlCategory?.some(entry.category))
                    }
                }
            }

            pickerRow("Accuracy") {
                Picker("Accuracy", selection: $filter.accuracyBand) {
                    Text("Any accuracy").tag(AccuracyBand?.none)
                    ForEach(AccuracyBand.allCases, id: \.self) { band in
                        Text(band.label).tag(AccuracyBand?.some(band))
                    }
                }
                .disabled(!options.accuracyAvailable)
                .help(
                    options.accuracyAvailable
                        ? "Your own accuracy in analyzed games"
                        : "Analyze your games to filter by your accuracy"
                )
            }

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                HStack {
                    Text("Played").dsSectionHeaderStyle()
                    if filter.playedFrom != nil || filter.playedTo != nil {
                        Button("Clear dates") {
                            filter.playedFrom = nil
                            filter.playedTo = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.dsSecondary)
                    }
                }
                datePicker("From", binding: fromBinding)
                datePicker("To", binding: toBinding)
            }

            HStack {
                Button("Reset All") { filter.reset() }
                    .buttonStyle(.borderless)
                    .disabled(!filter.isActive)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(DesignSpacing.lg)
        .frame(width: 280)
        .background(DesignColors.surface0)
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(title).dsSectionHeaderStyle()
            content()
                .font(.dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func datePicker(_ title: String, binding: Binding<Date>) -> some View {
        HStack {
            DatePicker(title, selection: binding, displayedComponents: .date)
                .font(.dsBody)
            if bound(for: title) != nil {
                Button {
                    clearBound(for: title)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignColors.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Clear this date")
            }
        }
    }

    private func bound(for title: String) -> Date? {
        title == "From" ? filter.playedFrom : filter.playedTo
    }

    private func clearBound(for title: String) {
        if title == "From" {
            filter.playedFrom = nil
        } else {
            filter.playedTo = nil
        }
    }

    private func panelLabel(_ base: String, count: Int) -> String {
        count > 0 ? "\(base)  (\(count))" : base
    }

    /// Optional date bounds behind non-optional `DatePicker`s: unsetting is
    /// explicit (the clear buttons), and picking a date always sets the bound.
    private var fromBinding: Binding<Date> {
        Binding(
            get: { filter.playedFrom ?? calendar.date(byAdding: .year, value: -10, to: .now) ?? .distantPast },
            set: { filter.playedFrom = calendar.startOfDay(for: $0) }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { filter.playedTo ?? calendar.date(byAdding: .year, value: 1, to: .now) ?? .distantFuture },
            set: { filter.playedTo = calendar.startOfDay(for: $0) }
        )
    }
}
