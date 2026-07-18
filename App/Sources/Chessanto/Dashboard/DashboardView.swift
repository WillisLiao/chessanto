import AnalysisKit
import Charts
import Persistence
import SwiftUI

/// The player improvement dashboard (PLAN.md M8): the user's accuracy trend
/// across their analyzed games and their most frequent mistake themes.
/// Recomputed live on open (measured 3.55 ms/game in release mode during M8
/// prep) - no rollup table, no new persistence.
struct DashboardView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var engineService: EngineService
    @Environment(\.dismiss) private var dismiss

    private struct AccuracyPoint: Identifiable {
        let id: Int64
        let date: Date
        let accuracy: Double
    }

    private struct ThemeCount: Identifiable {
        let id: String
        let label: String
        let count: Int
    }

    private struct MoveClassificationCount: Identifiable {
        let classification: MoveClassification
        let count: Int
        var id: MoveClassification { classification }
    }

    @State private var isLoading = true
    @State private var points: [AccuracyPoint] = []
    @State private var themeCounts: [ThemeCount] = []
    @State private var classificationCounts: [MoveClassificationCount] = []
    @State private var analyzedGameCount = 0
    @State private var userMatchedGameCount = 0
    @State private var dueTrainingCards: [TrainingCardRecord] = []
    @State private var fallbackTrainingCards: [TrainingCardRecord] = []
    @State private var nextTrainingDueDate: Date?
    @State private var isPracticeOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Progress").font(.dsTitle).foregroundStyle(DesignColors.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider().overlay(DesignColors.hairline)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(DesignColors.hairline)
            Text(coverageLine)
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
                .padding()
        }
        .frame(width: 620, height: 470)
        .background(DesignColors.surface0)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if library.chessComUsername.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView(
                "Set your chess.com username",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("The dashboard tracks your games by matching your chess.com username. Set it in Settings.")
            )
        } else if isLoading {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if userMatchedGameCount == 0 {
            ContentUnavailableView(
                "No analyzed games yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Analyze a game where you're one of the players to see your progress here.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    Card { accuracyTrend }
                    Card { nextLesson }
                    Card { mistakeThemes }
                    if points.count < 3 {
                        Card { firstTrendMilestone }
                    }
                }
                .padding()
            }
        }
    }

    private var firstTrendMilestone: some View {
        let remaining = max(3 - points.count, 0)
        return Group {
            SectionHeader(title: "Next milestone")
            Text("Build your first trend")
                .font(.dsBody.weight(.semibold))
                .foregroundStyle(DesignColors.textPrimary)
            ProgressView(value: Double(points.count), total: 3)
                .tint(DesignColors.accent)
            Text("Analyze \(remaining) more of your game\(remaining == 1 ? "" : "s") to reveal the direction of your accuracy.")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
        }
    }

    private var nextLesson: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            SectionHeader(title: "Next lesson")
            if dueTrainingCards.isEmpty {
                Text("No review due right now.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textPrimary)
                if let nextTrainingDueDate {
                    Text("Next review: \(nextTrainingDueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                } else {
                    Text("Practice cards appear here after you analyze a game with key moments.")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                Button("Practice any position") {
                    isPracticeOpen = true
                }
                .buttonStyle(.bordered)
                .disabled(fallbackTrainingCards.isEmpty)
            } else {
                Text("\(dueTrainingCards.count) card\(dueTrainingCards.count == 1 ? "" : "s") ready")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textPrimary)
                Button {
                    isPracticeOpen = true
                } label: {
                    Label("Review next lesson", systemImage: "target")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $isPracticeOpen) {
            PracticeSessionView(viewModel: PracticeSessionViewModel(
                store: library.store,
                loadCards: { dueTrainingCards.isEmpty ? fallbackTrainingCards : dueTrainingCards },
                evaluator: DefaultTrainingMoveEvaluator { fen, attemptedUCI in
                    try await engineService.trainingEvaluationAfterMove(fen: fen, attemptedUCI: attemptedUCI)
                }
            ))
            .environmentObject(library)
            .environmentObject(engineService)
        }
    }

    @ViewBuilder
    private var accuracyTrend: some View {
        SectionHeader(title: "Accuracy trend")
        if points.count == 1, let only = points.first {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                HStack(spacing: DesignSpacing.sm) {
                    Text("\(String(format: "%.0f", only.accuracy))%")
                        .font(.dsTitle)
                        .foregroundStyle(DesignColors.accent)
                    Text("accuracy in your only analyzed game so far")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                Text("Analyze a few more of your games to see a trend here.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            .padding(.vertical, DesignSpacing.sm)
        } else {
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Accuracy", point.accuracy))
                    .foregroundStyle(DesignColors.accent)
                PointMark(x: .value("Date", point.date), y: .value("Accuracy", point.accuracy))
                    .foregroundStyle(DesignColors.accent)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(DesignColors.hairline)
                    AxisValueLabel().foregroundStyle(DesignColors.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(DesignColors.hairline)
                    AxisValueLabel().foregroundStyle(DesignColors.textSecondary)
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var mistakeThemes: some View {
        SectionHeader(title: "Most frequent mistake themes")
        if themeCounts.isEmpty {
            Text("No recurring mistake pattern yet.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(themeCounts) { theme in
                    HStack {
                        Text(theme.label).font(.dsBody)
                        Spacer()
                        Text("\(theme.count)").font(.dsNotation).foregroundStyle(DesignColors.textSecondary)
                    }
                }
            }
        }
        Divider()
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: DesignSpacing.xs)], alignment: .leading, spacing: DesignSpacing.xs) {
            ForEach(classificationCounts.filter { $0.count > 0 }) { count in
                Chip("\(count.classification.shortAbbreviation) \(count.count)", color: count.classification.color)
            }
        }
    }

    private var coverageLine: String {
        "\(userMatchedGameCount) of your games analyzed · \(library.games.count) games imported"
    }

    private func load() async {
        let username = library.chessComUsername.trimmingCharacters(in: .whitespaces)
        let games = library.games
        let store = library.store

        let result = await Task.detached(priority: .userInitiated) {
            await Self.computeDashboard(games: games, username: username, store: store)
        }.value

        points = result.points
        themeCounts = result.themeCounts
        classificationCounts = result.classificationCounts
        analyzedGameCount = result.analyzedGameCount
        userMatchedGameCount = result.userMatchedGameCount
        dueTrainingCards = (try? await store.dueTrainingCards()) ?? []
        fallbackTrainingCards = (try? await store.anyTrainingCards()) ?? []
        nextTrainingDueDate = try? await store.nextTrainingDueDate()
        isLoading = false
    }

    private struct DashboardData {
        let points: [AccuracyPoint]
        let themeCounts: [ThemeCount]
        let classificationCounts: [MoveClassificationCount]
        let analyzedGameCount: Int
        let userMatchedGameCount: Int
    }

    /// Off the main actor: for every game, fetch its analysis rows and build
    /// a `GameReport` via the shared `ReportBuilding` helper (same mapping
    /// `GameReplayViewModel.buildReport()` uses), then aggregate the side
    /// that matches `username` (case-insensitive, same rule as
    /// `GameReplayViewModel.userRatingInThisGame`).
    private static func computeDashboard(games: [GameRecord], username: String, store: GameStore) async -> DashboardData {
        var points: [AccuracyPoint] = []
        var punishmentCount = 0
        var missedMateCount = 0
        var allowedMateCount = 0
        var classificationTotals: [MoveClassification: Int] = [:]
        var analyzedGameCount = 0
        var userMatchedGameCount = 0

        for game in games {
            guard let gameId = game.id else { continue }
            let isWhite = game.white.caseInsensitiveCompare(username) == .orderedSame
            let isBlack = game.black.caseInsensitiveCompare(username) == .orderedSame
            guard isWhite || isBlack else { continue }

            guard let analysisRows = try? await store.analysis(gameId: gameId), !analysisRows.isEmpty else { continue }
            analyzedGameCount += 1

            guard let report = ReportBuilding.buildReport(record: game, analysisRows: analysisRows, chessComUsername: username) else {
                continue
            }
            userMatchedGameCount += 1

            let accuracy = isWhite ? report.whiteAccuracy : report.blackAccuracy
            points.append(AccuracyPoint(id: gameId, date: game.playedAt ?? game.importedAt, accuracy: accuracy))

            let counts = isWhite ? report.whiteClassificationCounts : report.blackClassificationCounts
            for count in counts {
                classificationTotals[count.classification, default: 0] += count.count
            }

            for moment in report.keyMoments {
                let moverIsUser = moment.evalSwing.moverIsWhite == isWhite
                guard moverIsUser else { continue }
                if moment.punishment != nil { punishmentCount += 1 }
                if moment.missedMate != nil { missedMateCount += 1 }
                if moment.allowedMate != nil { allowedMateCount += 1 }
            }
        }

        points.sort { $0.date < $1.date }

        let themeCounts = [
            ThemeCount(id: "punishment", label: "Left a piece en prise", count: punishmentCount),
            ThemeCount(id: "missedMate", label: "Missed a forced mate", count: missedMateCount),
            ThemeCount(id: "allowedMate", label: "Allowed a forced mate", count: allowedMateCount)
        ].filter { $0.count > 0 }

        let classificationCounts = MoveClassification.allCases.map { classification in
            MoveClassificationCount(classification: classification, count: classificationTotals[classification] ?? 0)
        }

        return DashboardData(
            points: points, themeCounts: themeCounts, classificationCounts: classificationCounts,
            analyzedGameCount: analyzedGameCount, userMatchedGameCount: userMatchedGameCount
        )
    }
}
