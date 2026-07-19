import Foundation

public enum ChessComError: Error, LocalizedError {
    case invalidUsername
    case notFound
    case serverStatus(Int)
    case network(Error)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidUsername: return "Enter a chess.com username."
        case .notFound: return "No chess.com account found with that username."
        case .serverStatus(let status): return "chess.com returned an unexpected response (\(status))."
        case .network(let error): return "Couldn't reach chess.com: \(error.localizedDescription)"
        case .decoding: return "chess.com returned data Chessanto didn't understand."
        }
    }
}

public struct ChessComProfile: Decodable, Sendable, Equatable {
    public let username: String
    public let name: String?
    public let country: String?
    public let url: String?
    public let avatar: String?
}

public struct ChessComRatings: Sendable, Equatable {
    public let daily: Int?
    public let rapid: Int?
    public let blitz: Int?
    public let bullet: Int?

    public init(daily: Int? = nil, rapid: Int? = nil, blitz: Int? = nil, bullet: Int? = nil) {
        self.daily = daily
        self.rapid = rapid
        self.blitz = blitz
        self.bullet = bullet
    }
}

public struct ChessComStats: Decodable, Sendable, Equatable {
    public struct Category: Decodable, Sendable, Equatable {
        public struct Last: Decodable, Sendable, Equatable {
            public let rating: Int
        }

        public let last: Last?
    }

    public let daily: Category?
    public let rapid: Category?
    public let blitz: Category?
    public let bullet: Category?

    private enum CodingKeys: String, CodingKey {
        case daily = "chess_daily"
        case rapid = "chess_rapid"
        case blitz = "chess_blitz"
        case bullet = "chess_bullet"
    }
}

public struct ChessComAccount: Sendable, Equatable {
    public let username: String
    public let name: String?
    public let countryCode: String?
    public let profileURL: URL
    public let ratings: ChessComRatings

    public init(
        username: String,
        name: String?,
        countryCode: String?,
        profileURL: URL,
        ratings: ChessComRatings
    ) {
        self.username = username
        self.name = name
        self.countryCode = countryCode
        self.profileURL = profileURL
        self.ratings = ratings
    }

    public init(profile: ChessComProfile, stats: ChessComStats?) {
        username = profile.username
        name = profile.name
        countryCode = profile.country.flatMap { URL(string: $0)?.lastPathComponent.uppercased() }
        profileURL =
            profile.url.flatMap(URL.init(string:))
            ?? URL(string: "https://www.chess.com/member/\(profile.username.lowercased())")!
        ratings = ChessComRatings(
            daily: stats?.daily?.last?.rating,
            rapid: stats?.rapid?.last?.rating,
            blitz: stats?.blitz?.last?.rating,
            bullet: stats?.bullet?.last?.rating
        )
    }
}

public struct ChessComGame: Decodable, Sendable, Identifiable {
    public let url: String
    public let pgn: String
    public let timeControl: String
    public let endTime: Date
    public let rated: Bool
    public let white: ChessComPlayer
    public let black: ChessComPlayer

    public var id: String { url }

    private enum CodingKeys: String, CodingKey {
        case url, pgn, rated, white, black
        case timeControl = "time_control"
        case endTime = "end_time"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        pgn = try container.decode(String.self, forKey: .pgn)
        timeControl = try container.decode(String.self, forKey: .timeControl)
        rated = try container.decode(Bool.self, forKey: .rated)
        white = try container.decode(ChessComPlayer.self, forKey: .white)
        black = try container.decode(ChessComPlayer.self, forKey: .black)
        let endTimeInterval = try container.decode(TimeInterval.self, forKey: .endTime)
        endTime = Date(timeIntervalSince1970: endTimeInterval)
    }
}

public struct ChessComPlayer: Decodable, Sendable {
    public let username: String
    public let rating: Int
    public let result: String
}

private struct ArchivesResponse: Decodable {
    let archives: [String]
}

private struct GamesResponse: Decodable {
    let games: [ChessComGame]
}

/// Client for chess.com's public, unauthenticated API.
/// https://www.chess.com/news/view/published-data-api
public actor ChessComClient {
    private let session: URLSession
    private let userAgent: String

    public init(contactInfo: String = "chessanto-local-app") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
        self.userAgent = "Chessanto/1.0 (local chess coach; contact: \(contactInfo))"
    }

    public func profile(username: String) async throws -> ChessComProfile {
        try await get("https://api.chess.com/pub/player/\(try sanitized(username))")
    }

    public func stats(username: String) async throws -> ChessComStats {
        try await get("https://api.chess.com/pub/player/\(try sanitized(username))/stats")
    }

    /// Resolves the exact identity a user can confirm. Profile lookup is
    /// required, while ratings degrade gracefully when stats are unavailable.
    public func account(username: String) async throws -> ChessComAccount {
        async let profileRequest = profile(username: username)
        async let statsRequest = try? stats(username: username)
        return try await ChessComAccount(
            profile: profileRequest,
            stats: statsRequest
        )
    }

    /// Returns monthly archive URLs, oldest first.
    public func archiveURLs(username: String) async throws -> [String] {
        let response: ArchivesResponse = try await get(
            "https://api.chess.com/pub/player/\(try sanitized(username))/games/archives"
        )
        return response.archives
    }

    /// Fetches all games in a single monthly archive (e.g. the last URL from `archiveURLs`).
    public func games(archiveURL: String) async throws -> [ChessComGame] {
        let response: GamesResponse = try await get(archiveURL)
        return response.games
    }

    /// Convenience: fetches the games from the most recent `monthCount` archives, newest first.
    public func recentGames(username: String, monthCount: Int = 2) async throws -> [ChessComGame] {
        let archives = try await archiveURLs(username: username)
        guard !archives.isEmpty else { return [] }
        let recent = archives.suffix(monthCount).reversed()
        var results: [ChessComGame] = []
        for archiveURL in recent {
            results.append(contentsOf: try await games(archiveURL: archiveURL))
        }
        return results.sorted { $0.endTime > $1.endTime }
    }

    private func sanitized(_ username: String) throws -> String {
        let normalized = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty,
            let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            throw ChessComError.invalidUsername
        }
        return encoded
    }

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw ChessComError.invalidUsername }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChessComError.network(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw ChessComError.notFound
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ChessComError.serverStatus(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ChessComError.decoding(error)
        }
    }
}
