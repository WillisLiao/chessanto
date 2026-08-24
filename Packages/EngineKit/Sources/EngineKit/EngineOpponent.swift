import Foundation

/// Protocol for generating engine opponent replies during a live game session.
public protocol EngineOpponent: Sendable {
    /// Generates a move for the side to move in `fen` at the specified `strength`.
    /// Returns the UCI representation of the chosen move (e.g. `"e7e5"`, `"e7e8q"`).
    func generateMove(in fen: String, strength: EngineStrength) async throws -> String
}
