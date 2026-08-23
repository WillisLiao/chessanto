import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("Analysis provenance")
struct AnalysisProvenanceTests {
    @Test("stored quality satisfies only equal or weaker requests")
    func storedQualitySatisfiesOnlyEqualOrWeakerRequests() {
        #expect(
            AnalysisProvenance.canReuse(
                storedQuality: .standard,
                requestedQuality: .fast
            )
        )
        #expect(
            AnalysisProvenance.canReuse(
                storedQuality: .standard,
                requestedQuality: .standard
            )
        )
        #expect(
            !AnalysisProvenance.canReuse(
                storedQuality: .standard,
                requestedQuality: .deep
            )
        )
        #expect(
            !AnalysisProvenance.canReuse(
                storedQuality: nil,
                requestedQuality: .fast
            )
        )
    }

    @Test("v9 migration preserves legacy analysis with unknown provenance")
    func v9MigrationPreservesLegacyAnalysisWithUnknownProvenance() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v8_moveNotationStyle")
        let timestamp = Date(timeIntervalSince1970: 30_000)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO game (
                        id, source, pgn, white, black, importedAt
                    ) VALUES (
                        91, 'pgnImport', '1. Nf3', 'Learner', 'Opponent', ?
                    )
                    """,
                arguments: [timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO analysis (
                        id, gameId, plyIndex, fen, depth,
                        scoreCentipawns, principalVariation, multiPVRank
                    ) VALUES (
                        92, 91, 0, 'start', 18, 22, 'g1f3', 1
                    )
                    """
            )
        }

        try Schema.migrator().migrate(queue)

        let result = try queue.read { db in
            let record = try AnalysisRecord.fetchOne(db, key: 92)
            let columns = try db.columns(in: "analysis").map(\.name)
            let migrations = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
            return (record, columns, migrations)
        }

        #expect(result.0?.qualityPreset == nil)
        #expect(result.0?.analyzedAt == nil)
        #expect(result.0?.engineIdentifier == nil)
        #expect(result.1.contains("qualityPreset"))
        #expect(result.1.contains("analyzedAt"))
        #expect(result.1.contains("engineIdentifier"))
        #expect(result.2.last == "v12_spacedRepetition")
    }

    @Test("only sufficient analyzed plies are reusable")
    func onlySufficientAnalyzedPliesAreReusable() async throws {
        let store = try GameStore()
        let game = try store.save(
            GameRecord(
                source: .pgnImport,
                pgn: "1. Nf3",
                white: "Learner",
                black: "Opponent"
            )
        )
        let gameID = try #require(game.id)
        try await store.saveAnalysis(
            [
                AnalysisRecord(
                    gameId: gameID,
                    plyIndex: 0,
                    fen: "start",
                    depth: 12,
                    scoreCentipawns: 18,
                    principalVariation: "g1f3",
                    multiPVRank: 1,
                    qualityPreset: .fast,
                    analyzedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            gameId: gameID,
            plyIndex: 0
        )
        try await store.saveAnalysis(
            [
                AnalysisRecord(
                    gameId: gameID,
                    plyIndex: 1,
                    fen: "after",
                    depth: 20,
                    scoreCentipawns: 22,
                    principalVariation: "g8f6",
                    multiPVRank: 1,
                    qualityPreset: .deep,
                    analyzedAt: Date(timeIntervalSince1970: 101)
                ),
            ],
            gameId: gameID,
            plyIndex: 1
        )

        let standard = try await store.analyzedPlyIndices(
            gameId: gameID,
            satisfying: .standard
        )
        let deep = try await store.analyzedPlyIndices(
            gameId: gameID,
            satisfying: .deep
        )

        #expect(standard == [1])
        #expect(deep == [1])
    }

    /// The quality preset is a label, not a measurement. Rows written when a
    /// preset meant a fixed movetime carry that preset's name with whatever
    /// depth the machine happened to reach, so reusing on the label alone
    /// keeps shallow data under a preset that now promises a depth. The real
    /// case that motivated this: a game stored as "standard" whose rank-one
    /// depths ranged from 8 to 17.
    @Test("a row shallower than the request is not reused despite its preset")
    func aRowShallowerThanTheRequestIsNotReused() async throws {
        let store = try GameStore()
        let gameID = try #require(
            try store.save(GameRecord(source: .pgnImport, pgn: "*", white: "W", black: "B")).id
        )
        try await store.saveAnalysis(
            [
                AnalysisRecord(
                    gameId: gameID,
                    plyIndex: 0,
                    fen: "shallow",
                    depth: 13,
                    scoreCentipawns: 10,
                    principalVariation: "e2e4",
                    multiPVRank: 1,
                    qualityPreset: .standard,
                    analyzedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            gameId: gameID,
            plyIndex: 0
        )
        try await store.saveAnalysis(
            [
                AnalysisRecord(
                    gameId: gameID,
                    plyIndex: 1,
                    fen: "deep-enough",
                    depth: 18,
                    scoreCentipawns: 12,
                    principalVariation: "e7e5",
                    multiPVRank: 1,
                    qualityPreset: .standard,
                    analyzedAt: Date(timeIntervalSince1970: 101)
                ),
            ],
            gameId: gameID,
            plyIndex: 1
        )

        // On the preset alone both rows qualify.
        let withoutFloor = try await store.analyzedPlyIndices(
            gameId: gameID,
            satisfying: .standard
        )
        #expect(withoutFloor == [0, 1])

        // With the depth the preset now stands for, only the deep row does.
        let withFloor = try await store.analyzedPlyIndices(
            gameId: gameID,
            satisfying: .standard,
            minimumDepth: 18
        )
        #expect(withFloor == [1])
    }
}
