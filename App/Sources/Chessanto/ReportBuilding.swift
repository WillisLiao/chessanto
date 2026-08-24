import AnalysisKit
import ChessCore
import Persistence

/// The `AnalysisRecord` -> `ReportInput` -> `GameReport` mapping, shared
/// between `GameReplayViewModel.buildReport()` (one loaded game) and the
/// dashboard (every analyzed game) - one implementation of "replay the PGN,
/// group analysis rows by ply, hand it to `ReportBuilder`", not two.
enum ReportBuilding {
    /// Resolves the user's numeric rating in a game from their username matching White or Black.
    static func userRating(in record: GameRecord, username: String?) -> Int? {
        guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
            return nil
        }
        if record.white.caseInsensitiveCompare(username) == .orderedSame {
            return record.whiteRating
        }
        if record.black.caseInsensitiveCompare(username) == .orderedSame {
            return record.blackRating
        }
        return nil
    }

    /// Resolves the rating register given user profile and game/rating context.
    ///
    /// If profile or rating context is available, resolves via `RatingRegister.resolve`.
    /// When genuinely no profile or rating context exists (e.g. tests or callers omitting it),
    /// preserves the `.advanced` default.
    static func resolveRegister(
        userProfile: UserProfileRecord? = nil,
        ratingBand: String? = nil,
        userRating: Int? = nil,
        record: GameRecord? = nil,
        username: String? = nil
    ) -> RatingRegister {
        let band = ratingBand ?? userProfile?.ratingBand
        let rating = userRating ?? {
            guard let record else { return nil }
            let name = username ?? userProfile?.chessComUsername
            return self.userRating(in: record, username: name)
        }()
        guard band != nil || rating != nil else {
            return .advanced
        }
        return RatingRegister.resolve(ratingBand: band ?? "adaptive", userRating: rating)
    }

    /// `nil` if the PGN doesn't parse, the game has no moves, or analysis
    /// coverage is incomplete (some ply has no rows at all).
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

    /// `nil` under the same conditions as `buildInput`.
    static func buildReport(
        record: GameRecord,
        analysisRows: [AnalysisRecord],
        chessComUsername: String?,
        userProfile: UserProfileRecord? = nil,
        register: RatingRegister? = nil
    ) -> GameReport? {
        guard let input = buildInput(record: record, analysisRows: analysisRows, chessComUsername: chessComUsername) else {
            return nil
        }
        let resolvedRegister = register ?? resolveRegister(
            userProfile: userProfile,
            record: record,
            username: chessComUsername
        )
        return ReportBuilder.build(
            input: input,
            openingBook: OpeningBook.shared,
            register: resolvedRegister
        )
    }
}
