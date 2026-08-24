import Foundation
import ChessComKit
import ChessCore
import AnalysisKit
import Persistence

struct FailureRecord: Sendable {
    let gameURL: String
    let archiveURL: String
    let errorDescription: String
    let pgn: String
}

enum QAHelper {
    static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\w+)\s+"([^"]*)"\]"#
    )

    static func parseTags(from pgn: String) -> [String: String] {
        guard pgn.contains("[") else { return [:] }
        let range = NSRange(pgn.startIndex..., in: pgn)
        var tags: [String: String] = [:]
        tagPattern.enumerateMatches(in: pgn, range: range) { match, _, _ in
            guard let match, let keyRange = Range(match.range(at: 1), in: pgn),
                  let valueRange = Range(match.range(at: 2), in: pgn) else { return }
            tags[String(pgn[keyRange])] = String(pgn[valueRange])
        }
        return tags
    }

    static func date(from tags: [String: String]) -> Date? {
        guard let dateString = tags["Date"] else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateString)
    }

    static func buildInput(record: GameRecord, analysisRows: [AnalysisRecord], chessComUsername: String?) -> ReportInput? {
        guard let game = try? ChessGame(pgn: record.pgn) else { return nil }
        let moveIndices = [game.startIndex] + game.mainlineIndices
        guard moveIndices.count > 1 else { return nil }

        let fens = moveIndices.map { game.fen(at: $0) ?? "" }
        let playedUCIs = moveIndices.map { game.uciMove(at: $0) }

        var byPly: [Int: [AnalysisRecord]] = [:]
        for row in analysisRows {
            byPly[row.plyIndex, default: []].append(row)
        }
        guard fens.indices.allSatisfy({ byPly[$0] != nil }) else { return nil }

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

        return ReportInput(
            plies: plies, whiteName: record.white, blackName: record.black,
            result: record.result ?? "*", chessComUsername: chessComUsername
        )
    }

    static func buildReport(
        record: GameRecord,
        analysisRows: [AnalysisRecord],
        chessComUsername: String?,
        register: RatingRegister = .advanced
    ) -> GameReport? {
        guard let input = buildInput(record: record, analysisRows: analysisRows, chessComUsername: chessComUsername) else {
            return nil
        }
        return ReportBuilder.build(
            input: input,
            openingBook: OpeningBook.shared,
            register: register
        )
    }
}

actor QARunner {
    var totalArchives = 0
    var processedArchives = 0
    var totalGames = 0
    var totalPlies = 0
    var failedGames: [FailureRecord] = []
    var fenMismatches: [FailureRecord] = []
    var replayLineMismatches: [FailureRecord] = []
    var reportFailures: [FailureRecord] = []

    func incrementArchives() {
        processedArchives += 1
    }

    func recordGameSuccess(plies: Int) {
        totalGames += 1
        totalPlies += plies
    }

    func recordParseFailure(_ failure: FailureRecord) {
        totalGames += 1
        failedGames.append(failure)
    }

    func recordFENMismatch(_ failure: FailureRecord) {
        fenMismatches.append(failure)
    }

    func recordReplayLineMismatch(_ failure: FailureRecord) {
        replayLineMismatches.append(failure)
    }

    func recordReportFailure(_ failure: FailureRecord) {
        reportFailures.append(failure)
    }

    func printProgress() {
        print("[\(processedArchives)/\(totalArchives) archives] Games: \(totalGames) (failed: \(failedGames.count), fenMismatches: \(fenMismatches.count), replayFailures: \(replayLineMismatches.count), reportFailures: \(reportFailures.count)) Plies: \(totalPlies)")
    }
}

func fetchWithRetry(
    client: ChessComClient,
    url: String,
    maxRetries: Int = 5
) async throws -> [ChessComGame] {
    for attempt in 1...maxRetries {
        do {
            return try await client.games(archiveURL: url)
        } catch {
            if attempt == maxRetries {
                throw error
            }
            let delaySeconds = Double(attempt) * 1.5
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
    }
    return []
}

func validateGame(
    game: ChessComGame,
    archiveURL: String,
    runner: QARunner
) async {
    let pgn = game.pgn
    let tags = QAHelper.parseTags(from: pgn)

    let record = GameRecord(
        source: .chessCom,
        sourceURL: game.url,
        pgn: pgn,
        white: tags["White"] ?? game.white.username,
        black: tags["Black"] ?? game.black.username,
        whiteRating: tags["WhiteElo"].flatMap(Int.init) ?? game.white.rating,
        blackRating: tags["BlackElo"].flatMap(Int.init) ?? game.black.rating,
        result: tags["Result"],
        timeControl: tags["TimeControl"] ?? game.timeControl,
        playedAt: QAHelper.date(from: tags) ?? game.endTime
    )

    let chessGame: ChessGame

    do {
        // Test parsing
        chessGame = try ChessGame(pgn: pgn)
    } catch {
        await runner.recordParseFailure(FailureRecord(
            gameURL: game.url,
            archiveURL: archiveURL,
            errorDescription: "PGN parse threw: \(error)",
            pgn: pgn
        ))
        return
    }

    let moveIndices = [chessGame.startIndex] + chessGame.mainlineIndices
    let plyCount = moveIndices.count

    // Validate all plies and FENs
    var fens: [String] = []
    var playedUCIs: [String] = []

    for (index, moveIndex) in moveIndices.enumerated() {
        guard let fen = chessGame.fen(at: moveIndex) else {
            await runner.recordParseFailure(FailureRecord(
                gameURL: game.url,
                archiveURL: archiveURL,
                errorDescription: "nil FEN at ply \(index)",
                pgn: pgn
            ))
            return
        }

        let fenTokens = fen.split(separator: " ")
        if fenTokens.count != 6 {
            await runner.recordParseFailure(FailureRecord(
                gameURL: game.url,
                archiveURL: archiveURL,
                errorDescription: "invalid FEN field count (\(fenTokens.count)) at ply \(index): \(fen)",
                pgn: pgn
            ))
            return
        }

        fens.append(fen)

        if index > 0 {
            guard let san = chessGame.san(at: moveIndex), !san.isEmpty else {
                await runner.recordParseFailure(FailureRecord(
                    gameURL: game.url,
                    archiveURL: archiveURL,
                    errorDescription: "nil or empty SAN at ply \(index)",
                    pgn: pgn
                ))
                return
            }

            guard let uci = chessGame.uciMove(at: moveIndex), uci.count >= 4, uci.count <= 5 else {
                await runner.recordParseFailure(FailureRecord(
                    gameURL: game.url,
                    archiveURL: archiveURL,
                    errorDescription: "invalid UCI move at ply \(index): \(String(describing: chessGame.uciMove(at: moveIndex)))",
                    pgn: pgn
                ))
                return
            }

            playedUCIs.append(uci)
        }
    }

    // Compare final FEN with CurrentPosition tag if available
    if let currentPos = tags["CurrentPosition"], !currentPos.isEmpty, let finalFEN = fens.last {
        let expectedParts = currentPos.split(separator: " ")
        let actualParts = finalFEN.split(separator: " ")
        if expectedParts.count >= 2 && actualParts.count >= 2 {
            // Compare piece placement and active color
            if expectedParts[0] != actualParts[0] || expectedParts[1] != actualParts[1] {
                await runner.recordFENMismatch(FailureRecord(
                    gameURL: game.url,
                    archiveURL: archiveURL,
                    errorDescription: "CurrentPosition mismatch: expected '\(currentPos)', got '\(finalFEN)'",
                    pgn: pgn
                ))
            }
        }
    }

    // Verify full game replay via ChessGame.replayLine
    if !playedUCIs.isEmpty, let startFEN = fens.first {
        let replayedPositions = ChessGame.replayLine(fromUCI: playedUCIs, startingFEN: startFEN)
        if replayedPositions.count != playedUCIs.count {
            await runner.recordReplayLineMismatch(FailureRecord(
                gameURL: game.url,
                archiveURL: archiveURL,
                errorDescription: "replayLine returned \(replayedPositions.count) moves for \(playedUCIs.count) played moves",
                pgn: pgn
            ))
        }
    }

    // Opening book lookup
    _ = OpeningBook.shared.lookup(fens: fens)

    // Build synthetic analysis records to test ReportBuilding and all ThemeDetectors
    if plyCount > 1 {
        var analysisRows: [AnalysisRecord] = []
        for ply in 0..<plyCount {
            let fen = fens[ply]
            let playedUCI = ply == 0 ? nil : playedUCIs[ply - 1]
            let pvString = playedUCI ?? "e2e4"
            analysisRows.append(AnalysisRecord(
                id: nil,
                gameId: 1,
                plyIndex: ply,
                fen: fen,
                depth: 16,
                scoreCentipawns: (ply % 2 == 0) ? 20 : -20,
                mateIn: nil,
                principalVariation: pvString,
                multiPVRank: 1,
                qualityPreset: nil
            ))
            // Add rank 2 and 3 for MultiPV coverage
            analysisRows.append(AnalysisRecord(
                id: nil,
                gameId: 1,
                plyIndex: ply,
                fen: fen,
                depth: 16,
                scoreCentipawns: (ply % 2 == 0) ? 10 : -10,
                mateIn: nil,
                principalVariation: "g1f3",
                multiPVRank: 2,
                qualityPreset: nil
            ))
            analysisRows.append(AnalysisRecord(
                id: nil,
                gameId: 1,
                plyIndex: ply,
                fen: fen,
                depth: 16,
                scoreCentipawns: 0,
                mateIn: nil,
                principalVariation: "c2c4",
                multiPVRank: 3,
                qualityPreset: nil
            ))
        }

        if let input = QAHelper.buildInput(record: record, analysisRows: analysisRows, chessComUsername: "Hikaru") {
            let reportAdv = ReportBuilder.build(input: input, openingBook: OpeningBook.shared, register: .advanced)
            let reportBeg = ReportBuilder.build(input: input, openingBook: OpeningBook.shared, register: .beginner)
            let reportInt = ReportBuilder.build(input: input, openingBook: OpeningBook.shared, register: .intermediate)

            if reportAdv == nil || reportBeg == nil || reportInt == nil {
                await runner.recordReportFailure(FailureRecord(
                    gameURL: game.url,
                    archiveURL: archiveURL,
                    errorDescription: "ReportBuilder returned nil report",
                    pgn: pgn
                ))
            }
        } else {
            await runner.recordReportFailure(FailureRecord(
                gameURL: game.url,
                archiveURL: archiveURL,
                errorDescription: "buildInput returned nil",
                pgn: pgn
            ))
        }
    }

    await runner.recordGameSuccess(plies: plyCount)
}

@main
struct HikaruQAMain {
    static func main() async {
        print("Starting QA run on Hikaru public archives...")
        let client = ChessComClient(contactInfo: "chessanto-qa-hikaru")
        let runner = QARunner()

        do {
            let archives = try await client.archiveURLs(username: "hikaru")
            print("Found \(archives.count) monthly archives for user Hikaru.")

            // Check if archive limit is requested via arguments
            var targetArchives = archives
            var workerCount = 6

            for (idx, arg) in CommandLine.arguments.enumerated() {
                if arg == "--limit", idx + 1 < CommandLine.arguments.count, let limit = Int(CommandLine.arguments[idx + 1]) {
                    targetArchives = Array(archives.suffix(limit))
                    print("Limiting to last \(limit) archives (\(targetArchives.count) total)")
                }
                if arg == "--workers", idx + 1 < CommandLine.arguments.count, let w = Int(CommandLine.arguments[idx + 1]) {
                    workerCount = w
                }
            }

            await runner.setTotalArchives(targetArchives.count)

            let startTime = Date()

            // Fetch and process archives concurrently with a bounded task group
            await withTaskGroup(of: Void.self) { group in
                var archiveIterator = targetArchives.makeIterator()

                for _ in 0..<workerCount {
                    if let archiveURL = archiveIterator.next() {
                        group.addTask {
                            await processArchive(archiveURL: archiveURL, client: client, runner: runner)
                        }
                    }
                }

                while let _ = await group.next() {
                    if let nextArchiveURL = archiveIterator.next() {
                        group.addTask {
                            await processArchive(archiveURL: nextArchiveURL, client: client, runner: runner)
                        }
                    }
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("\n================ QA RUN SUMMARY ================")
            print("Elapsed time: \(String(format: "%.2f", elapsed))s")
            await runner.printFinalSummary()

        } catch {
            print("Fatal error during QA run: \(error)")
            exit(1)
        }
    }

    static func processArchive(archiveURL: String, client: ChessComClient, runner: QARunner) async {
        do {
            let games = try await fetchWithRetry(client: client, url: archiveURL)
            for game in games {
                await validateGame(game: game, archiveURL: archiveURL, runner: runner)
            }
        } catch {
            print("Failed to fetch archive: \(archiveURL): \(error)")
        }
        await runner.incrementArchives()
        await runner.printProgress()
    }
}

extension QARunner {
    func setTotalArchives(_ count: Int) {
        self.totalArchives = count
    }

    func printFinalSummary() {
        print("Archives processed: \(processedArchives)/\(totalArchives)")
        print("Total games validated: \(totalGames)")
        print("Total plies replayed: \(totalPlies)")
        print("Failed PGN parses: \(failedGames.count)")
        print("FEN mismatches: \(fenMismatches.count)")
        print("ReplayLine mismatches: \(replayLineMismatches.count)")
        print("Report building failures: \(reportFailures.count)")

        if !failedGames.isEmpty {
            print("\n--- Failed Games Sample (first 10) ---")
            for (idx, fail) in failedGames.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(fail.gameURL)")
                print("Error: \(fail.errorDescription)")
                print("PGN:\n\(fail.pgn)\n")
            }
        }

        if !fenMismatches.isEmpty {
            print("\n--- FEN Mismatches Sample (first 10) ---")
            for (idx, fail) in fenMismatches.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(fail.gameURL)")
                print("Error: \(fail.errorDescription)")
                print("PGN:\n\(fail.pgn)\n")
            }
        }

        if !replayLineMismatches.isEmpty {
            print("\n--- ReplayLine Mismatches Sample (first 10) ---")
            for (idx, fail) in replayLineMismatches.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(fail.gameURL)")
                print("Error: \(fail.errorDescription)")
                print("PGN:\n\(fail.pgn)\n")
            }
        }

        if !reportFailures.isEmpty {
            print("\n--- Report Failures Sample (first 10) ---")
            for (idx, fail) in reportFailures.prefix(10).enumerated() {
                print("[\(idx + 1)] URL: \(fail.gameURL)")
                print("Error: \(fail.errorDescription)")
                print("PGN:\n\(fail.pgn)\n")
            }
        }
    }
}
