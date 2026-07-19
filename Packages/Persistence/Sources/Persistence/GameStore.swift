import Foundation
import GRDB

public enum LibraryCommand: Sendable, Equatable {
    case setPinned(Set<Int64>, Bool)
    case setFavorite(Set<Int64>, Bool)
    case moveToRecentlyDeleted(Set<Int64>)
    case restore(Set<Int64>)
    case deletePermanently(Set<Int64>)

    var gameIDs: Set<Int64> {
        switch self {
        case .setPinned(let gameIDs, _),
            .setFavorite(let gameIDs, _),
            .moveToRecentlyDeleted(let gameIDs),
            .restore(let gameIDs),
            .deletePermanently(let gameIDs):
            return gameIDs
        }
    }
}

public struct LibraryMutationResult: Sendable, Equatable {
    public let affectedIDs: Set<Int64>
    public let staleIDs: Set<Int64>

    public init(affectedIDs: Set<Int64>, staleIDs: Set<Int64>) {
        self.affectedIDs = affectedIDs
        self.staleIDs = staleIDs
    }
}

public enum PersistenceError: Error, LocalizedError {
    case databaseSetupFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .databaseSetupFailed(let error):
            return "Couldn't open the local database: \(error.localizedDescription)"
        }
    }
}

/// Owns the app's single SQLite database and exposes typed access to it.
/// All persistence in Chessanto goes through this type.
public final class GameStore: Sendable {
    private static let activeTrainingCardsCTE = """
        WITH activeTrainingCard AS (
            SELECT tc.*, g.white AS gameWhite, g.black AS gameBlack
            FROM trainingCard tc
            JOIN game g ON g.id = tc.gameId
            WHERE g.deletedAt IS NULL
        )
        """

    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        do {
            let queue = try DatabaseQueue(path: path)
            try Schema.migrator().migrate(queue)
            self.dbQueue = queue
        } catch {
            throw PersistenceError.databaseSetupFailed(error)
        }
    }

    /// In-memory store, useful for tests and previews.
    public init() throws {
        do {
            let queue = try DatabaseQueue()
            try Schema.migrator().migrate(queue)
            self.dbQueue = queue
        } catch {
            throw PersistenceError.databaseSetupFailed(error)
        }
    }

    public static func defaultStore() throws -> GameStore {
        try defaultStore(environment: ProcessInfo.processInfo.environment)
    }

    static func defaultStore(environment: [String: String]) throws -> GameStore {
        if environment["CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE"] == "1",
            let overridePath = environment["CHESSANTO_DATABASE_PATH"],
            !overridePath.isEmpty
        {
            let databaseURL = URL(fileURLWithPath: overridePath)
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try GameStore(path: databaseURL.path)
        }

        if environment["XCTestConfigurationFilePath"]?.isEmpty == false {
            let runID = environment["CHESSANTO_TEST_RUN_ID"]
                ?? String(ProcessInfo.processInfo.processIdentifier)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChessantoTests", isDirectory: true)
                .appendingPathComponent(runID, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return try GameStore(
                path: directory
                    .appendingPathComponent("chessanto.sqlite")
                    .path
            )
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("Chessanto", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("chessanto.sqlite")
        return try GameStore(path: dbURL.path)
    }

    @discardableResult
    public func save(_ game: GameRecord) throws -> GameRecord {
        try dbQueue.write { db in
            var mutableGame = game
            try mutableGame.save(db)
            return mutableGame
        }
    }

    public func allGames() throws -> [GameRecord] {
        try dbQueue.read { db in
            try GameRecord
                .filter(Column("deletedAt") == nil)
                .order(
                    Column("pinnedAt").desc,
                    Column("playedAt").desc,
                    Column("importedAt").desc
                )
                .fetchAll(db)
        }
    }

    public func recentlyDeletedGames() throws -> [GameRecord] {
        try dbQueue.read { db in
            try GameRecord
                .filter(Column("deletedAt") != nil)
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    public func game(id: Int64) throws -> GameRecord? {
        try dbQueue.read { db in
            try GameRecord.fetchOne(db, key: id)
        }
    }

    /// Applies one library command atomically across every requested game.
    /// Missing or inapplicable IDs are reported as stale instead of causing
    /// a partially completed batch.
    @discardableResult
    public func perform(_ command: LibraryCommand) throws -> LibraryMutationResult {
        let requestedIDs = command.gameIDs
        guard !requestedIDs.isEmpty else {
            return LibraryMutationResult(affectedIDs: [], staleIDs: [])
        }

        return try dbQueue.write { db in
            let records = try GameRecord
                .filter(requestedIDs.contains(Column("id")))
                .fetchAll(db)
            var affectedIDs: Set<Int64> = []

            for var record in records {
                guard let id = record.id else { continue }
                switch command {
                case .setPinned(_, let pinned):
                    guard record.deletedAt == nil else { continue }
                    record.pinnedAt = pinned ? Date() : nil
                    try record.update(db)
                case .setFavorite(_, let favorite):
                    guard record.deletedAt == nil else { continue }
                    record.isFavorite = favorite
                    try record.update(db)
                case .moveToRecentlyDeleted:
                    guard record.deletedAt == nil else { continue }
                    record.deletedAt = Date()
                    try record.update(db)
                case .restore:
                    guard record.deletedAt != nil else { continue }
                    record.deletedAt = nil
                    try record.update(db)
                case .deletePermanently:
                    guard record.deletedAt != nil else { continue }
                    try record.delete(db)
                }
                affectedIDs.insert(id)
            }

            return LibraryMutationResult(
                affectedIDs: affectedIDs,
                staleIDs: requestedIDs.subtracting(affectedIDs)
            )
        }
    }

    /// PGNs already imported, keyed by chess.com game URL, so re-fetching
    /// an archive doesn't create duplicates.
    public func importedSourceURLs() throws -> Set<String> {
        try dbQueue.read { db in
            let urls = try GameRecord
                .filter(Column("sourceURL") != nil)
                .fetchAll(db)
                .compactMap(\.sourceURL)
            return Set(urls)
        }
    }

    /// Replaces all analysis rows for a single ply of a game in one
    /// transaction (delete-first, since the unique key on
    /// (gameId, plyIndex, multiPVRank, depth) would otherwise throw on
    /// blind re-insert of the same depth).
    public func saveAnalysis(_ records: [AnalysisRecord], gameId: Int64, plyIndex: Int) async throws {
        try await dbQueue.write { db in
            try AnalysisRecord
                .filter(Column("gameId") == gameId && Column("plyIndex") == plyIndex)
                .deleteAll(db)
            for var record in records {
                try record.insert(db)
            }
        }
    }

    public func analysis(gameId: Int64) async throws -> [AnalysisRecord] {
        try await dbQueue.read { db in
            try AnalysisRecord
                .filter(Column("gameId") == gameId)
                .order(Column("plyIndex"), Column("multiPVRank"))
                .fetchAll(db)
        }
    }

    /// Plies that have been analyzed, i.e. have a rank-1 row.
    public func analyzedPlyIndices(gameId: Int64) async throws -> Set<Int> {
        try await dbQueue.read { db in
            let plies = try AnalysisRecord
                .filter(Column("gameId") == gameId && Column("multiPVRank") == 1)
                .fetchAll(db)
                .map(\.plyIndex)
            return Set(plies)
        }
    }

    /// Plies whose rank-one analysis records were produced at an equal or
    /// stronger quality than the explicit request.
    ///
    /// Legacy rows have no provenance and are deliberately insufficient.
    public func analyzedPlyIndices(
        gameId: Int64,
        satisfying requestedQuality: AnalysisQualityProvenance
    ) async throws -> Set<Int> {
        try await dbQueue.read { db in
            let rows = try AnalysisRecord
                .filter(
                    Column("gameId") == gameId
                        && Column("multiPVRank") == 1
                )
                .fetchAll(db)
            return Set(
                rows.lazy
                    .filter {
                        AnalysisProvenance.canReuse(
                            storedQuality: $0.qualityPreset,
                            requestedQuality: requestedQuality
                        )
                    }
                    .map(\.plyIndex)
            )
        }
    }

    /// IDs of games that have at least one saved analysis row - used by the
    /// sidebar's "analyzed" marker. A single distinct-gameId query, not a
    /// per-game round trip.
    public func analyzedGameIDs() async throws -> Set<Int64> {
        try await dbQueue.read { db in
            let ids = try Int64.fetchAll(
                db, sql: "SELECT DISTINCT gameId FROM analysis"
            )
            return Set(ids)
        }
    }

    public func deleteAnalysis(gameId: Int64) async throws {
        _ = try await dbQueue.write { db in
            try AnalysisRecord
                .filter(Column("gameId") == gameId)
                .deleteAll(db)
        }
    }

    // MARK: - Variations

    /// Inserts a single played variation move. Called as each move is
    /// played, not batched, so a crash/quit never loses more than the move
    /// in flight.
    @discardableResult
    public func insertVariationMove(_ record: VariationRecord) async throws -> VariationRecord {
        try await dbQueue.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
            return mutableRecord
        }
    }

    /// All variation rows for a game, in insertion order (parents are
    /// always inserted before their children, so this order is also a
    /// valid replay/reconstruction order).
    public func variations(gameId: Int64) async throws -> [VariationRecord] {
        try await dbQueue.read { db in
            try VariationRecord
                .filter(Column("gameId") == gameId)
                .order(Column("id"))
                .fetchAll(db)
        }
    }

    /// Deletes a variation move and every move that descends from it
    /// (`ON DELETE CASCADE` on `parentVariationId` handles the subtree).
    public func deleteVariation(id: Int64) async throws {
        _ = try await dbQueue.write { db in
            try VariationRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Chat

    /// Inserts a single chat message. Called as each message is sent or
    /// received, not batched, matching the crash-safety pattern used for
    /// variation moves and analysis rows.
    @discardableResult
    public func insertChatMessage(_ record: ChatMessageRecord) async throws -> ChatMessageRecord {
        try await dbQueue.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
            return mutableRecord
        }
    }

    /// All chat messages for a game, in insertion order.
    public func chatMessages(gameId: Int64) async throws -> [ChatMessageRecord] {
        try await dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("gameId") == gameId)
                .order(Column("id"))
                .fetchAll(db)
        }
    }

    /// The Clear-chat affordance: removes every chat message for a game.
    public func deleteChatMessages(gameId: Int64) async throws {
        _ = try await dbQueue.write { db in
            try ChatMessageRecord
                .filter(Column("gameId") == gameId)
                .deleteAll(db)
        }
    }

    // MARK: - Training

    @discardableResult
    public func upsertTrainingCard(_ record: TrainingCardRecord) async throws -> TrainingCardRecord {
        try await dbQueue.write { db in
            if let existing = try TrainingCardRecord
                .filter(Column("gameId") == record.gameId && Column("sourcePly") == record.sourcePly)
                .fetchOne(db)
            {
                var updated = record
                updated.id = existing.id
                updated.dueAt = existing.dueAt
                updated.consecutiveSuccesses = existing.consecutiveSuccesses
                updated.masteryState = existing.masteryState
                updated.lastResult = existing.lastResult
                updated.createdAt = existing.createdAt
                updated.updatedAt = Date()
                try updated.update(db)
                return updated
            }

            var inserted = record
            try inserted.insert(db)
            return inserted
        }
    }

    public func trainingCards(gameId: Int64) async throws -> [TrainingCardRecord] {
        try await dbQueue.read { db in
            try TrainingCardRecord
                .filter(Column("gameId") == gameId)
                .order(Column("sourcePly"))
                .fetchAll(db)
        }
    }

    /// Replaces one game's generated card set in a single database write.
    /// Existing scheduling progress is retained for matching source plies;
    /// cards no longer produced by the audited report are removed.
    @discardableResult
    public func reconcileTrainingCards(
        gameId: Int64,
        candidates: [TrainingCardRecord]
    ) async throws -> [TrainingCardRecord] {
        try Task.checkCancellation()
        guard candidates.allSatisfy({ $0.gameId == gameId }) else {
            throw TrainingCardReconciliationError.mismatchedGame
        }
        guard Set(candidates.map(\.sourcePly)).count == candidates.count else {
            throw TrainingCardReconciliationError.duplicateSourcePly
        }
        try candidates.forEach { try $0.validateForReconciliation() }

        return try await dbQueue.write { db in
            try Task.checkCancellation()
            let existingCards = try TrainingCardRecord
                .filter(Column("gameId") == gameId)
                .fetchAll(db)
            let existingByPly = Dictionary(
                uniqueKeysWithValues: existingCards.map { ($0.sourcePly, $0) }
            )
            let candidatePlies = Set(candidates.map(\.sourcePly))

            for existing in existingCards where !candidatePlies.contains(existing.sourcePly) {
                _ = try existing.delete(db)
            }

            var reconciled: [TrainingCardRecord] = []
            for candidate in candidates.sorted(by: { $0.sourcePly < $1.sourcePly }) {
                if let existing = existingByPly[candidate.sourcePly] {
                    let answerIsUnchanged =
                        candidate.preMoveFEN == existing.preMoveFEN
                        && candidate.sideToMove == existing.sideToMove
                        && candidate.bestMoveUCI == existing.bestMoveUCI
                    let contentIsUnchanged =
                        answerIsUnchanged
                        && candidate.rankedLinesJSON == existing.rankedLinesJSON
                        && candidate.classification == existing.classification
                        && candidate.themesJSON == existing.themesJSON
                        && candidate.explanation == existing.explanation
                    if contentIsUnchanged {
                        reconciled.append(existing)
                        continue
                    }

                    var updated = candidate
                    updated.id = existing.id
                    updated.createdAt = existing.createdAt
                    updated.updatedAt = Date()
                    if answerIsUnchanged {
                        updated.dueAt = existing.dueAt
                        updated.consecutiveSuccesses = existing.consecutiveSuccesses
                        updated.masteryState = existing.masteryState
                        updated.lastResult = existing.lastResult
                    } else {
                        updated.consecutiveSuccesses = 0
                        updated.masteryState = "new"
                        updated.lastResult = nil
                        if let cardId = existing.id {
                            _ = try TrainingAttemptRecord
                                .filter(Column("cardId") == cardId)
                                .deleteAll(db)
                        }
                    }
                    try updated.update(db)
                    reconciled.append(updated)
                } else {
                    var inserted = candidate
                    try inserted.insert(db)
                    reconciled.append(inserted)
                }
            }
            return reconciled
        }
    }

    public func dueTrainingCards(now: Date = Date(), limit: Int = 20) async throws -> [TrainingCardRecord] {
        try await dbQueue.read { db in
            try TrainingCardRecord.fetchAll(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT tc.*
                    FROM activeTrainingCard tc
                    WHERE tc.dueAt <= ?
                    ORDER BY tc.dueAt, tc.updatedAt
                    LIMIT ?
                    """,
                arguments: [now, limit]
            )
        }
    }

    public func anyTrainingCards(limit: Int = 20) async throws -> [TrainingCardRecord] {
        try await dbQueue.read { db in
            try TrainingCardRecord.fetchAll(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT tc.*
                    FROM activeTrainingCard tc
                    ORDER BY tc.updatedAt DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
        }
    }

    public func nextTrainingDueDate(after now: Date = Date()) async throws -> Date? {
        try await dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT MIN(tc.dueAt)
                    FROM activeTrainingCard tc
                    WHERE tc.dueAt > ?
                    """,
                arguments: [now]
            )
        }
    }

    /// A consistent lesson-queue read for Dashboard. When a username is
    /// configured, only games where that player appears are included.
    public func trainingQueueSnapshot(
        username: String?,
        now: Date = Date(),
        limit: Int = 20
    ) async throws -> TrainingQueueSnapshot {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await dbQueue.read { db in
            if let trimmedUsername, !trimmedUsername.isEmpty {
                let playerArguments: StatementArguments = [
                    trimmedUsername,
                    trimmedUsername
                ]
                let dueCards = try TrainingCardRecord.fetchAll(
                    db,
                    sql: Self.activeTrainingCardsCTE + """
                        SELECT tc.*
                        FROM activeTrainingCard tc
                        WHERE (tc.gameWhite COLLATE NOCASE = ? OR tc.gameBlack COLLATE NOCASE = ?)
                          AND tc.dueAt <= ?
                        ORDER BY tc.dueAt, tc.updatedAt
                        LIMIT ?
                        """,
                    arguments: playerArguments + [now, limit]
                )
                let dueCount = try Int.fetchOne(
                    db,
                    sql: Self.activeTrainingCardsCTE + """
                        SELECT COUNT(*)
                        FROM activeTrainingCard tc
                        WHERE (tc.gameWhite COLLATE NOCASE = ? OR tc.gameBlack COLLATE NOCASE = ?)
                          AND tc.dueAt <= ?
                        """,
                    arguments: playerArguments + [now]
                ) ?? 0
                let fallbackCards = try TrainingCardRecord.fetchAll(
                    db,
                    sql: Self.activeTrainingCardsCTE + """
                        SELECT tc.*
                        FROM activeTrainingCard tc
                        WHERE (tc.gameWhite COLLATE NOCASE = ? OR tc.gameBlack COLLATE NOCASE = ?)
                        ORDER BY tc.updatedAt DESC
                        LIMIT ?
                        """,
                    arguments: playerArguments + [limit]
                )
                let nextDueDate = try Date.fetchOne(
                    db,
                    sql: Self.activeTrainingCardsCTE + """
                        SELECT MIN(tc.dueAt)
                        FROM activeTrainingCard tc
                        WHERE (tc.gameWhite COLLATE NOCASE = ? OR tc.gameBlack COLLATE NOCASE = ?)
                          AND tc.dueAt > ?
                        """,
                    arguments: playerArguments + [now]
                )
                return TrainingQueueSnapshot(
                    dueCards: dueCards,
                    dueCount: dueCount,
                    fallbackCards: fallbackCards,
                    nextDueDate: nextDueDate
                )
            }

            let dueCards = try TrainingCardRecord.fetchAll(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT tc.*
                    FROM activeTrainingCard tc
                    WHERE tc.dueAt <= ?
                    ORDER BY tc.dueAt, tc.updatedAt
                    LIMIT ?
                    """,
                arguments: [now, limit]
            )
            let dueCount = try Int.fetchOne(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT COUNT(*)
                    FROM activeTrainingCard tc
                    WHERE tc.dueAt <= ?
                    """,
                arguments: [now]
            ) ?? 0
            let fallbackCards = try TrainingCardRecord.fetchAll(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT tc.*
                    FROM activeTrainingCard tc
                    ORDER BY tc.updatedAt DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            let nextDueDate = try Date.fetchOne(
                db,
                sql: Self.activeTrainingCardsCTE + """
                    SELECT MIN(tc.dueAt)
                    FROM activeTrainingCard tc
                    WHERE tc.dueAt > ?
                    """,
                arguments: [now]
            )
            return TrainingQueueSnapshot(
                dueCards: dueCards,
                dueCount: dueCount,
                fallbackCards: fallbackCards,
                nextDueDate: nextDueDate
            )
        }
    }

    @discardableResult
    public func saveTrainingAttempt(_ attempt: TrainingAttemptRecord, updatedCard: TrainingCardRecord) async throws -> TrainingAttemptRecord {
        try await dbQueue.write { db in
            var card = updatedCard
            card.updatedAt = Date()
            try card.update(db)

            var inserted = attempt
            try inserted.insert(db)
            return inserted
        }
    }

    public func trainingAttempts(cardId: Int64) async throws -> [TrainingAttemptRecord] {
        try await dbQueue.read { db in
            try TrainingAttemptRecord
                .filter(Column("cardId") == cardId)
                .order(Column("id"))
                .fetchAll(db)
        }
    }

    // MARK: - User profile

    /// The single user profile row, creating a default one on first access.
    public func userProfile() throws -> UserProfileRecord {
        try dbQueue.write { db in
            if let existing = try UserProfileRecord.fetchOne(db, key: 1) {
                return existing
            }
            var fresh = UserProfileRecord()
            try fresh.insert(db)
            return fresh
        }
    }

    @discardableResult
    public func saveUserProfile(_ profile: UserProfileRecord) throws -> UserProfileRecord {
        try dbQueue.write { db in
            var mutableProfile = profile
            try mutableProfile.save(db)
            return mutableProfile
        }
    }
}
