import EngineKit

/// Accumulates the latest info per MultiPV rank for one fixed-time search,
/// resolving to a final ranked line list once the terminating bestmove
/// arrives. Pure bookkeeping, factored out so it's unit-testable without a
/// live engine.
struct BatchCollector {
    private var infosByRank: [Int: AnalysisEngine.EngineInfo] = [:]

    mutating func record(_ info: AnalysisEngine.EngineInfo) {
        infosByRank[info.multiPVRank ?? 1] = info
    }

    /// The latest info for each rank that reported one, ordered by rank.
    var rankedInfos: [AnalysisEngine.EngineInfo] {
        infosByRank.keys.sorted().compactMap { infosByRank[$0] }
    }

    /// Whether every rank that has reported at all has reached `depth`.
    ///
    /// A depth-budgeted search is only reproducible if the iteration it was
    /// asked for is the one that gets stored, and the terminating
    /// `bestmove` can overtake that iteration's own `info` lines in
    /// delivery (chesskit-engine dispatches every response through its own
    /// unstructured `Task`, so responses are not ordered). Measured on the
    /// start position at depth 12, the deepest rank-one info was lost in
    /// three of eight runs. This is how the caller tells whether the
    /// iteration it paid for actually landed.
    func hasReachedDepth(_ depth: Int) -> Bool {
        guard depth > 0, !infosByRank.isEmpty else { return true }
        return infosByRank.values.allSatisfy { ($0.depth ?? 0) >= depth }
    }
}

/// Whether an engine update belongs to the generation currently being shown
/// live, factored out so it's unit-testable without a live engine.
struct LiveGenerationFilter {
    let liveGeneration: Int

    func isCurrent(_ updateGeneration: Int) -> Bool {
        updateGeneration == liveGeneration
    }
}
