import AnalysisKit
import ChessCore
import ChessComKit
import Persistence
import Foundation
import Testing
@testable import Chessanto

@MainActor
struct HikaruQAScanTests {
    @Test func scanAllHikaruArchives() throws {
        // Deliberate opt-in: the full scan takes minutes over 70,182 cached
        // games and must never run inside ordinary `xcodebuild test` runs.
        // Set HIKARU_QA_RUN_SCAN=1 (and optionally HIKARU_QA_ARCHIVES_DIR)
        // to run it on purpose.
        guard ProcessInfo.processInfo.environment["HIKARU_QA_RUN_SCAN"] == "1" else {
            print("Set HIKARU_QA_RUN_SCAN=1 to run the full Hikaru archive scan; skipping.")
            return
        }
        // Overridable so the scan can run from any machine; falls back to the
        // directory used when the archives were first fetched.
        let archivesDir = ProcessInfo.processInfo.environment["HIKARU_QA_ARCHIVES_DIR"]
            ?? "/Users/willis/.gemini/antigravity-cli/brain/ed28d818-b105-4ad9-9eaf-a0314594e75b/scratch/hikaru_archives"
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archivesDir) else {
            print("Archives directory not found at \(archivesDir); set HIKARU_QA_ARCHIVES_DIR to run the full scan. Skipping.")
            return
        }

        let files = try fileManager.contentsOfDirectory(atPath: archivesDir)
            .filter { $0.hasSuffix(".json") }
            .sorted()

        print("Found \(files.count) archive files to scan.")

        var totalGames = 0
        var totalPlies = 0
        var pgnParseFailures: [(file: String, url: String, error: String, pgn: String)] = []
        var fenMismatches: [(file: String, url: String, expected: String, actual: String, pgn: String)] = []
        var reportBuildingFailures: [(file: String, url: String, reason: String, pgn: String)] = []
        var zeroKeyMomentReports: [(file: String, url: String, pgn: String)] = []
        var otherIssues: [(file: String, url: String, issue: String, pgn: String)] = []
        var skippedVariants: [(file: String, url: String, variant: String)] = []
        var skippedNoPGN = 0

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let store = try GameStore()

        for file in files {
            let filePath = (archivesDir as NSString).appendingPathComponent(file)
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let games: [ChessComGame]
            do {
                games = try decoder.decode([ChessComGame].self, from: data)
            } catch {
                print("Failed to decode archive file \(file): \(error)")
                continue
            }

            for game in games {
                totalGames += 1
                let pgn = game.pgn

                // Bughouse and other partner variants ship with no "pgn" key
                // at all (chess.com provides none for them). They are out of
                // product scope per PLAN.md. Count them, do not assert on them.
                if pgn.isEmpty {
                    skippedNoPGN += 1
                    continue
                }

                // Variant games (Chess960, three-check, odds) are explicitly
                // out of product scope per PLAN.md and degrade via the normal
                // load-error alert. Count them, do not assert on them.
                if let variant = extractTag(name: "Variant", from: pgn), variant != "Standard" {
                    skippedVariants.append((file: file, url: game.url, variant: variant))
                    continue
                }

                // 1. Replay and load through GameReplayViewModel
                let resultStr = game.white.result == "win" ? "1-0" : (game.black.result == "win" ? "0-1" : "1/2-1/2")
                let record = GameRecord(
                    id: Int64(totalGames),
                    source: .chessCom,
                    sourceURL: game.url,
                    pgn: pgn,
                    white: game.white.username,
                    black: game.black.username,
                    whiteRating: game.white.rating,
                    blackRating: game.black.rating,
                    result: resultStr
                )

                let viewModel = GameReplayViewModel(record: record, store: store)
                if let loadError = viewModel.loadError {
                    pgnParseFailures.append((file: file, url: game.url, error: loadError, pgn: pgn))
                    continue
                }

                let pliesCount = viewModel.moveIndices.count
                totalPlies += pliesCount

                // Check FEN count and playedUCIs count
                if viewModel.fens.count != pliesCount || viewModel.playedUCIs.count != pliesCount {
                    otherIssues.append((
                        file: file,
                        url: game.url,
                        issue: "Count mismatch: moveIndices=\(pliesCount), fens=\(viewModel.fens.count), playedUCIs=\(viewModel.playedUCIs.count)",
                        pgn: pgn
                    ))
                }

                // Check FEN validity at every ply (a full FEN has six fields)
                for (plyIdx, fen) in viewModel.fens.enumerated() {
                    let parts = fen.split(separator: " ")
                    if parts.count != 6 {
                        otherIssues.append((
                            file: file,
                            url: game.url,
                            issue: "Malformed FEN at ply \(plyIdx): \(fen)",
                            pgn: pgn
                        ))
                    }
                }

                // Check CurrentPosition tag if present in PGN
                if let currentPosTag = extractTag(name: "CurrentPosition", from: pgn),
                   let finalFen = viewModel.fens.last {
                    // Compare position board part and active color
                    let tagParts = currentPosTag.split(separator: " ")
                    let fenParts = finalFen.split(separator: " ")
                    if tagParts.count >= 2 && fenParts.count >= 2 {
                        let tagBoardAndColor = "\(tagParts[0]) \(tagParts[1])"
                        let fenBoardAndColor = "\(fenParts[0]) \(fenParts[1])"
                        if tagBoardAndColor != fenBoardAndColor {
                            fenMismatches.append((
                                file: file,
                                url: game.url,
                                expected: currentPosTag,
                                actual: finalFen,
                                pgn: pgn
                            ))
                        }
                    }
                }

                // 2. Report building pipeline if plies > 1
                if pliesCount > 1 {
                    let syntheticAnalyses: [AnalysisRecord] = (0..<pliesCount).map { ply in
                        let fen = viewModel.fens[ply]
                        let playedUCI = viewModel.playedUCIs[ply]
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

                    guard let reportInput = ReportBuilding.buildInput(
                        record: record,
                        analysisRows: syntheticAnalyses,
                        chessComUsername: "Hikaru"
                    ) else {
                        reportBuildingFailures.append((
                            file: file,
                            url: game.url,
                            reason: "buildInput returned nil",
                            pgn: pgn
                        ))
                        continue
                    }

                    guard let report = ReportBuilding.buildReport(
                        record: record,
                        analysisRows: syntheticAnalyses,
                        chessComUsername: "Hikaru"
                    ) else {
                        reportBuildingFailures.append((
                            file: file,
                            url: game.url,
                            reason: "buildReport returned nil",
                            pgn: pgn
                        ))
                        continue
                    }

                    if report.whiteAccuracy.isNaN || report.blackAccuracy.isNaN {
                        otherIssues.append((
                            file: file,
                            url: game.url,
                            issue: "Accuracy is NaN: white=\(report.whiteAccuracy), black=\(report.blackAccuracy)",
                            pgn: pgn
                        ))
                    }

                    if report.keyMoments.isEmpty {
                        zeroKeyMomentReports.append((file: file, url: game.url, pgn: pgn))
                    }
                }
            }
        }

        print("==================================================")
        print("HIKARU QA SCAN SUMMARY")
        print("Total games scanned: \(totalGames)")
        print("Skipped no-PGN games (bughouse and other partner variants): \(skippedNoPGN)")
        print("Skipped variant games (out of product scope): \(skippedVariants.count)")
        print("Total plies replayed: \(totalPlies)")
        print("PGN parse failures: \(pgnParseFailures.count)")
        print("FEN mismatches: \(fenMismatches.count)")
        print("Report building failures: \(reportBuildingFailures.count)")
        print("Zero key moment reports (logged, not asserted): \(zeroKeyMomentReports.count)")
        print("Other issues: \(otherIssues.count)")
        print("==================================================")

        if !pgnParseFailures.isEmpty {
            print("--- PGN PARSE FAILURES (\(pgnParseFailures.count)) ---")
            for (i, failure) in pgnParseFailures.prefix(10).enumerated() {
                print("[\(i + 1)] File: \(failure.file) | URL: \(failure.url)")
                print("Error: \(failure.error)")
                print("PGN snippet: \(String(failure.pgn.prefix(300)))")
                print("--------------------------------------------------")
            }
        }

        if !fenMismatches.isEmpty {
            print("--- FEN MISMATCHES (\(fenMismatches.count)) ---")
            for (i, mismatch) in fenMismatches.prefix(10).enumerated() {
                print("[\(i + 1)] File: \(mismatch.file) | URL: \(mismatch.url)")
                print("Expected: \(mismatch.expected)")
                print("Actual:   \(mismatch.actual)")
                print("PGN snippet: \(String(mismatch.pgn.prefix(300)))")
                print("--------------------------------------------------")
            }
        }

        if !reportBuildingFailures.isEmpty {
            print("--- REPORT BUILDING FAILURES (\(reportBuildingFailures.count)) ---")
            for (i, failure) in reportBuildingFailures.prefix(10).enumerated() {
                print("[\(i + 1)] File: \(failure.file) | URL: \(failure.url) | Reason: \(failure.reason)")
            }
        }

        if !otherIssues.isEmpty {
            print("--- OTHER ISSUES (\(otherIssues.count)) ---")
            for (i, issue) in otherIssues.prefix(10).enumerated() {
                print("[\(i + 1)] File: \(issue.file) | URL: \(issue.url) | Issue: \(issue.issue)")
            }
        }

        if !zeroKeyMomentReports.isEmpty {
            print("--- ZERO KEY MOMENT REPORTS (\(zeroKeyMomentReports.count), first 10) ---")
            for (i, report) in zeroKeyMomentReports.prefix(10).enumerated() {
                print("[\(i + 1)] File: \(report.file) | URL: \(report.url)")
            }
        }

        #expect(pgnParseFailures.isEmpty, "Found \(pgnParseFailures.count) PGN parse failures")
        #expect(fenMismatches.isEmpty, "Found \(fenMismatches.count) FEN mismatches")
        #expect(reportBuildingFailures.isEmpty, "Found \(reportBuildingFailures.count) report building failures")
        #expect(otherIssues.isEmpty, "Found \(otherIssues.count) other issues")
    }

    private func extractTag(name: String, from pgn: String) -> String? {
        let pattern = "\\[\(name) \\\"([^\\\"]+)\\\"\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(pgn.startIndex..<pgn.endIndex, in: pgn)
        guard let match = regex.firstMatch(in: pgn, options: [], range: range),
              let tagRange = Range(match.range(at: 1), in: pgn) else {
            return nil
        }
        return String(pgn[tagRange])
    }
}
