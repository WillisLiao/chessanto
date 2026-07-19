import AnalysisKit
import Charts
import Persistence
import SwiftUI

struct PlayerBriefView: View {
    @EnvironmentObject private var library: GameLibrary
    let onOpenPractice: (
        _ gameID: Int64,
        _ loadCards: @escaping () async throws -> [TrainingCardRecord]
    ) -> Void

    @State private var isLoading = true
    @State private var snapshot: PlayerBriefSnapshot?
    @State private var dueTrainingCards: [TrainingCardRecord] = []
    @State private var dueTrainingCardCount = 0
    @State private var fallbackTrainingCards: [TrainingCardRecord] = []
    @State private var nextTrainingDueDate: Date?
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DesignColors.hairline)
            content
        }
        .background(DesignColors.surface0)
        .task(id: loadIdentity) { await load() }
    }

    private var loadIdentity: String {
        "\(library.isChessComAccountConfirmed):\(library.chessComUsername.lowercased()):\(loadGeneration)"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Player Brief")
                    .font(.dsTitle)
                    .foregroundStyle(DesignColors.textPrimary)
                if !library.chessComUsername.isEmpty {
                    Text("@\(library.chessComUsername)")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
            Spacer()
            if let snapshot {
                Text("\(snapshot.coverage.analyzed) of \(snapshot.coverage.imported) games analyzed")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if !library.isChessComAccountConfirmed {
            ContentUnavailableView(
                "Confirm your chess.com account",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Player Brief matches analyzed games to the account you explicitly confirm in Settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            ProgressView("Building your brief…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Player Brief unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") { loadGeneration += 1 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot, snapshot.coverage.analyzed > 0 {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    focusRegister(snapshot)
                    metricStrip(snapshot)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: DesignSpacing.xl) {
                            mainEvidenceColumn(snapshot)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            evidenceColumn(snapshot)
                                .frame(width: 300, alignment: .topLeading)
                        }
                        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                            mainEvidenceColumn(snapshot)
                            evidenceColumn(snapshot)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    coverageLine(snapshot)
                }
                .frame(maxWidth: 1040)
                .padding(DesignSpacing.xl)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView(
                "No analyzed games yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Analyze a game where @\(library.chessComUsername) is one of the players to build your first brief.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func focusRegister(_ snapshot: PlayerBriefSnapshot) -> some View {
        HStack(alignment: .center, spacing: DesignSpacing.lg) {
            Rectangle()
                .fill(DesignColors.accent)
                .frame(width: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Current finding")
                    .font(.dsSectionHeader)
                    .foregroundStyle(DesignColors.accentText)
                Text(snapshot.focus.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                Text(snapshot.focus.detail)
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignSpacing.md)
            reviewAction
        }
        .padding(.vertical, DesignSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var reviewAction: some View {
        if dueTrainingCards.isEmpty {
            Button("Practice positions") {
                startPractice(cards: fallbackTrainingCards)
            }
            .buttonStyle(.bordered)
            .disabled(fallbackTrainingCards.isEmpty)
        } else {
            Button("Review \(dueTrainingCardCount) position\(dueTrainingCardCount == 1 ? "" : "s")") {
                startPractice(cards: dueTrainingCards)
            }
            .buttonStyle(.dsPrimary)
        }
    }

    private func metricStrip(_ snapshot: PlayerBriefSnapshot) -> some View {
        HStack(spacing: 0) {
            metric(
                value: String(format: "%.0f%%", snapshot.averageAccuracy),
                label: "\(snapshot.coverage.analyzed)-game mean"
            )
            metricDivider
            metric(value: "\(costlyMoveCount(snapshot))", label: "Costly moves")
            metricDivider
            metric(
                value: "\(snapshot.coverage.analyzed) / \(snapshot.coverage.imported)",
                label: "Analyzed / imported"
            )
            metricDivider
            metric(value: "\(dueTrainingCardCount)", label: "Reviews due")
        }
        .padding(.vertical, DesignSpacing.md)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(DesignColors.hairline)
            .frame(width: 1, height: 34)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignColors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func mainEvidenceColumn(_ snapshot: PlayerBriefSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            accuracySection(snapshot)
            phaseSection(snapshot)
            classificationSection(snapshot)
        }
    }

    private func evidenceColumn(_ snapshot: PlayerBriefSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            strengthSection(snapshot)
            lessonSection
            motifSection(snapshot)
            contextSection(snapshot)
        }
    }

    private func strengthSection(_ snapshot: PlayerBriefSnapshot) -> some View {
        Card {
            SectionHeader(title: "Strength")
            if let strength = snapshot.strength {
                Text(strength.title)
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                Text(strength.detail)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            } else {
                Text("Not enough comparable games to name a strength yet.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                Text("Chessanto waits for at least three games on both sides of a comparison and a meaningful accuracy difference.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
    }

    private func accuracySection(_ snapshot: PlayerBriefSnapshot) -> some View {
        Card {
            SectionHeader(title: "Accuracy history")
            if snapshot.accuracyHistory.count >= 4 {
                Chart(snapshot.accuracyHistory) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(DesignColors.accentText)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(DesignColors.accentText)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .accessibilityLabel(accuracySummary(snapshot))
                Text(accuracySummary(snapshot))
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            } else {
                Text(snapshot.collectionMilestone ?? "Analyze more games to reveal a trend.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func phaseSection(_ snapshot: PlayerBriefSnapshot) -> some View {
        if !snapshot.phasePerformance.isEmpty {
            Card {
                SectionHeader(title: "Costly moves by game third")
                HStack {
                    tableHeader("Segment").frame(maxWidth: .infinity, alignment: .leading)
                    tableHeader("Costly").frame(width: 56, alignment: .trailing)
                    tableHeader("Moves").frame(width: 56, alignment: .trailing)
                    tableHeader("Rate").frame(width: 56, alignment: .trailing)
                }
                ForEach(snapshot.phasePerformance) { phase in
                    HStack {
                        Text(phase.phase.rawValue)
                            .font(.dsBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(phase.costlyMoves)")
                            .font(.dsNotation)
                            .frame(width: 56, alignment: .trailing)
                        Text("\(phase.moves)")
                            .font(.dsNotation)
                            .frame(width: 56, alignment: .trailing)
                        Text(phase.costlyMoveRate, format: .percent.precision(.fractionLength(0)))
                            .font(.dsNotation)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .foregroundStyle(DesignColors.textPrimary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(phase.phase.rawValue), \(phase.costlyMoves) costly moves from \(phase.moves) moves"
                    )
                }
                Text("Segments are equal thirds of game length, not formal opening, middlegame, and endgame analysis.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
    }

    private func classificationSection(_ snapshot: PlayerBriefSnapshot) -> some View {
        Card {
            SectionHeader(title: "Move distribution")
            ForEach(MoveClassification.allCases, id: \.rawValue) { classification in
                if let count = snapshot.classificationCounts[classification], count > 0 {
                    HStack(spacing: DesignSpacing.sm) {
                        ClassificationChip(classification: classification)
                        Spacer()
                        Text("\(count)")
                            .font(.dsNotation)
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var lessonSection: some View {
        Card {
            SectionHeader(title: "Review queue")
            Text(dueTrainingCards.isEmpty ? "No review due now" : "\(dueTrainingCardCount) positions ready")
                .font(.dsBody.weight(.semibold))
                .foregroundStyle(DesignColors.textPrimary)
            Text(nextLessonSupportingText)
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
        }
    }

    @ViewBuilder
    private func motifSection(_ snapshot: PlayerBriefSnapshot) -> some View {
        if !snapshot.motifEvidence.isEmpty {
            Card {
                SectionHeader(title: "Repeated signals")
                ForEach(snapshot.motifEvidence) { motif in
                    HStack {
                        Text(motif.motif.label)
                            .font(.dsBody)
                        Spacer()
                        Text("\(motif.count) / \(motif.games) games")
                            .font(.dsNotation)
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                }
            }
        }
    }

    private func contextSection(_ snapshot: PlayerBriefSnapshot) -> some View {
        Card {
            SectionHeader(title: "Context")
            if snapshot.contextObservations.isEmpty {
                Text("Not enough games to compare contexts yet.")
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
            } else {
                ForEach(snapshot.contextObservations) { observation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(observation.title).font(.dsBody.weight(.semibold))
                        Text(observation.detail)
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                }
            }
            breakdownSection("Color", values: snapshot.colorPerformance)
            breakdownSection("Time control", values: snapshot.timeControlPerformance)
            if !snapshot.openingPerformance.isEmpty {
                breakdownSection("Recurring openings", values: snapshot.openingPerformance)
            }
        }
    }

    private func breakdownSection(
        _ title: String,
        values: [PerformanceBreakdown]
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(title)
                .font(.dsSecondary.weight(.semibold))
                .foregroundStyle(DesignColors.textSecondary)
            ForEach(values) { value in
                HStack {
                    Text(value.label)
                        .font(.dsBody)
                        .lineLimit(1)
                    Spacer()
                    Text("\(String(format: "%.0f", value.averageAccuracy))%  \(value.games)g  \(value.wins)W \(value.draws)D \(value.losses)L")
                        .font(.dsNotation)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(.dsSecondary.weight(.semibold))
            .foregroundStyle(DesignColors.textSecondary)
    }

    private func coverageLine(_ snapshot: PlayerBriefSnapshot) -> some View {
        HStack {
            Text("\(snapshot.coverage.analyzed) matched analyzed games")
            Text("·")
            Text("\(snapshot.coverage.imported) games imported")
            if let milestone = snapshot.collectionMilestone {
                Text("·")
                Text(milestone)
            }
        }
        .font(.dsSecondary)
        .foregroundStyle(DesignColors.textSecondary)
        .padding(.top, DesignSpacing.xs)
    }

    private var nextLessonSupportingText: String {
        if let nextTrainingDueDate {
            return "Next review: \(nextTrainingDueDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Practice cards appear after an analyzed game contains selected key moments."
    }

    private func costlyMoveCount(_ snapshot: PlayerBriefSnapshot) -> Int {
        (snapshot.classificationCounts[.mistake] ?? 0)
            + (snapshot.classificationCounts[.blunder] ?? 0)
            + (snapshot.classificationCounts[.missedWin] ?? 0)
    }

    private func accuracySummary(_ snapshot: PlayerBriefSnapshot) -> String {
        guard let first = snapshot.accuracyHistory.first,
            let last = snapshot.accuracyHistory.last
        else {
            return "No accuracy history."
        }
        return "Accuracy history across \(snapshot.accuracyHistory.count) games, from \(String(format: "%.0f", first.accuracy)) percent to \(String(format: "%.0f", last.accuracy)) percent."
    }

    private func startPractice(cards: [TrainingCardRecord]) {
        guard let gameID = cards.first?.gameId else { return }
        onOpenPractice(gameID) {
            let username = library.chessComUsername.trimmingCharacters(in: .whitespaces)
            let queue = try await library.store.trainingQueueSnapshot(
                username: username.isEmpty ? nil : username
            )
            return queue.dueCards.isEmpty ? queue.fallbackCards : queue.dueCards
        }
    }

    private func load() async {
        guard library.isChessComAccountConfirmed else {
            snapshot = nil
            dueTrainingCards = []
            dueTrainingCardCount = 0
            fallbackTrainingCards = []
            nextTrainingDueDate = nil
            errorMessage = nil
            isLoading = false
            return
        }

        let username = library.chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let games = library.games
        let store = library.store
        isLoading = true
        snapshot = nil
        errorMessage = nil

        let loadTask = Task.detached(priority: .userInitiated) {
            try await Self.buildSnapshot(
                games: games,
                username: username,
                store: store
            )
        }

        do {
            let builtSnapshot = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            try Task.checkCancellation()
            snapshot = builtSnapshot
            let queue = try await store.trainingQueueSnapshot(
                username: username.isEmpty ? nil : username
            )
            try Task.checkCancellation()
            dueTrainingCards = queue.dueCards
            dueTrainingCardCount = queue.dueCount
            fallbackTrainingCards = queue.fallbackCards
            nextTrainingDueDate = queue.nextDueDate
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    nonisolated private static func buildSnapshot(
        games: [GameRecord],
        username: String,
        store: GameStore
    ) async throws -> PlayerBriefSnapshot {
        var analyzedGames: [AnalyzedPlayerGame] = []
        for game in games {
            try Task.checkCancellation()
            guard let gameID = game.id else { continue }
            let isWhite = game.white.caseInsensitiveCompare(username) == .orderedSame
            let isBlack = game.black.caseInsensitiveCompare(username) == .orderedSame
            guard isWhite || isBlack else { continue }

            let rows = try await store.analysis(gameId: gameID)
            guard !rows.isEmpty,
                let input = ReportBuilding.buildInput(
                    record: game,
                    analysisRows: rows,
                    chessComUsername: username
                ),
                let report = ReportBuilder.build(
                    input: input,
                    openingBook: OpeningBook.shared
                )
            else {
                continue
            }

            analyzedGames.append(
                summary(
                    game: game,
                    gameID: gameID,
                    isWhite: isWhite,
                    input: input,
                    report: report
                )
            )
        }
        return PlayerInsightBuilder.build(
            games: analyzedGames,
            importedGameCount: games.count
        )
    }

    nonisolated private static func summary(
        game: GameRecord,
        gameID: Int64,
        isWhite: Bool,
        input: ReportInput,
        report: GameReport
    ) -> AnalyzedPlayerGame {
        let counts = isWhite
            ? report.whiteClassificationCounts
            : report.blackClassificationCounts
        let classificationCounts = Dictionary(
            uniqueKeysWithValues: counts.map { ($0.classification, $0.count) }
        )
        let phaseErrors = phaseErrors(input: input, userIsWhite: isWhite)
        var motifs: [PlayerMotif: Int] = [:]
        for moment in report.keyMoments where moment.evalSwing.moverIsWhite == isWhite {
            if moment.punishment != nil { motifs[.loosePiece, default: 0] += 1 }
            if moment.missedMate != nil { motifs[.missedMate, default: 0] += 1 }
            if moment.allowedMate != nil { motifs[.allowedMate, default: 0] += 1 }
        }

        return AnalyzedPlayerGame(
            id: gameID,
            date: game.playedAt ?? game.importedAt,
            accuracy: isWhite ? report.whiteAccuracy : report.blackAccuracy,
            isWhite: isWhite,
            result: playerResult(raw: game.result, userIsWhite: isWhite),
            timeClass: timeClass(raw: game.timeControl),
            opening: report.opening?.name,
            classificationCounts: classificationCounts,
            phaseErrors: phaseErrors,
            motifs: motifs
        )
    }

    nonisolated private static func phaseErrors(
        input: ReportInput,
        userIsWhite: Bool
    ) -> [PlayerGamePhase: PhaseErrorCount] {
        let moveCount = input.plies.count - 1
        guard moveCount > 0 else { return [:] }
        let playedUCIs = input.plies.dropFirst().compactMap(\.playedUCI)
        guard playedUCIs.count == moveCount else { return [:] }
        let movers = (1...moveCount).map { input.moverIsWhite(atPly: $0) }
        let evaluations = input.plies.compactMap { $0.rank1?.rank1Evaluation }
        guard evaluations.count == input.plies.count else { return [:] }
        let classifications = MoveClassifier.classify(
            positionEvaluations: evaluations,
            playedUCIs: playedUCIs,
            whiteToMove: movers
        )

        var totals: [PlayerGamePhase: PhaseErrorCount] = [:]
        for index in classifications.indices where movers[index] == userIsWhite {
            let phaseIndex = min(index * 3 / max(moveCount, 1), 2)
            let phase = PlayerGamePhase.allCases[phaseIndex]
            let existing = totals[phase] ?? PhaseErrorCount(moves: 0, costlyMoves: 0)
            let classification = classifications[index]
            let isCostly =
                classification == .mistake
                || classification == .blunder
                || classification == .missedWin
            totals[phase] = PhaseErrorCount(
                moves: existing.moves + 1,
                costlyMoves: existing.costlyMoves + (isCostly ? 1 : 0)
            )
        }
        return totals
    }

    nonisolated private static func playerResult(
        raw: String?,
        userIsWhite: Bool
    ) -> PlayerGameResult {
        switch raw {
        case "1-0": return userIsWhite ? .win : .loss
        case "0-1": return userIsWhite ? .loss : .win
        case "1/2-1/2": return .draw
        default: return .unknown
        }
    }

    nonisolated private static func timeClass(raw: String?) -> PlayerTimeClass {
        guard let raw, !raw.isEmpty else { return .other }
        if raw.contains("/") { return .daily }
        let seconds = raw.split(separator: "+").first.flatMap { Int($0) } ?? 0
        switch seconds {
        case ..<180: return .bullet
        case 180..<600: return .blitz
        case 600..<1800: return .rapid
        default: return .other
        }
    }
}
