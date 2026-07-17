import ChessCore
import Foundation

/// One engine line at some rank (1-3; fewer when the position has fewer
/// legal moves) for a position, white-perspective per the DB convention.
public struct RankedLine: Sendable, Codable, Equatable {
    public let rank: Int
    public let scoreCentipawns: Int?
    public let mateIn: Int?
    public let principalVariationUCI: [String]
    public let depth: Int

    public init(rank: Int, scoreCentipawns: Int?, mateIn: Int?, principalVariationUCI: [String], depth: Int) {
        self.rank = rank
        self.scoreCentipawns = scoreCentipawns
        self.mateIn = mateIn
        self.principalVariationUCI = principalVariationUCI
        self.depth = depth
    }

    public var rank1Evaluation: PlyEvaluation {
        PlyEvaluation(scoreCentipawns: scoreCentipawns, mateIn: mateIn, bestMoveUCI: principalVariationUCI.first)
    }
}

/// All stored analysis for one ply (a position in the game), plus the move
/// that was actually played to reach it.
public struct PlyRecord: Sendable, Codable, Equatable {
    public let fen: String
    /// Ranked lines, sorted by `rank` ascending; rank 1 is the engine's best.
    public let lines: [RankedLine]
    /// The UCI of the mainline move that produced this ply, `nil` at ply 0.
    public let playedUCI: String?

    public init(fen: String, lines: [RankedLine], playedUCI: String?) {
        self.fen = fen
        self.lines = lines
        self.playedUCI = playedUCI
    }

    public var rank1: RankedLine? {
        lines.first { $0.rank == 1 }
    }
}

/// The plain, DB-free input to the M5 report pipeline. The app maps
/// `AnalysisRecord`s (grouped by ply) into this; `AnalysisKit` never
/// imports `Persistence` or `EngineKit` to build a report.
public struct ReportInput: Sendable, Codable, Equatable {
    /// Index 0 = starting position; `plies[p]` is the position after mainline
    /// move `p` (matching `GameReplayViewModel`'s existing convention).
    public let plies: [PlyRecord]
    public let whiteName: String
    public let blackName: String
    /// PGN `Result` tag verbatim (e.g. `"1-0"`, `"0-1"`, `"1/2-1/2"`, `"*"`).
    public let result: String
    /// Case-insensitively matched against `whiteName`/`blackName` to decide
    /// whether templates may address a player as "you" - a rendering
    /// choice, not a chess claim, so it needs no audit.
    public let chessComUsername: String?

    public init(plies: [PlyRecord], whiteName: String, blackName: String, result: String, chessComUsername: String?) {
        self.plies = plies
        self.whiteName = whiteName
        self.blackName = blackName
        self.result = result
        self.chessComUsername = chessComUsername
    }

    /// Whether every ply has at least a rank-1 record - the report requires
    /// a fully analyzed game.
    public var isFullyAnalyzed: Bool {
        !plies.isEmpty && plies.allSatisfy { $0.rank1 != nil }
    }

    /// Whether White is the mover of move `p` (1-based), read from the
    /// side-to-move field of the FEN *before* the move (`plies[p - 1].fen`) -
    /// correct for FEN-start games, unlike inferring from ply parity.
    public func moverIsWhite(atPly p: Int) -> Bool {
        let fen = plies[p - 1].fen
        let fields = fen.split(separator: " ")
        guard fields.count > 1 else { return p % 2 == 1 }
        return fields[1] == "w"
    }

    public func playerName(isWhite: Bool) -> String {
        isWhite ? whiteName : blackName
    }

    /// Whether `playerName` may be addressed as "you" in report text.
    public func isUser(isWhite: Bool) -> Bool {
        guard let chessComUsername, !chessComUsername.isEmpty else { return false }
        return playerName(isWhite: isWhite).caseInsensitiveCompare(chessComUsername) == .orderedSame
    }
}
