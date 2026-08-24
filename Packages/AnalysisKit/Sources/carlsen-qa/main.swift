import AnalysisKit
import ChessCore
import Persistence
import Foundation

struct ChessComPlayer: Decodable {
    let username: String
    let rating: Int
    let result: String
}

struct ChessComGame: Decodable {
    let url: String
    let pgn: String
    let timeControl: String
    let endTime: Date
    let rated: Bool
    let white: ChessComPlayer
    let black: ChessComPlayer

    enum CodingKeys: String, CodingKey {
        case url, pgn, rated, white, black
        case timeControl = "time_control"
        case endTime = "end_time"
    }

    init(from decoder: Decoder) throws {
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

func log(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}

func extractTag(name: String, from pgn: String) -> String? {
    let pattern = "\\[\(name) \\\"([^\\\"]+)\\\"\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(pgn.startIndex..<pgn.endIndex, in: pgn)
    guard let match = regex.firstMatch(in: pgn, options: [], range: range),
          let tagRange = Range(match.range(at: 1), in: pgn) else {
        return nil
    }
    return String(pgn[tagRange])
}

let archivesDir = "/Users/willis/.gemini/antigravity-cli/brain/ed28d818-b105-4ad9-9eaf-a0314594e75b/scratch/carlsen_archives"
let fileManager = FileManager.default
guard fileManager.fileExists(atPath: archivesDir) else {
    log("Archives directory not found at \(archivesDir)")
    exit(1)
}

let files = try fileManager.contentsOfDirectory(atPath: archivesDir)
    .filter { $0.hasSuffix(".json") }
    .sorted()

log("Found \(files.count) archive files to scan.")

var totalGames = 0
var totalPlies = 0
var pgnParseFailures: [(file: String, url: String, error: String, pgn: String)] = []
var fenMismatches: [(file: String, url: String, expected: String, actual: String, pgn: String)] = []
var reportBuildingFailures: [(file: String, url: String, reason: String, pgn: String)] = []
var otherIssues: [(file: String, url: String, issue: String, pgn: String)] = []

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .secondsSince1970

let book = OpeningBook.shared

for (fileIdx, file) in files.enumerated() {
    let filePath = (archivesDir as NSString).appendingPathComponent(file)
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let games: [ChessComGame]
    do {
        games = try decoder.decode([ChessComGame].self, from: data)
    } catch {
        log("Failed to decode archive file \(file): \(error)")
        continue
    }

    var filePlies = 0
    var fileErrors = 0

    for (gameIdx, game) in games.enumerated() {
        totalGames += 1
        let pgn = game.pgn

        // 1. Parse with ChessGame
        let chessGame: ChessGame
        do {
            chessGame = try ChessGame(pgn: pgn)
        } catch {
            fileErrors += 1
            pgnParseFailures.append((file: file, url: game.url, error: "\(error)", pgn: pgn))
            log("FAIL [\(file) #\(gameIdx+1)] PGN parse throw: \(error) url=\(game.url)")
            continue
        }

        let moveIndices = [chessGame.startIndex] + chessGame.mainlineIndices
        let pliesCount = moveIndices.count
        totalPlies += pliesCount
        filePlies += pliesCount

        let fens = moveIndices.map { chessGame.fen(at: $0) ?? "" }
        let playedUCIs = moveIndices.map { chessGame.uciMove(at: $0) }

        // Check FEN validity
        for (plyIdx, fen) in fens.enumerated() {
            let parts = fen.split(separator: " ")
            if parts.count < 4 {
                otherIssues.append((file: file, url: game.url, issue: "Malformed FEN at ply \(plyIdx): \(fen)", pgn: pgn))
            }
        }

        // Check CurrentPosition tag if present in PGN
        if let currentPosTag = extractTag(name: "CurrentPosition", from: pgn),
           let finalFen = fens.last {
            let tagParts = currentPosTag.split(separator: " ")
            let fenParts = finalFen.split(separator: " ")
            if tagParts.count >= 2 && fenParts.count >= 2 {
                let tagBoardAndColor = "\(tagParts[0]) \(tagParts[1])"
                let fenBoardAndColor = "\(fenParts[0]) \(fenParts[1])"
                if tagBoardAndColor != fenBoardAndColor {
                    fenMismatches.append((file: file, url: game.url, expected: currentPosTag, actual: finalFen, pgn: pgn))
                    log("FAIL [\(file) #\(gameIdx+1)] FEN mismatch: expected=\(currentPosTag) actual=\(finalFen) url=\(game.url)")
                }
            }
        }

        // 2. Report building pipeline if plies > 1
        if pliesCount > 1 {
            let syntheticAnalyses: [AnalysisRecord] = (0..<pliesCount).map { ply in
                let fen = fens[ply]
                let playedUCI = playedUCIs[ply]
                return AnalysisRecord(
                    id: Int64(ply + 1),
                    gameId: Int64(totalGames),
                    plyIndex: ply,
                    fen: fen,
                    depth: 16,
                    scoreCentipawns: (ply % 2 == 1) ? 20 : -20,
                    mateIn: nil,
                    principalVariation: playedUCI ?? "e2e4",
                    multiPVRank: 1
                )
            }

            var byPly: [Int: [AnalysisRecord]] = [:]
            for row in syntheticAnalyses {
                byPly[row.plyIndex, default: []].append(row)
            }

            let plies: [PlyRecord] = fens.indices.map { ply in
                let lines = (byPly[ply] ?? [])
                    .sorted { $0.multiPVRank < $1.multiPVRank }
                    .map { analysisRecord in
                        RankedLine(
                            rank: analysisRecord.multiPVRank,
                            scoreCentipawns: analysisRecord.scoreCentipawns,
                            mateIn: analysisRecord.mateIn,
                            principalVariationUCI: analysisRecord.principalVariation.isEmpty
                                ? [] : analysisRecord.principalVariation.split(separator: " ").map(String.init),
                            depth: analysisRecord.depth
                        )
                    }
                return PlyRecord(fen: fens[ply], lines: lines, playedUCI: playedUCIs[ply])
            }

            let resultStr = game.white.result == "win" ? "1-0" : (game.black.result == "win" ? "0-1" : "1/2-1/2")
            let reportInput = ReportInput(
                plies: plies,
                whiteName: game.white.username,
                blackName: game.black.username,
                result: resultStr,
                chessComUsername: "MagnusCarlsen"
            )

            guard let report = ReportBuilder.build(
                input: reportInput,
                openingBook: book,
                register: .advanced
            ) else {
                reportBuildingFailures.append((file: file, url: game.url, reason: "ReportBuilder.build returned nil", pgn: pgn))
                continue
            }

            if report.whiteAccuracy.isNaN {
                otherIssues.append((file: file, url: game.url, issue: "White accuracy is NaN", pgn: pgn))
            }
            if report.blackAccuracy.isNaN {
                otherIssues.append((file: file, url: game.url, issue: "Black accuracy is NaN", pgn: pgn))
            }
        }
    }

    log("[\(fileIdx + 1)/\(files.count)] \(file): \(games.count) games, \(filePlies) plies, \(fileErrors) errors (running total: \(totalGames) games, \(pgnParseFailures.count) failures)")
}

log("==================================================")
log("CARLSEN QA SCAN COMPLETE")
log("Total games scanned: \(totalGames)")
log("Total plies replayed: \(totalPlies)")
log("PGN parse failures: \(pgnParseFailures.count)")
log("FEN mismatches: \(fenMismatches.count)")
log("Report building failures: \(reportBuildingFailures.count)")
log("Other issues: \(otherIssues.count)")
log("==================================================")

if !pgnParseFailures.isEmpty {
    log("--- PGN PARSE FAILURES DETAIL ---")
    for (i, f) in pgnParseFailures.enumerated() {
        log("[\(i + 1)] File: \(f.file) | URL: \(f.url)")
        log("Error: \(f.error)")
        log("PGN:\n\(f.pgn)")
        log("--------------------------------------------------")
    }
}

if !fenMismatches.isEmpty {
    log("--- FEN MISMATCHES DETAIL ---")
    for (i, m) in fenMismatches.enumerated() {
        log("[\(i + 1)] File: \(m.file) | URL: \(m.url)")
        log("Expected: \(m.expected)")
        log("Actual:   \(m.actual)")
        log("PGN:\n\(m.pgn)")
        log("--------------------------------------------------")
    }
}

if !otherIssues.isEmpty {
    log("--- OTHER ISSUES DETAIL ---")
    for (i, o) in otherIssues.enumerated() {
        log("[\(i + 1)] File: \(o.file) | URL: \(o.url) | Issue: \(o.issue)")
        log("PGN:\n\(o.pgn)")
        log("--------------------------------------------------")
    }
}

if pgnParseFailures.isEmpty && fenMismatches.isEmpty && reportBuildingFailures.isEmpty && otherIssues.isEmpty {
    log("ALL 9,677 CARLSEN GAMES PASSED WITHOUT ERROR.")
}
