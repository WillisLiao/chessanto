import Foundation

public enum ChessComError: Error, LocalizedError {
    case invalidUsername
    case notFound
    case network(Error)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidUsername: return "Enter a chess.com username."
        case .notFound: return "No chess.com account found with that username."
        case .network(let error): return "Couldn't reach chess.com: \(error.localizedDescription)"
        case .decoding: return "chess.com returned data Chessanto didn't understand."
        }
    }
}

public struct ChessComProfile: Decodable, Sendable {
    public let username: String
    public let name: String?
    public let country: String?
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
        try await get("https://api.chess.com/pub/player/\(sanitized(username))")
    }

    /// Returns monthly archive URLs, oldest first.
    public func archiveURLs(username: String) async throws -> [String] {
        let response: ArchivesResponse = try await get(
            "https://api.chess.com/pub/player/\(sanitized(username))/games/archives"
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

    private func sanitized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ChessComError.decoding(error)
        }
    }
}
