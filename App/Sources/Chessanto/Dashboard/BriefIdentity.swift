import Foundation
import Persistence

/// Who the user is among the players in their own games.
///
/// Pure and separate from `GameLibrary` so it can be tested without opening
/// a database. `GameLibrary` holds the state; this decides what the state
/// means.
enum BriefIdentity {
    /// A confirmed chess.com account answers the question implicitly, so it
    /// wins. Otherwise the user's explicitly chosen name stands in, which is
    /// what makes progress surfaces reachable for a PGN-only user.
    static func resolve(
        chessComUsername: String,
        isChessComAccountConfirmed: Bool,
        playerName: String?
    ) -> String? {
        if isChessComAccountConfirmed {
            let username = chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty { return username }
        }
        let name = (playerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Every name appearing in the register, most-played first, so the
    /// user's own name is normally the first thing offered. Names are
    /// matched case-insensitively but presented as first seen, because
    /// "willisliao" and "WillisLiao" are one player.
    static func candidates(in games: [GameRecord]) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for game in games {
            for name in [game.white, game.black] {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = trimmed }
            }
        }
        return counts
            .sorted { left, right in
                // Ties break alphabetically so the list is stable between
                // launches rather than reordering with dictionary seed.
                left.value == right.value ? left.key < right.key : left.value > right.value
            }
            .compactMap { display[$0.key] }
    }
}
