import AnalysisKit
import Foundation

enum PlayerMotif: String, Sendable, Hashable {
    case loosePiece
    case missedMate
    case allowedMate

    var label: String {
        switch self {
        case .loosePiece: return "Loose pieces"
        case .missedMate: return "Missed forced mates"
        case .allowedMate: return "Allowed forced mates"
        }
    }

    var focusTitle: String {
        switch self {
        case .loosePiece: return "Loose pieces appeared repeatedly"
        case .missedMate: return "Forced mates were missed repeatedly"
        case .allowedMate: return "Opponent threats decided repeated moments"
        }
    }
}

enum PlayerGameResult: Sendable, Equatable {
    case win
    case draw
    case loss
    case unknown
}

enum PlayerTimeClass: String, Sendable, Hashable, CaseIterable {
    case bullet = "Bullet"
    case blitz = "Blitz"
    case rapid = "Rapid"
    case daily = "Daily"
    case other = "Other"
}

enum PlayerGamePhase: String, Sendable, Hashable, CaseIterable {
    case early = "First third"
    case middle = "Middle third"
    case late = "Final third"
}

struct PhaseErrorCount: Sendable, Equatable {
    let moves: Int
    let costlyMoves: Int

    var rate: Double {
        guard moves > 0 else { return 0 }
        return Double(costlyMoves) / Double(moves)
    }
}

struct AnalyzedPlayerGame: Sendable, Equatable {
    let id: Int64
    let date: Date
    let accuracy: Double
    let isWhite: Bool
    let result: PlayerGameResult
    let timeClass: PlayerTimeClass
    let opening: String?
    let classificationCounts: [MoveClassification: Int]
    let phaseErrors: [PlayerGamePhase: PhaseErrorCount]
    let motifs: [PlayerMotif: Int]
}

struct PlayerObservation: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
}

struct PlayerAccuracyPoint: Sendable, Equatable, Identifiable {
    let id: Int64
    let date: Date
    let accuracy: Double
}

struct PerformanceBreakdown: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let games: Int
    let averageAccuracy: Double
    let wins: Int
    let draws: Int
    let losses: Int
}

struct MotifEvidence: Sendable, Equatable, Identifiable {
    let motif: PlayerMotif
    let count: Int
    let games: Int
    var id: PlayerMotif { motif }
}

struct PhasePerformance: Sendable, Equatable, Identifiable {
    let phase: PlayerGamePhase
    let moves: Int
    let costlyMoves: Int
    var id: PlayerGamePhase { phase }
    var costlyMoveRate: Double {
        guard moves > 0 else { return 0 }
        return Double(costlyMoves) / Double(moves)
    }
}

struct InsightCoverage: Sendable, Equatable {
    let analyzed: Int
    let imported: Int
}

struct PlayerBriefSnapshot: Sendable, Equatable {
    let averageAccuracy: Double
    let focus: PlayerObservation
    let strength: PlayerObservation?
    let contextObservations: [PlayerObservation]
    let collectionMilestone: String?
    let accuracyHistory: [PlayerAccuracyPoint]
    let classificationCounts: [MoveClassification: Int]
    let motifEvidence: [MotifEvidence]
    let phasePerformance: [PhasePerformance]
    let colorPerformance: [PerformanceBreakdown]
    let timeControlPerformance: [PerformanceBreakdown]
    let openingPerformance: [PerformanceBreakdown]
    let coverage: InsightCoverage
}

enum PlayerInsightBuilder {
    static func build(
        games: [AnalyzedPlayerGame],
        importedGameCount: Int
    ) -> PlayerBriefSnapshot {
        let sortedGames = games.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }
        let averageAccuracy = average(sortedGames.map(\.accuracy))
        let motifEvidence = motifEvidence(for: sortedGames)
        let classificationCounts = aggregateClassifications(sortedGames)
        let focus = focus(
            motifs: motifEvidence,
            classifications: classificationCounts,
            analyzedGameCount: sortedGames.count
        )
        let colorPerformance = breakdown(
            groups: Dictionary(grouping: sortedGames) { $0.isWhite ? "White" : "Black" }
        )
        let timeControlPerformance = breakdown(
            groups: Dictionary(grouping: sortedGames) { $0.timeClass.rawValue }
        )
        let openingPerformance = breakdown(
            groups: Dictionary(grouping: sortedGames.compactMap { game in
                game.opening.map { ($0, game) }
            }) { $0.0 },
            value: { $0.1 }
        ).filter { $0.games >= 2 }
        let contextObservations = comparativeObservations(
            color: colorPerformance,
            timeControls: timeControlPerformance
        )
        let strength = supportedStrength(
            color: colorPerformance,
            timeControls: timeControlPerformance
        )

        return PlayerBriefSnapshot(
            averageAccuracy: averageAccuracy,
            focus: focus,
            strength: strength,
            contextObservations: Array(contextObservations.prefix(3)),
            collectionMilestone: sortedGames.count < 4
                ? "Analyze \(4 - sortedGames.count) more game\(4 - sortedGames.count == 1 ? "" : "s") to reveal your first accuracy trend."
                : nil,
            accuracyHistory: sortedGames.map {
                PlayerAccuracyPoint(id: $0.id, date: $0.date, accuracy: $0.accuracy)
            },
            classificationCounts: classificationCounts,
            motifEvidence: motifEvidence,
            phasePerformance: phasePerformance(for: sortedGames),
            colorPerformance: colorPerformance,
            timeControlPerformance: timeControlPerformance,
            openingPerformance: openingPerformance,
            coverage: InsightCoverage(
                analyzed: sortedGames.count,
                imported: importedGameCount
            )
        )
    }

    private static func focus(
        motifs: [MotifEvidence],
        classifications: [MoveClassification: Int],
        analyzedGameCount: Int
    ) -> PlayerObservation {
        if let motif = motifs
            .filter({ $0.games >= 2 })
            .sorted(by: {
                if $0.count == $1.count { return $0.motif.rawValue < $1.motif.rawValue }
                return $0.count > $1.count
            })
            .first
        {
            return PlayerObservation(
                id: "motif-\(motif.motif.rawValue)",
                title: motif.motif.focusTitle,
                detail: "This appeared in \(motif.count) selected mistakes across \(motif.games) analyzed games."
            )
        }

        let costlyMoves =
            (classifications[.mistake] ?? 0)
            + (classifications[.blunder] ?? 0)
            + (classifications[.missedWin] ?? 0)
        if costlyMoves > 0 {
            return PlayerObservation(
                id: "costly-moves",
                title: "\(costlyMoves) costly move\(costlyMoves == 1 ? "" : "s") found in this sample",
                detail: "\(costlyMoves) mistakes, blunders, or missed wins were classified across \(analyzedGameCount) analyzed game\(analyzedGameCount == 1 ? "" : "s")."
            )
        }

        return PlayerObservation(
            id: "baseline",
            title: "Build your player baseline",
            detail: "Analyze more of your own games so Chessanto can identify a repeated pattern."
        )
    }

    private static func motifEvidence(for games: [AnalyzedPlayerGame]) -> [MotifEvidence] {
        PlayerMotif.allCases.map { motif in
            let matchingGames = games.filter { ($0.motifs[motif] ?? 0) > 0 }
            return MotifEvidence(
                motif: motif,
                count: matchingGames.reduce(0) { $0 + ($1.motifs[motif] ?? 0) },
                games: matchingGames.count
            )
        }.filter { $0.count > 0 }
    }

    private static func aggregateClassifications(
        _ games: [AnalyzedPlayerGame]
    ) -> [MoveClassification: Int] {
        var totals: [MoveClassification: Int] = [:]
        for game in games {
            for (classification, count) in game.classificationCounts {
                totals[classification, default: 0] += count
            }
        }
        return totals
    }

    private static func phasePerformance(
        for games: [AnalyzedPlayerGame]
    ) -> [PhasePerformance] {
        PlayerGamePhase.allCases.compactMap { phase in
            let counts = games.compactMap { $0.phaseErrors[phase] }
            let moves = counts.reduce(0) { $0 + $1.moves }
            guard moves > 0 else { return nil }
            return PhasePerformance(
                phase: phase,
                moves: moves,
                costlyMoves: counts.reduce(0) { $0 + $1.costlyMoves }
            )
        }
    }

    private static func breakdown(
        groups: [String: [AnalyzedPlayerGame]]
    ) -> [PerformanceBreakdown] {
        breakdown(groups: groups, value: { $0 })
    }

    private static func breakdown<T>(
        groups: [String: [T]],
        value: (T) -> AnalyzedPlayerGame
    ) -> [PerformanceBreakdown] {
        groups.map { label, values in
            let games = values.map(value)
            return PerformanceBreakdown(
                id: label,
                label: label,
                games: games.count,
                averageAccuracy: average(games.map(\.accuracy)),
                wins: games.filter { $0.result == .win }.count,
                draws: games.filter { $0.result == .draw }.count,
                losses: games.filter { $0.result == .loss }.count
            )
        }.sorted {
            if $0.games == $1.games { return $0.label < $1.label }
            return $0.games > $1.games
        }
    }

    private static func comparativeObservations(
        color: [PerformanceBreakdown],
        timeControls: [PerformanceBreakdown]
    ) -> [PlayerObservation] {
        var observations: [PlayerObservation] = []
        if let white = color.first(where: { $0.label == "White" }),
            let black = color.first(where: { $0.label == "Black" }),
            white.games >= 3,
            black.games >= 3
        {
            observations.append(
                PlayerObservation(
                    id: "color",
                    title: "Accuracy by color",
                    detail: "\(rounded(white.averageAccuracy))% as White across \(white.games) games and \(rounded(black.averageAccuracy))% as Black across \(black.games) games."
                )
            )
        }

        let supportedTimeControls = timeControls.filter { $0.games >= 3 }
        if supportedTimeControls.count >= 2,
            let best = supportedTimeControls.max(by: { $0.averageAccuracy < $1.averageAccuracy }),
            let lowest = supportedTimeControls.min(by: { $0.averageAccuracy < $1.averageAccuracy })
        {
            observations.append(
                PlayerObservation(
                    id: "time-control",
                    title: "Accuracy by time control",
                    detail: "\(best.label) averaged \(rounded(best.averageAccuracy))% across \(best.games) games; \(lowest.label) averaged \(rounded(lowest.averageAccuracy))% across \(lowest.games) games."
                )
            )
        }
        return observations
    }

    private static func supportedStrength(
        color: [PerformanceBreakdown],
        timeControls: [PerformanceBreakdown]
    ) -> PlayerObservation? {
        if let white = color.first(where: { $0.label == "White" }),
            let black = color.first(where: { $0.label == "Black" }),
            white.games >= 3,
            black.games >= 3,
            abs(white.averageAccuracy - black.averageAccuracy) >= 5
        {
            let stronger = white.averageAccuracy > black.averageAccuracy ? white : black
            let comparison = stronger.label == "White" ? black : white
            return PlayerObservation(
                id: "strength-color",
                title: "More accurate as \(stronger.label)",
                detail: "\(rounded(stronger.averageAccuracy))% across \(stronger.games) games, compared with \(rounded(comparison.averageAccuracy))% as \(comparison.label) across \(comparison.games) games."
            )
        }

        let supportedTimeControls = timeControls.filter { $0.games >= 3 }
        if supportedTimeControls.count >= 2,
            let strongest = supportedTimeControls.max(by: {
                $0.averageAccuracy < $1.averageAccuracy
            }),
            let comparison = supportedTimeControls.min(by: {
                $0.averageAccuracy < $1.averageAccuracy
            }),
            strongest.averageAccuracy - comparison.averageAccuracy >= 5
        {
            return PlayerObservation(
                id: "strength-time-control",
                title: "Strongest in \(strongest.label.lowercased())",
                detail: "\(rounded(strongest.averageAccuracy))% across \(strongest.games) games, compared with \(rounded(comparison.averageAccuracy))% in \(comparison.label.lowercased()) across \(comparison.games) games."
            )
        }

        return nil
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func rounded(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

extension PlayerMotif: CaseIterable {}
