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

let semaphore = DispatchSemaphore(value: 0)

Task {
    let client = ChessComClient(contactInfo: "chesscom-smoke")

    do {
        let profile = try await client.profile(username: username)
        log("profile: username=\(profile.username) name=\(profile.name ?? "-") country=\(profile.country ?? "-")")

        let archives = try await client.archiveURLs(username: username)
        guard !archives.isEmpty else { fail("no archives for \(username)") }
        log("archives: \(archives.count) months, most recent \(archives.last!)")

        let recent = try await client.recentGames(username: username, monthCount: 1)
        guard !recent.isEmpty else { fail("no games in most recent archive") }
        log("recentGames: \(recent.count) games")

        let first = recent[0]
        guard first.pgn.contains("[Event "), !first.white.username.isEmpty, !first.black.username.isEmpty else {
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
