import ChessCore
import Foundation

/// Every fact carries typed fields only (squares, piece kinds, SANs produced
/// by `ChessGame` replay, evals copied from stored records) so the
/// `FactAuditor` can re-verify each one mechanically against `ReportInput` -
/// no report sentence is ever produced from free-composed chess prose.
/// `ply` is the mainline move number (1-based) the fact is about.

/// The mover's win-probability swing across a played move - attached to
/// every key moment.
public struct EvalSwingFact: Sendable, Equatable, Codable {
    public let ply: Int
    public let moverIsWhite: Bool
    public let playedSAN: String
    public let moverWinProbabilityBefore: Double
    public let moverWinProbabilityAfter: Double
    public let classification: MoveClassification
}

/// The engine's preferred alternative to the move actually played, cited
/// from the pre-move position's rank-1 line.
public struct BetterMoveFact: Sendable, Equatable, Codable {
    public let ply: Int
    public let bestMoveSAN: String
    /// Up to 6 plies of the engine's PV starting with `bestMoveSAN`.
    public let lineSANs: [String]
    /// The pre-move position's stored eval, white-perspective - honest by
    /// construction, since it *is* the eval assuming this line is played.
    public let preMoveScoreCentipawns: Int?
    public let preMoveMateIn: Int?
}

/// Fires when the rank-1 PV of the post-move position starts with a
/// capture - the mover "left a piece where it could be taken".
public struct PunishmentFact: Sendable, Equatable, Codable {
    public let ply: Int
    public let refutingSAN: String
    public let capturedPieceKind: PieceKind
    public let capturedSquare: String
    /// Whether the PV's capture square is the square the played move just
    /// moved to (the punished piece is the one that just moved).
    public let capturesJustMovedPiece: Bool
    /// Net material the opponent (refuter) gains over the course of the
    /// replayed PV, relative to the post-move position (positive = good for
    /// the opponent). Only >= the captured piece's value licenses "winning
    /// the {piece}" wording; between 0 and that value licenses "winning
    /// material"; otherwise (a trade or sacrifice line) no material claim
    /// is made.
    public let netMaterialGainForOpponent: Int
}

/// The pre-move position had a forced mate for the mover that the played
/// move let slip.
public struct MissedMateFact: Sendable, Equatable, Codable {
    public let ply: Int
    public let mateInN: Int
    /// Only populated when the auditor can verify the replayed PV actually
    /// ends in checkmate with the expected length - otherwise the mate
    /// count is still stated, but no line is cited.
    public let matingLineSANs: [String]?
}

/// The converse of `MissedMateFact`: the played move let the opponent reach
/// a forced mate that wasn't there before.
public struct AllowedMateFact: Sendable, Equatable, Codable {
    public let ply: Int
    public let mateInN: Int
    public let matingLineSANs: [String]?
}

/// The game's opening name/deviation point, from the bundled opening book.
public struct OpeningFact: Sendable, Equatable, Codable {
    public let eco: String
    public let name: String
    public let deepestBookPly: Int
    /// The move (and ply) where the game left the book, if the game
    /// continued past `deepestBookPly`.
    public let deviationSAN: String?
    public let deviationPly: Int?
}

/// All facts attached to one selected key moment.
public struct KeyMoment: Sendable, Equatable, Codable {
    public let ply: Int
    public let evalSwing: EvalSwingFact
    public let betterMove: BetterMoveFact?
    public let punishment: PunishmentFact?
    public let missedMate: MissedMateFact?
    public let allowedMate: AllowedMateFact?
}
