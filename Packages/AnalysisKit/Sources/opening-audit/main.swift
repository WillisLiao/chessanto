import AnalysisKit
import ChessCore
import Foundation

struct GameEntry: Decodable {
    let url: String
    let white: String
    let black: String
    let eco: String?
    let rules: String?
    let pgn: String
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: opening-audit <path to real_games.json>\n".data(using: .utf8)!)
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let data = try Data(contentsOf: inputURL)
let games = try JSONDecoder().decode([GameEntry].self, from: data)

let book = OpeningBook.shared
print("Loaded opening book with \(book.indexedEntryCount) indexed EPDs.")

var totalGames = 0
var standardGames = 0
var chess960Games = 0
var parseFailures = 0
var matchedCount = 0
var missedCount = 0
var chess960MatchedCount = 0

var missedSequences: [String: Int] = [:]
var depthCounts: [Int: Int] = [:]
var missedSamples: [(pgn: String, white: String, black: String, ecoTag: String, url: String)] = []
var shallowMatches: [(name: String, eco: String, ply: Int, pgn: String, ecoTag: String)] = []

for game in games {
    totalGames += 1
    let is960 = game.rules == "chess960" || game.pgn.contains("[Variant \"Chess960\"]") || game.pgn.contains("[SetUp \"1\"]")
    if is960 {
        chess960Games += 1
        if let chessGame = try? ChessGame(pgn: game.pgn) {
            var fens = [chessGame.fen(at: chessGame.startIndex) ?? ""]
            for idx in chessGame.mainlineIndices {
                fens.append(chessGame.fen(at: idx) ?? "")
            }
            if book.lookup(fens: fens) != nil {
                chess960MatchedCount += 1
            }
        }
        continue
    }

    standardGames += 1
    guard let chessGame = try? ChessGame(pgn: game.pgn) else {
        parseFailures += 1
        continue
    }

    var fens = [chessGame.fen(at: chessGame.startIndex) ?? ""]
    for idx in chessGame.mainlineIndices {
        fens.append(chessGame.fen(at: idx) ?? "")
    }

    guard fens.count > 1 else { continue }

    if let match = book.lookup(fens: fens) {
        matchedCount += 1
        depthCounts[match.deepestBookPly, default: 0] += 1
        if match.deepestBookPly <= 2 && fens.count > 10 && (game.eco ?? "").count > 0 {
            if shallowMatches.count < 30 {
                shallowMatches.append((name: match.name, eco: match.eco, ply: match.deepestBookPly, pgn: game.pgn, ecoTag: game.eco ?? ""))
            }
        }
    } else {
        missedCount += 1
        let sans = OpeningBook.tokenize(pgn: game.pgn)
        let firstFew = sans.prefix(6).joined(separator: " ")
        missedSequences[firstFew, default: 0] += 1
        if missedSamples.count < 30 {
            missedSamples.append((pgn: game.pgn, white: game.white, black: game.black, ecoTag: game.eco ?? "", url: game.url))
        }
    }
}

print("\n--- COVERAGE AUDIT RESULTS ---")
print("Total games in file: \(totalGames)")
print("Standard chess games: \(standardGames)")
print("Chess960 games: \(chess960Games) (Matched against book: \(chess960MatchedCount))")
print("Parse failures: \(parseFailures)")
print("Matched standard games: \(matchedCount) (\(String(format: "%.2f", Double(matchedCount) * 100.0 / Double(standardGames)))%)")
print("Missed standard games: \(missedCount) (\(String(format: "%.2f", Double(missedCount) * 100.0 / Double(standardGames)))%)")

print("\n--- BOOK DEPTH DISTRIBUTION ---")
for ply in depthCounts.keys.sorted() {
    print("  Ply \(ply) (Move \(ply/2).\(ply%2 == 1 ? "W" : "B")): \(depthCounts[ply]!) games (\(String(format: "%.1f", Double(depthCounts[ply]!) * 100.0 / Double(matchedCount))%))")
}

print("\n--- TOP MISSED OPENING SEQUENCES ---")
let sortedMissed = missedSequences.sorted { $0.value > $1.value }
for (seq, count) in sortedMissed.prefix(25) {
    print("  [\(count) games]: \(seq)")
}

print("\n--- SAMPLE MISSED GAMES ---")
for sample in missedSamples.prefix(10) {
    let sans = OpeningBook.tokenize(pgn: sample.pgn)
    print("  Players: \(sample.white) vs \(sample.black), Tag: \(sample.ecoTag), URL: \(sample.url)")
    print("  Moves: \(sans.prefix(12).joined(separator: " "))")
}

print("\n--- SAMPLE SHALLOW MATCHES (ply <= 2) ---")
for sample in shallowMatches.prefix(10) {
    let sans = OpeningBook.tokenize(pgn: sample.pgn)
    print("  Matched: \(sample.name) (\(sample.eco)) at ply \(sample.ply), Tag: \(sample.ecoTag)")
    print("  Moves: \(sans.prefix(12).joined(separator: " "))")
}
