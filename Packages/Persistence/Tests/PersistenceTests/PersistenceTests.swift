import Foundation
import GRDB
import Testing
@testable import Persistence

struct PersistenceTests {
    @Test func placeholder() {
        #expect(true)
    }

    private func makeGame(_ store: GameStore) throws -> Int64 {
        let saved = try store.save(GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "Alice",
            black: "Bob"
        ))
        return saved.id!
    }

    @Test func analysisRoundTrips() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        let records = [
            AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "startpos", depth: 15, scoreCentipawns: 32, principalVariation: "e2e4 e7e5", multiPVRank: 1),
            AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "startpos", depth: 15, scoreCentipawns: 20, principalVariation: "d2d4 d7d5", multiPVRank: 2)
        ]
        try await store.saveAnalysis(records, gameId: gameId, plyIndex: 0)

        let fetched = try await store.analysis(gameId: gameId)
        #expect(fetched.count == 2)
        #expect(fetched[0].multiPVRank == 1)
        #expect(fetched[0].scoreCentipawns == 32)
        #expect(fetched[1].multiPVRank == 2)
    }

    @Test func saveAnalysisReplacesExistingRowsAtSamePly() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 3, fen: "f1", depth: 10, scoreCentipawns: 5, principalVariation: "a", multiPVRank: 1)],
            gameId: gameId, plyIndex: 3
        )
        // Re-analyze at a deeper depth: delete-first replacement, not a unique-key throw.
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 3, fen: "f1", depth: 20, scoreCentipawns: 8, principalVariation: "b", multiPVRank: 1)],
            gameId: gameId, plyIndex: 3
        )

        let fetched = try await store.analysis(gameId: gameId)
        #expect(fetched.count == 1)
        #expect(fetched[0].depth == 20)
        #expect(fetched[0].scoreCentipawns == 8)
    }

    @Test func analyzedPlyIndicesTracksRankOneRowsOnly() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        try await store.saveAnalysis(
            [
                AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "f0", depth: 10, principalVariation: "", multiPVRank: 1),
                AnalysisRecord(gameId: gameId, plyIndex: 1, fen: "f1", depth: 10, principalVariation: "", multiPVRank: 2)
            ],
            gameId: gameId, plyIndex: 0
        )
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 1, fen: "f1", depth: 10, principalVariation: "", multiPVRank: 2)],
            gameId: gameId, plyIndex: 1
        )

        let analyzed = try await store.analyzedPlyIndices(gameId: gameId)
        #expect(analyzed == [0])
    }

    @Test func deleteAnalysisRemovesAllRowsForGame() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "f0", depth: 10, principalVariation: "", multiPVRank: 1)],
            gameId: gameId, plyIndex: 0
        )

        try await store.deleteAnalysis(gameId: gameId)

        let fetched = try await store.analysis(gameId: gameId)
        #expect(fetched.isEmpty)
    }

    @Test func deletingGameCascadesToAnalysis() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "f0", depth: 10, principalVariation: "", multiPVRank: 1)],
            gameId: gameId, plyIndex: 0
        )

        try store.deleteGame(id: gameId)

        let fetched = try await store.analysis(gameId: gameId)
        #expect(fetched.isEmpty)
    }

    @Test func variationMovesRoundTripInInsertionOrder() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        let root = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Nf3", orderIndex: 0)
        )
        let child = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Nc6", orderIndex: 0, parentVariationId: root.id)
        )
        _ = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Bb5", orderIndex: 0, parentVariationId: child.id)
        )

        let fetched = try await store.variations(gameId: gameId)
        #expect(fetched.map(\.moveSAN) == ["Nf3", "Nc6", "Bb5"])
    }

    @Test func deletingVariationCascadesToSubtreeButNotSiblings() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        let root = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Nf3", orderIndex: 0)
        )
        let child = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Nc6", orderIndex: 0, parentVariationId: root.id)
        )
        let grandchild = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Bb5", orderIndex: 0, parentVariationId: child.id)
        )
        let sibling = try await store.insertVariationMove(
            VariationRecord(gameId: gameId, parentPlyIndex: 2, moveSAN: "Bc4", orderIndex: 1)
        )

        try await store.deleteVariation(id: child.id!)

        let remaining = try await store.variations(gameId: gameId)
        #expect(Set(remaining.map(\.id)) == [root.id, sibling.id])
        _ = grandchild // deleted via cascade, no longer fetchable
    }

    @Test func chatMessagesRoundTripInInsertionOrder() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        _ = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 4, role: "user", content: "What if I played Nf3?")
        )
        _ = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 4, role: "assistant", content: "Nf3 develops...", source: "coach")
        )

        let fetched = try await store.chatMessages(gameId: gameId)
        #expect(fetched.count == 2)
        #expect(fetched[0].role == "user")
        #expect(fetched[1].role == "assistant")
    }

    @Test func chatMessageSourceIsNilOnUserRowsAndSetOnAssistantRows() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        let userRow = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 0, role: "user", content: "hello")
        )
        let assistantRow = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 0, role: "assistant", content: "hi", source: "precheck")
        )

        #expect(userRow.source == nil)
        #expect(assistantRow.source == "precheck")
    }

    @Test func deleteChatMessagesRemovesAllRowsForGame() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        _ = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 0, role: "user", content: "hello")
        )

        try await store.deleteChatMessages(gameId: gameId)

        let fetched = try await store.chatMessages(gameId: gameId)
        #expect(fetched.isEmpty)
    }

    @Test func deletingGameCascadesToChatMessages() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        _ = try await store.insertChatMessage(
            ChatMessageRecord(gameId: gameId, plyIndex: 0, role: "user", content: "hello")
        )

        try store.deleteGame(id: gameId)

        let fetched = try await store.chatMessages(gameId: gameId)
        #expect(fetched.isEmpty)
    }

    @Test func trainingCardsDeduplicateBySourceGameAndPly() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)

        let first = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 3,
            preMoveFEN: "fen-a",
            sideToMove: "white",
            bestMoveUCI: "g1f3",
            rankedLinesJSON: "[]",
            classification: "mistake",
            explanation: "First explanation"
        ))
        let second = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 3,
            preMoveFEN: "fen-b",
            sideToMove: "white",
            bestMoveUCI: "g1f3",
            rankedLinesJSON: "[]",
            classification: "blunder",
            explanation: "Updated explanation"
        ))

        let fetched = try await store.trainingCards(gameId: gameId)
        #expect(fetched.count == 1)
        #expect(second.id == first.id)
        #expect(fetched[0].preMoveFEN == "fen-b")
        #expect(fetched[0].classification == "blunder")
        #expect(fetched[0].explanation == "Updated explanation")
    }

    @Test func dueTrainingCardsAndAttemptsRoundTrip() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        let now = Date()

        var card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake",
            dueAt: now.addingTimeInterval(-60)
        ))
        card.masteryState = "review"
        card.consecutiveSuccesses = 1
        card.dueAt = now.addingTimeInterval(86_400)
        let attempt = try await store.saveTrainingAttempt(
            TrainingAttemptRecord(
                cardId: card.id!,
                attemptedUCI: "e2e4",
                evaluationLossCentipawns: 0,
                outcome: "strong",
                hintCount: 1
            ),
            updatedCard: card
        )

        let due = try await store.dueTrainingCards(now: now)
        let attempts = try await store.trainingAttempts(cardId: card.id!)
        let nextDue = try await store.nextTrainingDueDate(after: now)
        let updated = try await store.trainingCards(gameId: gameId)

        #expect(due.isEmpty)
        #expect(attempts.map { $0.id } == [attempt.id])
        #expect(attempts[0].hintCount == 1)
        #expect(updated[0].masteryState == "review")
        #expect(updated[0].consecutiveSuccesses == 1)
        #expect(nextDue != nil)
    }

    @Test func deletingGameCascadesToTrainingCardsAndAttempts() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        let card = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake"
        ))
        _ = try await store.saveTrainingAttempt(
            TrainingAttemptRecord(cardId: card.id!, attemptedUCI: "e2e4", outcome: "strong", hintCount: 0),
            updatedCard: card
        )

        try store.deleteGame(id: gameId)

        let cards = try await store.trainingCards(gameId: gameId)
        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(cards.isEmpty)
        #expect(attempts.isEmpty)
    }

    @Test func userProfileDefaultsOnFirstAccess() throws {
        let store = try GameStore()
        let profile = try store.userProfile()
        #expect(profile.chessComUsername == nil)
        #expect(profile.ratingBand == "adaptive")
        #expect(profile.coachEnabled == false)
    }

    @Test func userProfileRoundTripsAndUpdatesInPlace() throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.chessComUsername = "hikaru"
        try store.saveUserProfile(profile)

        let refetched = try store.userProfile()
        #expect(refetched.chessComUsername == "hikaru")
        #expect(refetched.id == 1)
    }

    @Test func userProfileDefaultsForM8ColumnsOnFirstAccess() throws {
        let store = try GameStore()
        let profile = try store.userProfile()
        #expect(profile.hasCompletedOnboarding == false)
        #expect(profile.analysisQuality == "standard")
        #expect(profile.boardTheme == "classic")
    }

    @Test func m8ColumnsRoundTrip() throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.hasCompletedOnboarding = true
        profile.analysisQuality = "deep"
        profile.boardTheme = "green"
        try store.saveUserProfile(profile)

        let refetched = try store.userProfile()
        #expect(refetched.hasCompletedOnboarding == true)
        #expect(refetched.analysisQuality == "deep")
        #expect(refetched.boardTheme == "green")
    }

    @Test func v3MigrationAppliesOnAV2ShapedStoreWithDefaultsAndDataIntact() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v2_chatMessageSource")

        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO userProfile (id, chessComUsername, ratingBand, coachModel, coachEnabled) VALUES (1, 'hikaru', 'adaptive', 'qwen3:0.6b', 1)"
            )
        }

        try Schema.migrator().migrate(queue)

        let profile = try queue.read { db in
            try UserProfileRecord.fetchOne(db, key: 1)
        }
        #expect(profile?.chessComUsername == "hikaru")
        #expect(profile?.coachEnabled == true)
        #expect(profile?.hasCompletedOnboarding == false)
        #expect(profile?.analysisQuality == "standard")
        #expect(profile?.boardTheme == "classic")
    }

    @Test func v4MigrationAppliesOnAV3ShapedStoreAndKeepsDataIntact() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v3_m8Settings")

        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO game (id, source, pgn, white, black, importedAt) VALUES (10, 'pgnImport', '1. e4 e5', 'Alice', 'Bob', ?)",
                arguments: [Date()]
            )
        }

        try Schema.migrator().migrate(queue)

        let game = try queue.read { db in
            try GameRecord.fetchOne(db, key: 10)
        }
        let trainingColumns = try queue.read { db in
            try db.columns(in: "trainingCard").map(\.name)
        }
        #expect(game?.white == "Alice")
        #expect(trainingColumns.contains("sourcePly"))
        #expect(trainingColumns.contains("masteryState"))
    }
}
