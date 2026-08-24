import AnalysisKit
import ChessCore
import Foundation
import Persistence

struct RawGame: Decodable {
    let url: String
    let pgn: String?
    let timeControl: String?
    let rules: String?
    let white: RawPlayer?
    let black: RawPlayer?

    enum CodingKeys: String, CodingKey {
        case url, pgn, rules, white, black
        case timeControl = "time_control"
    }
}

struct RawPlayer: Decodable {
    let username: String?
    let rating: Int?
    let result: String?
}

struct ArchiveData: Decodable {
    let games: [RawGame]
}

struct FailureReport {
    let url: String
    let errorType: String
    let message: String
    let pgn: String
}

@main
struct QACaruanaRunner {
    static func main() async {
        let scratchDir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "/Users/willis/.gemini/antigravity-cli/brain/1f1424b9-e0b1-4afe-9dce-954ac04122f7/scratch/caruana_games"

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: scratchDir) else {
            print("ERROR: Cannot read directory \(scratchDir)")
            exit(1)
        }

        let jsonFiles = files.filter { $0.hasPrefix("archive-") && $0.hasSuffix(".json") }.sorted()
        print("Found \(jsonFiles.count) archive files in \(scratchDir)")

        var totalRawGames = 0
        var nonChessVariantGames = 0
        var totalStandardGames = 0
        var pgnParseFailures: [FailureReport] = []
        var fenMismatches: [FailureReport] = []
        var replayFailures: [FailureReport] = []
        var reportBuildingFailures: [FailureReport] = []
        var detectorFailures: [FailureReport] = []

        let openingBook = OpeningBook.shared

        for (archiveIndex, jsonFile) in jsonFiles.enumerated() {
            let path = "\(scratchDir)/\(jsonFile)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let archive = try? JSONDecoder().decode(ArchiveData.self, from: data) else {
                print("[\(archiveIndex + 1)/\(jsonFiles.count)] Failed to decode JSON \(jsonFile)")
                continue
            }

            totalRawGames += archive.games.count
            var archiveStandardCount = 0

            for game in archive.games {
                guard let pgn = game.pgn, !pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    nonChessVariantGames += 1
                    continue
                }

                if let rules = game.rules, rules != "chess" {
                    nonChessVariantGames += 1
                    continue
                }

                archiveStandardCount += 1
                totalStandardGames += 1

                // 1. PGN Parse
                let chessGame: ChessGame
                do {
                    chessGame = try ChessGame(pgn: pgn)
                } catch {
                    pgnParseFailures.append(FailureReport(
                        url: game.url,
                        errorType: "PGNParseError",
                        message: "\(error)",
                        pgn: pgn
                    ))
                    continue
                }

                // 2. Mainline Navigation and Replay
                let moveIndices = [chessGame.startIndex] + chessGame.mainlineIndices
                guard moveIndices.count > 0 else {
                    replayFailures.append(FailureReport(
                        url: game.url,
                        errorType: "EmptyMainline",
                        message: "moveIndices is empty",
                        pgn: pgn
                    ))
                    continue
                }

                var fens: [String] = []
                var playedUCIs: [String?] = []
                var replayOk = true

                for (idx, moveIndex) in moveIndices.enumerated() {
                    guard let fen = chessGame.fen(at: moveIndex) else {
                        replayFailures.append(FailureReport(
                            url: game.url,
                            errorType: "NilFEN",
                            message: "FEN is nil at move index \(idx)",
                            pgn: pgn
                        ))
                        replayOk = false
                        break
                    }
                    guard ChessGame.isValidFEN(fen) else {
                        replayFailures.append(FailureReport(
                            url: game.url,
                            errorType: "InvalidFEN",
                            message: "Invalid FEN at move index \(idx): \(fen)",
                            pgn: pgn
                        ))
                        replayOk = false
                        break
                    }
                    fens.append(fen)
                    let uci = chessGame.uciMove(at: moveIndex)
                    playedUCIs.append(uci)

                    if idx > 0 {
                        guard uci != nil else {
                            replayFailures.append(FailureReport(
                                url: game.url,
                                errorType: "NilUCI",
                                message: "UCI move is nil at move index \(idx)",
                                pgn: pgn
                            ))
                            replayOk = false
                            break
                        }
                    }
                }

                guard replayOk else { continue }

                // Check CurrentPosition tag if present
                if let currentPos = chessGame.tags["CurrentPosition"], !currentPos.isEmpty, let lastFEN = fens.last {
                    let currentBoard = currentPos.split(separator: " ").prefix(2).joined(separator: " ")
                    let computedBoard = lastFEN.split(separator: " ").prefix(2).joined(separator: " ")
                    if currentBoard != computedBoard {
                        fenMismatches.append(FailureReport(
                            url: game.url,
                            errorType: "FENMismatch",
                            message: "Expected board '\(currentBoard)' but got '\(computedBoard)' (full expected: \(currentPos), full computed: \(lastFEN))",
                            pgn: pgn
                        ))
                    }
                }

                // If game has moves, test full replayLine
                let ucies = Array(playedUCIs.dropFirst()).compactMap { $0 }
                if !ucies.isEmpty {
                    let replayedMoves = ChessGame.replayLine(fromUCI: ucies, startingFEN: fens[0])
                    if replayedMoves.count != ucies.count {
                        replayFailures.append(FailureReport(
                            url: game.url,
                            errorType: "ReplayLineMismatch",
                            message: "Replayed \(replayedMoves.count) of \(ucies.count) moves from start FEN \(fens[0])",
                            pgn: pgn
                        ))
                    }
                }

                // 3. Report Building & Theme Detectors across all plies
                let whiteName = game.white?.username ?? chessGame.tags["White"] ?? "White"
                let blackName = game.black?.username ?? chessGame.tags["Black"] ?? "Black"
                let result = chessGame.tags["Result"] ?? "*"

                // Construct synthetic/simulated analysis rows for the game
                let plies: [PlyRecord] = fens.indices.map { ply in
                    let rank1Line = RankedLine(
                        rank: 1,
                        scoreCentipawns: ply % 4 == 0 ? 150 : (ply % 4 == 2 ? -120 : 10),
                        mateIn: ply == fens.count - 1 && result != "1/2-1/2" && result != "*" ? (result == "1-0" ? 1 : -1) : nil,
                        principalVariationUCI: ply < playedUCIs.count && playedUCIs[ply] != nil ? [playedUCIs[ply]!] : ["e2e4"],
                        depth: 16
                    )
                    return PlyRecord(
                        fen: fens[ply],
                        lines: [rank1Line],
                        playedUCI: playedUCIs[ply],
                        clockSeconds: 60
                    )
                }

                let reportInput = ReportInput(
                    plies: plies,
                    whiteName: whiteName,
                    blackName: blackName,
                    result: result,
                    chessComUsername: "FabianoCaruana"
                )

                // Build reports with all 3 registers
                for register in [RatingRegister.advanced, RatingRegister.intermediate, RatingRegister.beginner] {
                    if let report = ReportBuilder.build(input: reportInput, openingBook: openingBook, register: register) {
                        if report.whiteAccuracy.isNaN || report.whiteAccuracy.isInfinite || report.blackAccuracy.isNaN || report.blackAccuracy.isInfinite {
                            reportBuildingFailures.append(FailureReport(
                                url: game.url,
                                errorType: "AccuracyNaN",
                                message: "Accuracy calculation produced NaN/Infinite: White=\(report.whiteAccuracy), Black=\(report.blackAccuracy)",
                                pgn: pgn
                            ))
                        }
                    } else if moveIndices.count > 1 {
                        reportBuildingFailures.append(FailureReport(
                            url: game.url,
                            errorType: "BuildReportNil",
                            message: "ReportBuilder.build returned nil for fully analyzed game with \(moveIndices.count) plies",
                            pgn: pgn
                        ))
                    }
                }

                // 4. Run all theme detectors on every ply
                for p in 1..<reportInput.plies.count {
                    _ = ThemeDetector.pin(input: reportInput, ply: p)
                    _ = ThemeDetector.skewer(input: reportInput, ply: p)
                    _ = ThemeDetector.discoveredAttack(input: reportInput, ply: p)
                    _ = ThemeDetector.backRankWeakness(input: reportInput, ply: p)
                    _ = ThemeDetector.trappedPiece(input: reportInput, ply: p)
                    _ = ThemeDetector.moveQuality(input: reportInput, ply: p)
                    _ = ThemeDetector.fork(input: reportInput, ply: p)
                    _ = ThemeDetector.ignoredThreat(input: reportInput, ply: p)
                    _ = ThemeDetector.punishment(input: reportInput, ply: p)
                    _ = ThemeDetector.missedMate(input: reportInput, ply: p)
                    _ = ThemeDetector.allowedMate(input: reportInput, ply: p)
                    _ = ThemeDetector.betterMove(input: reportInput, ply: p)
                }
            }

            print("[\(archiveIndex + 1)/\(jsonFiles.count)] \(jsonFile): \(archiveStandardCount) standard games scanned (accumulated \(totalStandardGames))")
        }

        print("\n=======================================================")
        print("QA CARUANA SCAN COMPLETE")
        print("=======================================================")
        print("Total raw games inspected: \(totalRawGames)")
        print("Non-chess/bughouse games skipped: \(nonChessVariantGames)")
        print("Total standard chess games scanned: \(totalStandardGames)")
        print("PGN parse failures: \(pgnParseFailures.count)")
        print("FEN mismatches: \(fenMismatches.count)")
        print("Replay failures: \(replayFailures.count)")
        print("Report building failures: \(reportBuildingFailures.count)")
        print("Theme detector failures: \(detectorFailures.count)")
        print("=======================================================\n")

        if !pgnParseFailures.isEmpty {
            print("--- PGN PARSE FAILURES (\(pgnParseFailures.count)) ---")
            for (idx, failure) in pgnParseFailures.enumerated() {
                print("[\(idx + 1)] URL: \(failure.url)")
                print("Error: \(failure.message)")
                print("PGN:\n\(failure.pgn)\n")
            }
        }

        if !fenMismatches.isEmpty {
            print("--- FEN MISMATCHES (\(fenMismatches.count)) ---")
            for (idx, failure) in fenMismatches.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(failure.url)")
                print("Message: \(failure.message)")
                print("PGN:\n\(failure.pgn)\n")
            }
        }

        if !replayFailures.isEmpty {
            print("--- REPLAY FAILURES (\(replayFailures.count)) ---")
            for (idx, failure) in replayFailures.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(failure.url)")
                print("Message: \(failure.message)")
                print("PGN:\n\(failure.pgn)\n")
            }
        }

        if !reportBuildingFailures.isEmpty {
            print("--- REPORT BUILDING FAILURES (\(reportBuildingFailures.count)) ---")
            for (idx, failure) in reportBuildingFailures.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(failure.url)")
                print("Message: \(failure.message)")
            }
        }
    }
}
