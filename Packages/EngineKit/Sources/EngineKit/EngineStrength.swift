import Foundation

/// Strength configuration for an engine opponent.
///
/// Maps human-friendly difficulty presets to Stockfish UCI `Skill Level` (0-20),
/// a search depth cap, a wall-clock movetime ceiling, and an estimated Elo rating.
public struct EngineStrength: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let skillLevel: Int
    public let depth: Int
    public let movetimeCeilingMilliseconds: Int
    public let estimatedElo: Int?

    public init(
        id: String,
        name: String,
        skillLevel: Int,
        depth: Int,
        movetimeCeilingMilliseconds: Int,
        estimatedElo: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.skillLevel = max(0, min(20, skillLevel))
        self.depth = max(1, depth)
        self.movetimeCeilingMilliseconds = max(50, movetimeCeilingMilliseconds)
        self.estimatedElo = estimatedElo
    }

    public static let beginner = EngineStrength(
        id: "beginner",
        name: "Beginner",
        skillLevel: 0,
        depth: 3,
        movetimeCeilingMilliseconds: 500,
        estimatedElo: 600
    )

    public static let casual = EngineStrength(
        id: "casual",
        name: "Casual",
        skillLevel: 4,
        depth: 5,
        movetimeCeilingMilliseconds: 750,
        estimatedElo: 1000
    )

    public static let intermediate = EngineStrength(
        id: "intermediate",
        name: "Intermediate",
        skillLevel: 9,
        depth: 8,
        movetimeCeilingMilliseconds: 1000,
        estimatedElo: 1400
    )

    public static let advanced = EngineStrength(
        id: "advanced",
        name: "Advanced",
        skillLevel: 14,
        depth: 12,
        movetimeCeilingMilliseconds: 1500,
        estimatedElo: 1800
    )

    public static let master = EngineStrength(
        id: "master",
        name: "Master",
        skillLevel: 20,
        depth: 18,
        movetimeCeilingMilliseconds: 2500,
        estimatedElo: 2400
    )

    public static let allCases: [EngineStrength] = [
        .beginner,
        .casual,
        .intermediate,
        .advanced,
        .master
    ]
}
