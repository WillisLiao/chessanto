import GRDB

/// Database migrations for Chessanto's local store. Add new migrations by
/// registering them here in order; never edit a migration that has already
/// shipped.
enum Schema {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_games") { db in
            try db.create(table: "game") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("source", .text).notNull()
                t.column("sourceURL", .text)
                t.column("pgn", .text).notNull()
                t.column("white", .text).notNull()
                t.column("black", .text).notNull()
                t.column("whiteRating", .integer)
                t.column("blackRating", .integer)
                t.column("result", .text)
                t.column("timeControl", .text)
                t.column("playedAt", .datetime)
                t.column("importedAt", .datetime).notNull()
            }

            try db.create(table: "analysis") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull()
                    .references("game", onDelete: .cascade)
                t.column("plyIndex", .integer).notNull()
                t.column("fen", .text).notNull()
                t.column("depth", .integer).notNull()
                t.column("scoreCentipawns", .integer)
                t.column("mateIn", .integer)
                t.column("principalVariation", .text).notNull()
                t.column("multiPVRank", .integer).notNull()
                t.uniqueKey(["gameId", "plyIndex", "multiPVRank", "depth"])
            }

            try db.create(table: "variation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull()
                    .references("game", onDelete: .cascade)
                t.column("parentPlyIndex", .integer).notNull()
                t.column("moveSAN", .text).notNull()
                t.column("orderIndex", .integer).notNull()
                t.column("parentVariationId", .integer)
                    .references("variation", onDelete: .cascade)
            }

            try db.create(table: "chatMessage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull()
                    .references("game", onDelete: .cascade)
                t.column("plyIndex", .integer).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "userProfile") { t in
                t.column("id", .integer).notNull().primaryKey()
                t.column("chessComUsername", .text)
                t.column("ratingBand", .text).notNull().defaults(to: "adaptive")
                t.column("coachModel", .text)
                t.column("coachEnabled", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2_chatMessageSource") { db in
            try db.alter(table: "chatMessage") { t in
                t.add(column: "source", .text)
            }
        }

        migrator.registerMigration("v3_m8Settings") { db in
            try db.alter(table: "userProfile") { t in
                t.add(column: "hasCompletedOnboarding", .boolean).notNull().defaults(to: false)
                t.add(column: "analysisQuality", .text).notNull().defaults(to: "standard")
                t.add(column: "boardTheme", .text).notNull().defaults(to: "classic")
            }
        }

        return migrator
    }
}
