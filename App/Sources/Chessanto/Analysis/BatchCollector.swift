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
}

/// Whether an engine update belongs to the generation currently being shown
/// live, factored out so it's unit-testable without a live engine.
struct LiveGenerationFilter {
    let liveGeneration: Int

    func isCurrent(_ updateGeneration: Int) -> Bool {
        updateGeneration == liveGeneration
    }
}
