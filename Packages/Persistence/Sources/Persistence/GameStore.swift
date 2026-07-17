import Foundation
import GRDB

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
                .order(Column("playedAt").desc, Column("importedAt").desc)
                .fetchAll(db)
        }
    }

    public func game(id: Int64) throws -> GameRecord? {
        try dbQueue.read { db in
            try GameRecord.fetchOne(db, key: id)
        }
    }

    public func deleteGame(id: Int64) throws {
        _ = try dbQueue.write { db in
            try GameRecord.deleteOne(db, key: id)
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
}
