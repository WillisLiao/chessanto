import Foundation

/// Lightweight PGN tag-pair scanner used only for quick metadata extraction
/// (library list display) before a game is opened for full analysis.
/// Full parsing and move-tree construction goes through ChessCore.
enum PGNTagScanner {
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\w+)\s+"([^"]*)"\]"#
    )

    static func tags(from pgn: String) -> [String: String]? {
        guard pgn.contains("[") else { return nil }
        let range = NSRange(pgn.startIndex..., in: pgn)
        var tags: [String: String] = [:]
        tagPattern.enumerateMatches(in: pgn, range: range) { match, _, _ in
            guard let match, let keyRange = Range(match.range(at: 1), in: pgn),
                  let valueRange = Range(match.range(at: 2), in: pgn) else { return }
            tags[String(pgn[keyRange])] = String(pgn[valueRange])
        }
        return tags.isEmpty ? nil : tags
    }

    static func date(from tags: [String: String]) -> Date? {
        guard let dateString = tags["Date"] else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateString)
    }
}
