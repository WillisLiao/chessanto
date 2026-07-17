import Foundation
import Testing
@testable import ChessComKit

struct ChessComKitTests {
    private struct GamesResponse: Decodable {
        let games: [ChessComGame]
    }

    private func loadFixtureGames() throws -> [ChessComGame] {
        let url = Bundle.module.url(forResource: "sample-archive", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GamesResponse.self, from: data).games
    }

    @Test func decodesRealArchiveFixture() throws {
        let games = try loadFixtureGames()
        #expect(games.count == 2)
    }

    @Test func decodesGameFields() throws {
        let game = try loadFixtureGames()[0]
        #expect(game.url == "https://www.chess.com/game/live/170971127078")
        #expect(game.id == game.url)
        #expect(game.timeControl == "180")
        #expect(game.rated == true || game.rated == false)
        #expect(game.pgn.contains("[Event \"Live Chess\""))
        #expect(game.white.username.isEmpty == false)
        #expect(game.black.username.isEmpty == false)
        #expect(game.white.rating > 0)
        #expect(game.black.rating > 0)
    }

    @Test func decodesEndTimeAsDate() throws {
        let game = try loadFixtureGames()[0]
        // A game played 2026-07-01 should decode to a plausible epoch-based date, not garbage.
        #expect(game.endTime.timeIntervalSince1970 > 1_700_000_000)
    }
}
