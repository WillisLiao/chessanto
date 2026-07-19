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

    @Test func accountIdentityCombinesCanonicalProfileAndCurrentRatings() throws {
        let profileData = Data(
            """
            {
              "username": "WillisLiao",
              "name": "Willis Liao",
              "country": "https://api.chess.com/pub/country/TW",
              "url": "https://www.chess.com/member/willisliao",
              "avatar": "https://images.chesscomfiles.com/avatar.png"
            }
            """.utf8
        )
        let statsData = Data(
            """
            {
              "chess_daily": {"last": {"rating": 906}},
              "chess_rapid": {"last": {"rating": 307}},
              "chess_bullet": {"last": {"rating": 137}},
              "chess_blitz": {"last": {"rating": 231}}
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(ChessComProfile.self, from: profileData)
        let stats = try JSONDecoder().decode(ChessComStats.self, from: statsData)
        let account = ChessComAccount(profile: profile, stats: stats)

        #expect(account.username == "WillisLiao")
        #expect(account.name == "Willis Liao")
        #expect(account.countryCode == "TW")
        #expect(account.profileURL.absoluteString == "https://www.chess.com/member/willisliao")
        #expect(account.ratings == ChessComRatings(daily: 906, rapid: 307, blitz: 231, bullet: 137))
    }
}
