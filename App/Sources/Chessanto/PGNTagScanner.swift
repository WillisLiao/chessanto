import Foundation
import ChessCore

/// Lightweight PGN tag-pair scanner used only for quick metadata extraction
/// (library list display) before a game is opened for full analysis.
/// Full parsing and move-tree construction goes through ChessCore.
enum PGNTagScanner {
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[\s*([A-Za-z0-9_]+)\s+"([^"]*)"\s*\]"#
    )

    static func tags(from pgn: String) -> [String: String]? {
        let normalized = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard !normalized.isEmpty else { return nil }

        let range = NSRange(normalized.startIndex..., in: normalized)
        var tags: [String: String] = [:]
        tagPattern.enumerateMatches(in: normalized, range: range) { match, _, _ in
            guard let match, let keyRange = Range(match.range(at: 1), in: normalized),
                  let valueRange = Range(match.range(at: 2), in: normalized) else { return }
            tags[String(normalized[keyRange])] = String(normalized[valueRange])
        }

        if !tags.isEmpty {
            return tags
        }

        // Bare move text with no headers (e.g. pasted or drag-dropped "1. e4 e5 ...")
        if let game = try? ChessGame(pgn: normalized), !game.mainlineIndices.isEmpty {
            var resultTags = game.tags
            if resultTags["White"] == nil { resultTags["White"] = "White" }
            if resultTags["Black"] == nil { resultTags["Black"] = "Black" }
            if resultTags["Result"] == nil { resultTags["Result"] = "*" }
            return resultTags
        }

        return nil
    }

    static func date(from tags: [String: String]) -> Date? {
        guard let dateString = tags["Date"] else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateString)
    }
}

