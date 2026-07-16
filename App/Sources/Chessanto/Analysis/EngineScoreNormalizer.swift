import Foundation

/// Normalizes side-to-move-relative engine scores to white-perspective
/// values, per the fixed M2 convention: DB (and the live eval bar) only
/// ever store/show white-perspective centipawns and mate counts.
enum EngineScoreNormalizer {
    static func isBlackToMove(fen: String) -> Bool {
        let fields = fen.split(separator: " ", maxSplits: 2)
        return fields.count > 1 && fields[1] == "b"
    }

    static func whitePerspectiveScore(_ scoreCentipawns: Int?, fen: String) -> Int? {
        guard let scoreCentipawns else { return nil }
        return isBlackToMove(fen: fen) ? -scoreCentipawns : scoreCentipawns
    }

    static func whitePerspectiveMate(_ mateIn: Int?, fen: String) -> Int? {
        guard let mateIn else { return nil }
        return isBlackToMove(fen: fen) ? -mateIn : mateIn
    }
}
