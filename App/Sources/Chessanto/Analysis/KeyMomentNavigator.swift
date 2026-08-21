import AnalysisKit
import Foundation

/// Picks the key moment to jump to from wherever the board currently is.
///
/// Key moments are the reason the report exists, and reaching them meant
/// finding and clicking a card in the right pane. Up and down should walk
/// them the way left and right walk the moves.
enum KeyMomentNavigator {
    /// The first key moment strictly after `ply`, or `nil` at the last one.
    /// Deliberately not wrapping: silently jumping from the last mistake in
    /// the game back to the first reads as the board losing its place.
    static func next(after ply: Int, in moments: [KeyMoment]) -> KeyMoment? {
        moments.sorted { $0.ply < $1.ply }.first { $0.ply > ply }
    }

    /// The last key moment strictly before `ply`, or `nil` at the first one.
    static func previous(before ply: Int, in moments: [KeyMoment]) -> KeyMoment? {
        moments.sorted { $0.ply < $1.ply }.last { $0.ply < ply }
    }
}
