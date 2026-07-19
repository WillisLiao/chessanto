import Foundation
import GRDB
import Testing
@testable import Persistence

struct PersistenceTests {
    @Test func defaultStoreUsesLaunchDatabaseOverride() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chessanto-default-store-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
        }

        let store = try GameStore.defaultStore(environment: [
            "CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE": "1",
            "CHESSANTO_DATABASE_PATH": databaseURL.path
        ])
        _ = try store.save(GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "QA",
            black: "Fixture"
        ))

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(try store.allGames().map(\.white) == ["QA"])
    }

    @Test func trainingReconciliationErrorsExplainTheInvalidPracticeData() {
        #expect(
            TrainingCardReconciliationError.invalidFEN.localizedDescription
                == "A practice card contained an invalid chess position."
        )
        #expect(
            TrainingCardReconciliationError.invalidBestMove.localizedDescription
                == "A practice card's best move was not legal in its chess position."
        )
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

    private func validTrainingCard(
        gameId: Int64,
        sourcePly: Int,
        bestMoveUCI: String = "e2e4",
        dueAt: Date = Date()
    ) -> TrainingCardRecord {
        TrainingCardRecord(
            gameId: gameId,
            sourcePly: sourcePly,
            preMoveFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            sideToMove: "white",
            bestMoveUCI: bestMoveUCI,
            rankedLinesJSON: """
                [{"rank":1,"scoreCentipawns":0,"mateIn":null,"principalVariationUCI":["\(bestMoveUCI)"],"depth":10}]
                """,
            classification: "mistake",
            dueAt: dueAt
        )
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

        _ = try store.perform(.moveToRecentlyDeleted([gameId]))
        _ = try store.perform(.deletePermanently([gameId]))

        let fetched = try await store.analysis(gameId: gameId)
        #expect(fetched.isEmpty)
    }

    @Test func recentlyDeletedGamesCanBeRestoredWithTheirAnalysis() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "f0", depth: 10, principalVariation: "", multiPVRank: 1)],
            gameId: gameId,
            plyIndex: 0
        )

        let deletion = try store.perform(.moveToRecentlyDeleted([gameId]))

        #expect(deletion.affectedIDs == [gameId])
        #expect(try store.allGames().isEmpty)
        #expect(try store.recentlyDeletedGames().map(\.id) == [gameId])
        #expect(try await store.analysis(gameId: gameId).count == 1)

        _ = try store.perform(.restore([gameId]))

        #expect(try store.allGames().map(\.id) == [gameId])
        #expect(try store.recentlyDeletedGames().isEmpty)
        #expect(try await store.analysis(gameId: gameId).count == 1)
    }

    @Test func pinAndFavoriteAreIndependentBulkOrganizationStates() throws {
        let store = try GameStore()
        let firstID = try makeGame(store)
        let secondID = try makeGame(store)

        _ = try store.perform(.setPinned([firstID], true))
        _ = try store.perform(.setFavorite([firstID, secondID], true))

        let games = try store.allGames()
        #expect(games.first?.id == firstID)
        #expect(games.first?.pinnedAt != nil)
        #expect(games.map(\.isFavorite) == [true, true])

        _ = try store.perform(.setPinned([firstID], false))

        let updatedFirst = try store.game(id: firstID)
        #expect(updatedFirst?.pinnedAt == nil)
        #expect(updatedFirst?.isFavorite == true)
    }

    @Test func permanentDeletionOnlyRemovesGamesAlreadyInRecentlyDeleted() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        try await store.saveAnalysis(
            [AnalysisRecord(gameId: gameId, plyIndex: 0, fen: "f0", depth: 10, principalVariation: "", multiPVRank: 1)],
            gameId: gameId,
            plyIndex: 0
        )

        let refused = try store.perform(.deletePermanently([gameId]))

        #expect(refused.affectedIDs.isEmpty)
        #expect(refused.staleIDs == [gameId])
        #expect(try store.game(id: gameId) != nil)

        _ = try store.perform(.moveToRecentlyDeleted([gameId]))
        let deleted = try store.perform(.deletePermanently([gameId]))

        #expect(deleted.affectedIDs == [gameId])
        #expect(try store.game(id: gameId) == nil)
        #expect(try await store.analysis(gameId: gameId).isEmpty)
    }

    @Test func recentlyDeletedGamesAreExcludedFromThePracticeQueue() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        _ = try await store.upsertTrainingCard(
            validTrainingCard(
                gameId: gameId,
                sourcePly: 1,
                dueAt: Date(timeIntervalSince1970: 1)
            )
        )

        #expect(try await store.trainingQueueSnapshot(username: nil).dueCount == 1)

        _ = try store.perform(.moveToRecentlyDeleted([gameId]))

        let queue = try await store.trainingQueueSnapshot(username: nil)
        #expect(queue.dueCount == 0)
        #expect(queue.dueCards.isEmpty)
        #expect(queue.fallbackCards.isEmpty)
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

        _ = try store.perform(.moveToRecentlyDeleted([gameId]))
        _ = try store.perform(.deletePermanently([gameId]))

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

    @Test func reconcilingTrainingCardsRemovesObsoleteSourcePlies() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        _ = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 1,
            preMoveFEN: "obsolete-fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake"
        ))
        _ = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 18,
            preMoveFEN: "current-fen",
            sideToMove: "black",
            bestMoveUCI: "d8e7",
            rankedLinesJSON: "[]",
            classification: "inaccuracy"
        ))

        _ = try await store.reconcileTrainingCards(
            gameId: gameId,
            candidates: [
                validTrainingCard(gameId: gameId, sourcePly: 18)
            ]
        )

        let fetched = try await store.trainingCards(gameId: gameId)
        #expect(fetched.map(\.sourcePly) == [18])
    }

    @Test func reconcilingChangedTrainingAnswerResetsProgressAndAttempts() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        let original = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: gameId,
            sourcePly: 18,
            preMoveFEN: "old-fen",
            sideToMove: "black",
            bestMoveUCI: "d8e7",
            rankedLinesJSON: "[]",
            classification: "inaccuracy"
        ))
        var learned = original
        learned.dueAt = Date(timeIntervalSince1970: 50_000)
        learned.consecutiveSuccesses = 2
        learned.masteryState = "review"
        learned.lastResult = "strong"
        _ = try await store.saveTrainingAttempt(
            TrainingAttemptRecord(
                cardId: original.id!,
                attemptedUCI: "d8e7",
                evaluationLossCentipawns: 0,
                outcome: "strong",
                hintCount: 0
            ),
            updatedCard: learned
        )
        let resetDueAt = Date(timeIntervalSince1970: 2_000)

        let reconciled = try await store.reconcileTrainingCards(
            gameId: gameId,
            candidates: [
                validTrainingCard(
                    gameId: gameId,
                    sourcePly: 18,
                    bestMoveUCI: "d2d4",
                    dueAt: resetDueAt
                )
            ]
        )

        #expect(reconciled[0].id == original.id)
        #expect(reconciled[0].dueAt == resetDueAt)
        #expect(reconciled[0].consecutiveSuccesses == 0)
        #expect(reconciled[0].masteryState == "new")
        #expect(reconciled[0].lastResult == nil)
        #expect(try await store.trainingAttempts(cardId: original.id!).isEmpty)
    }

    @Test func invalidTrainingCandidateRollsBackWholeReconciliation() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        _ = try await store.upsertTrainingCard(
            validTrainingCard(gameId: gameId, sourcePly: 1)
        )
        var invalid = validTrainingCard(gameId: gameId, sourcePly: 3)
        invalid.rankedLinesJSON = """
            [{"rank":1,"principalVariationUCI":["e2e4"]}]
            """

        await #expect(throws: TrainingCardReconciliationError.self) {
            _ = try await store.reconcileTrainingCards(
                gameId: gameId,
                candidates: [
                    validTrainingCard(gameId: gameId, sourcePly: 2),
                    invalid
                ]
            )
        }

        #expect(try await store.trainingCards(gameId: gameId).map(\.sourcePly) == [1])
    }

    @Test func unchangedTrainingReconciliationIsIdempotent() async throws {
        let store = try GameStore()
        let gameId = try makeGame(store)
        let first = try await store.reconcileTrainingCards(
            gameId: gameId,
            candidates: [validTrainingCard(gameId: gameId, sourcePly: 2)]
        )
        let firstPersisted = try await store.trainingCards(gameId: gameId)

        let second = try await store.reconcileTrainingCards(
            gameId: gameId,
            candidates: [validTrainingCard(gameId: gameId, sourcePly: 2)]
        )

        #expect(second[0].id == first[0].id)
        #expect(second[0].updatedAt == firstPersisted[0].updatedAt)
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

    @Test func trainingQueueSnapshotExcludesGamesThatDoNotMatchTheUsername() async throws {
        let store = try GameStore()
        let matchingGameId = try makeGame(store)
        let unmatchedGameId = try #require(try store.save(GameRecord(
            source: .pgnImport,
            pgn: "1. d4 d5",
            white: "Carol",
            black: "Dave"
        )).id)
        let now = Date(timeIntervalSince1970: 10_000)
        _ = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: matchingGameId,
            sourcePly: 2,
            preMoveFEN: "matching",
            sideToMove: "black",
            bestMoveUCI: "e7e5",
            rankedLinesJSON: "[]",
            classification: "mistake",
            dueAt: now.addingTimeInterval(-10)
        ))
        _ = try await store.upsertTrainingCard(TrainingCardRecord(
            gameId: unmatchedGameId,
            sourcePly: 2,
            preMoveFEN: "unmatched",
            sideToMove: "black",
            bestMoveUCI: "d7d5",
            rankedLinesJSON: "[]",
            classification: "mistake",
            dueAt: now.addingTimeInterval(-10)
        ))

        let snapshot = try await store.trainingQueueSnapshot(
            username: "aLiCe",
            now: now,
            limit: 20
        )

        #expect(snapshot.dueCards.map(\.gameId) == [matchingGameId])
        #expect(snapshot.dueCount == 1)
        #expect(snapshot.fallbackCards.map(\.gameId) == [matchingGameId])
        #expect(snapshot.nextDueDate == nil)
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

        _ = try store.perform(.moveToRecentlyDeleted([gameId]))
        _ = try store.perform(.deletePermanently([gameId]))

        let cards = try await store.trainingCards(gameId: gameId)
        let attempts = try await store.trainingAttempts(cardId: card.id!)
        #expect(cards.isEmpty)
        #expect(attempts.isEmpty)
    }

    @Test func userProfileDefaultsOnFirstAccess() throws {
        let store = try GameStore()
        let profile = try store.userProfile()
        #expect(profile.chessComUsername == nil)
        #expect(profile.isChessComAccountConfirmed == false)
        #expect(profile.ratingBand == "adaptive")
        #expect(profile.coachEnabled == false)
    }

    @Test func userProfileRoundTripsAndUpdatesInPlace() throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.chessComUsername = "hikaru"
        profile.isChessComAccountConfirmed = true
        try store.saveUserProfile(profile)

        let refetched = try store.userProfile()
        #expect(refetched.chessComUsername == "hikaru")
        #expect(refetched.isChessComAccountConfirmed == true)
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

    @Test func v5AddsTrainingQueueIndexes() throws {
        let store = try GameStore()
        let indexNames = try store.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'index'
                    ORDER BY name
                    """
            )
        }

        #expect(indexNames.contains("trainingCard_dueAt_updatedAt"))
        #expect(indexNames.contains("trainingAttempt_cardId_attemptedAt"))
    }

    @Test func v5MigrationPreservesExistingV4TrainingDataAndForeignKeys() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v4_trainingLoop")
        let timestamp = Date(timeIntervalSince1970: 20_000)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO game (
                        id, source, pgn, white, black, importedAt
                    ) VALUES (
                        41, 'pgnImport', '1. e4 e5', 'Learner', 'Opponent', ?
                    )
                    """,
                arguments: [timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO trainingCard (
                        id, gameId, sourcePly, preMoveFEN, sideToMove,
                        bestMoveUCI, rankedLinesJSON, classification,
                        themesJSON, explanation, dueAt,
                        consecutiveSuccesses, masteryState, lastResult,
                        createdAt, updatedAt
                    ) VALUES (
                        51, 41, 1, ?, 'white',
                        'e2e4', ?, 'mistake',
                        '["Opening"]', 'Claim the center.', ?,
                        2, 'review', 'strong',
                        ?, ?
                    )
                    """,
                arguments: [
                    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                    """
                    [{"rank":1,"scoreCentipawns":20,"mateIn":null,"principalVariationUCI":["e2e4"],"depth":16}]
                    """,
                    timestamp,
                    timestamp,
                    timestamp
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO trainingAttempt (
                        id, cardId, attemptedUCI, attemptedAt,
                        evaluationLossCentipawns, outcome, hintCount
                    ) VALUES (
                        61, 51, 'e2e4', ?, 0, 'strong', 1
                    )
                    """,
                arguments: [timestamp]
            )
        }

        try Schema.migrator().migrate(queue)

        let result = try queue.read { db in
            let card = try TrainingCardRecord.fetchOne(db, key: 51)
            let attempt = try TrainingAttemptRecord.fetchOne(db, key: 61)
            let indexNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'index'
                    ORDER BY name
                    """
            )
            let migrations = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
            let foreignKeyViolations = try Row.fetchAll(
                db,
                sql: "PRAGMA foreign_key_check"
            )
            return (
                card,
                attempt,
                indexNames,
                migrations,
                foreignKeyViolations
            )
        }

        #expect(result.0?.gameId == 41)
        #expect(result.0?.consecutiveSuccesses == 2)
        #expect(result.0?.masteryState == "review")
        #expect(result.1?.cardId == 51)
        #expect(result.1?.hintCount == 1)
        #expect(result.2.contains("trainingCard_dueAt_updatedAt"))
        #expect(result.2.contains("trainingAttempt_cardId_attemptedAt"))
        #expect(result.3.last == "v7_confirmedChessComIdentity")
        #expect(result.4.isEmpty)
    }

    @Test func v6MigrationPreservesExistingGamesAndAddsSafeOrganizationDefaults() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v5_trainingIndexes")
        let timestamp = Date(timeIntervalSince1970: 30_000)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO game (
                        id, source, pgn, white, black, importedAt
                    ) VALUES (
                        71, 'pgnImport', '1. d4 d5', 'Learner', 'Opponent', ?
                    )
                    """,
                arguments: [timestamp]
            )
        }

        try Schema.migrator().migrate(queue)

        let result = try queue.read { db in
            let game = try GameRecord.fetchOne(db, key: 71)
            let columns = try db.columns(in: "game").map(\.name)
            let foreignKeyViolations = try Row.fetchAll(
                db,
                sql: "PRAGMA foreign_key_check"
            )
            return (game, columns, foreignKeyViolations)
        }

        #expect(result.0?.white == "Learner")
        #expect(result.0?.pinnedAt == nil)
        #expect(result.0?.isFavorite == false)
        #expect(result.0?.deletedAt == nil)
        #expect(result.1.contains("pinnedAt"))
        #expect(result.1.contains("isFavorite"))
        #expect(result.1.contains("deletedAt"))
        #expect(result.2.isEmpty)
    }

    @Test func v7MigrationRequiresLegacyChessComUsernamesToBeConfirmed() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v6_gameOrganization")

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO userProfile (
                        id, chessComUsername, ratingBand, coachEnabled,
                        hasCompletedOnboarding, analysisQuality, boardTheme
                    ) VALUES (
                        1, 'legacy-name', 'adaptive', 0, 1, 'standard', 'classic'
                    )
                    """
            )
        }

        try Schema.migrator().migrate(queue)

        let profile = try queue.read { db in
            try UserProfileRecord.fetchOne(db, key: 1)
        }

        #expect(profile?.chessComUsername == "legacy-name")
        #expect(profile?.isChessComAccountConfirmed == false)
    }
}
