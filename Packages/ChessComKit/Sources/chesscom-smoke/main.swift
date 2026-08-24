import ChessComKit
import Foundation

// Live smoke run against the real chess.com public API.
//
//     swift run --package-path Packages/ChessComKit chesscom-smoke <username>
//
// Exits 0 only if a real profile/archive/games fetch round-trips through
// ChessComClient's decoders without error. Run this after touching
// ChessComKit, before trusting it end-to-end through the UI.

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    log("FAIL: \(message)")
    exit(1)
}

let username = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "hikaru"
let fetchAll = CommandLine.arguments.contains("--all")
let outDirIndex = CommandLine.arguments.firstIndex(of: "--out-dir")
let outDir: String? = outDirIndex != nil && outDirIndex! + 1 < CommandLine.arguments.count ? CommandLine.arguments[outDirIndex! + 1] : nil

let semaphore = DispatchSemaphore(value: 0)

Task {
    let client = ChessComClient(contactInfo: "chessanto-qa-hikaru")

    do {
        let profile = try await client.profile(username: username)
        log("profile: username=\(profile.username) name=\(profile.name ?? "-") country=\(profile.country ?? "-")")

        let archives = try await client.archiveURLs(username: username)
        guard !archives.isEmpty else { fail("no archives for \(username)") }
        log("archives: \(archives.count) months, most recent \(archives.last!)")

        if fetchAll {
            var totalGames = 0
            for (idx, archiveURL) in archives.enumerated() {
                let games = try await client.games(archiveURL: archiveURL)
                totalGames += games.count
                log("[\(idx + 1)/\(archives.count)] \(archiveURL) -> \(games.count) games (total: \(totalGames))")

                if let outDir {
                    let filename = archiveURL.replacingOccurrences(of: "https://api.chess.com/pub/player/\(username.lowercased())/games/", with: "").replacingOccurrences(of: "/", with: "-") + ".json"
                    let filePath = (outDir as NSString).appendingPathComponent(filename)
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .secondsSince1970
                    let data = try encoder.encode(games)
                    try data.write(to: URL(fileURLWithPath: filePath))
                }
            }
            log("FETCH ALL COMPLETE: \(totalGames) games across \(archives.count) archives")
        } else {
            let recent = try await client.recentGames(username: username, monthCount: 1)
            guard !recent.isEmpty else { fail("no games in most recent archive") }
            log("recentGames: \(recent.count) games")

            let first = recent[0]
            guard first.pgn.contains("[Event "), !first.white.username.isEmpty, !first.black.username.isEmpty else {
                fail("first game decoded but looks malformed: \(first)")
            }
            log("first game: \(first.white.username) (\(first.white.rating)) vs \(first.black.username) (\(first.black.rating)), \(first.timeControl)")
        }

        log("PASS")
        semaphore.signal()
    } catch {
        fail("\(error)")
    }
}

semaphore.wait()
