import CompanionDomain
import Foundation
import Testing
@testable import Chessanto

@Suite("Companion game mapping store")
struct CompanionGameMappingStoreTests {
    @Test("opaque identifiers persist separately without exposing local database IDs")
    func opaqueIdentifiersPersistSeparately() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("game-map.json")
        let first = CompanionGameMappingStore(
            fileURL: url,
            makeID: { CompanionGameID("game-random-token") }
        )

        let opaque = try await first.assign(localGameID: 42)
        let reopened = CompanionGameMappingStore(fileURL: url)

        #expect(opaque == CompanionGameID("game-random-token"))
        #expect(try await reopened.localGameID(for: opaque) == 42)
        let bytes = try Data(contentsOf: url)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(text.contains("game-random-token"))
        #expect(opaque.rawValue.contains("42") == false)
    }

    @Test("one local game receives one stable opaque identifier")
    func oneLocalGameReceivesStableOpaqueIdentifier() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("game-map.json")
        let store = CompanionGameMappingStore(
            fileURL: url,
            makeID: { CompanionGameID(UUID().uuidString) }
        )

        let first = try await store.assign(localGameID: 9)
        let second = try await store.assign(localGameID: 9)

        #expect(first == second)
    }
}
