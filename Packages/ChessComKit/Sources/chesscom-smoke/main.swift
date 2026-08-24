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
let fetchAll = CommandLine.arguments.contains("--fetch-all")
let outDir = CommandLine.arguments.firstIndex(of: "--fetch-all").flatMap { idx in
    CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : nil
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    let client = ChessComClient(contactInfo: "chesscom-smoke")

    do {
        let profile = try await client.profile(username: username)
        log("profile: username=\(profile.username) name=\(profile.name ?? "-") country=\(profile.country ?? "-")")

        let archives = try await client.archiveURLs(username: username)
        guard !archives.isEmpty else { fail("no archives for \(username)") }
        log("archives: \(archives.count) months, most recent \(archives.last!)")

        if fetchAll, let outDir {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            var totalGames = 0
            for (index, archiveURL) in archives.enumerated() {
                let archiveName = archiveURL.split(separator: "/").suffix(2).joined(separator: "-")
                let outPath = "\(outDir)/archive-\(archiveName).json"
                let data: Data
                if fileManager.fileExists(atPath: outPath) {
                    data = try Data(contentsOf: URL(fileURLWithPath: outPath))
                } else {
                    log("[\(index + 1)/\(archives.count)] Fetching \(archiveURL)...")
                    var request = URLRequest(url: URL(string: archiveURL)!)
                    request.setValue("Chessanto/1.0 (local chess coach; contact: chesscom-smoke)", forHTTPHeaderField: "User-Agent")
                    let (fetchedData, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        fail("HTTP \(http.statusCode) for \(archiveURL)")
                    }
                    try fetchedData.write(to: URL(fileURLWithPath: outPath))
                    data = fetchedData
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }

                struct GamesResponse: Decodable {
                    let games: [ChessComGame]
                }
                let decoded = try JSONDecoder().decode(GamesResponse.self, from: data)
                log("[\(index + 1)/\(archives.count)] \(archiveName): \(decoded.games.count) games")
                totalGames += decoded.games.count
            }
            log("Total games fetched across \(archives.count) archives: \(totalGames)")
            log("PASS")
            semaphore.signal()
            return
        }

        let recent = try await client.recentGames(username: username, monthCount: 1)
        guard !recent.isEmpty else { fail("no games in most recent archive") }
        log("recentGames: \(recent.count) games")

        let first = recent[0]
        guard first.pgn?.contains("[Event ") == true, !first.white.username.isEmpty, !first.black.username.isEmpty else {
            fail("first game decoded but looks malformed: \(first)")
        }
        log("first game: \(first.white.username) (\(first.white.rating)) vs \(first.black.username) (\(first.black.rating)), \(first.timeControl)")

        log("PASS")
        semaphore.signal()
    } catch {
        fail("\(error)")
    }
}

semaphore.wait()
