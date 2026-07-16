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
}
