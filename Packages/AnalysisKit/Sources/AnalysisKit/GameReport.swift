import Foundation

/// Count of mainline moves at one classification, for one player.
public struct ClassificationCount: Sendable, Equatable, Codable {
    public let classification: MoveClassification
    public let count: Int
}

/// The full rule-based coaching report for one analyzed game: everything
/// `ReportText` needs to render, and nothing more - every field here is
/// either copied verbatim from `ReportInput` or produced by a `Fact`
/// detector + the `FactAuditor` gate.
public struct GameReport: Sendable, Equatable {
    public let whiteName: String
    public let blackName: String
    public let result: String
    /// Case-insensitively matched against `whiteName`/`blackName` by
    /// `ReportText` to decide whether to address that player as "you" - a
    /// rendering choice, not a chess claim.
    public let chessComUsername: String?
    public let whiteAccuracy: Double
    public let blackAccuracy: Double
    public let whiteClassificationCounts: [ClassificationCount]
    public let blackClassificationCounts: [ClassificationCount]
    public let opening: OpeningFact?
    public let keyMoments: [KeyMoment]
    public let takeaways: [String]
}
