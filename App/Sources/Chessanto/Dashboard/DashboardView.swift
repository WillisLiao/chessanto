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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Progress").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            Text(coverageLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 620, height: 520)
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
                VStack(alignment: .leading, spacing: 20) {
                    accuracyTrend
                    mistakeThemes
                }
                .padding()
            }
        }
    }

    private var accuracyTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy trend").font(.headline)
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Accuracy", point.accuracy))
                PointMark(x: .value("Date", point.date), y: .value("Accuracy", point.accuracy))
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
        }
    }

    private var mistakeThemes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most frequent mistake themes").font(.headline)
            ForEach(themeCounts) { theme in
                HStack {
                    Text(theme.label)
                    Spacer()
                    Text("\(theme.count)").foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 12) {
                ForEach(classificationCounts.filter { $0.count > 0 }) { count in
                    HStack(spacing: 4) {
                        ClassificationBadge(classification: count.classification)
                        Text("\(count.count)")
                    }
                }
            }
        }
    }

    private var coverageLine: String {
        "\(analyzedGameCount) of \(library.games.count) imported games analyzed (user-matched: \(userMatchedGameCount))"
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
