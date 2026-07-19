import AnalysisKit
import Foundation
import Testing
@testable import Chessanto

struct PlayerInsightBuilderTests {
    @Test func recurringAuditedMotifBecomesThePrimaryFocusWithEvidence() {
        let games = [
            summary(id: 1, accuracy: 61, motifs: [.loosePiece: 2]),
            summary(id: 2, accuracy: 72, motifs: [.loosePiece: 1])
        ]

        let brief = PlayerInsightBuilder.build(games: games, importedGameCount: 5)

        #expect(brief.focus.title == "Loose pieces appeared repeatedly")
        #expect(brief.focus.detail == "This appeared in 3 selected mistakes across 2 analyzed games.")
        #expect(brief.coverage == InsightCoverage(analyzed: 2, imported: 5))
    }

    @Test func sparseColorDataReportsFactsWithoutCallingThemStrengths() {
        let games = [
            summary(id: 1, accuracy: 81, isWhite: true),
            summary(id: 2, accuracy: 54, isWhite: false)
        ]

        let brief = PlayerInsightBuilder.build(games: games, importedGameCount: 2)

        #expect(brief.strength == nil)
        #expect(brief.contextObservations.isEmpty)
        #expect(brief.collectionMilestone == "Analyze 2 more games to reveal your first accuracy trend.")
    }

    @Test func supportedColorDifferenceBecomesAnEvidenceThresholdedStrength() {
        let games = [
            summary(id: 1, accuracy: 84, isWhite: true),
            summary(id: 2, accuracy: 82, isWhite: true),
            summary(id: 3, accuracy: 80, isWhite: true),
            summary(id: 4, accuracy: 68, isWhite: false),
            summary(id: 5, accuracy: 70, isWhite: false),
            summary(id: 6, accuracy: 69, isWhite: false)
        ]

        let brief = PlayerInsightBuilder.build(games: games, importedGameCount: 6)

        #expect(brief.strength?.title == "More accurate as White")
        #expect(brief.strength?.detail == "82% across 3 games, compared with 69% as Black across 3 games.")
    }

    private func summary(
        id: Int64,
        accuracy: Double,
        isWhite: Bool = true,
        motifs: [PlayerMotif: Int] = [:]
    ) -> AnalyzedPlayerGame {
        AnalyzedPlayerGame(
            id: id,
            date: Date(timeIntervalSince1970: Double(id)),
            accuracy: accuracy,
            isWhite: isWhite,
            result: .draw,
            timeClass: .rapid,
            opening: "Queen's Pawn Game",
            classificationCounts: [.mistake: 1],
            phaseErrors: [:],
            motifs: motifs
        )
    }
}
