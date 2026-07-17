import Foundation

/// The one tool the coach LLM may call (PLAN.md's Layer 3): evaluate a
/// position reached by playing `movesUCI` from `fen`. CoachKit depends on
/// this only as a protocol - the app implements it against the real
/// `AnalysisEngine` (`EngineService.coachEvaluate`); CoachKit's own tests
/// use a scripted stub.
public protocol EngineToolExecutor: Sendable {
    func evaluate(fen: String, movesUCI: [String]) async throws -> EngineToolResult
}

/// The result of one `evaluate` tool call: the same vocabulary as
/// `RankedLine` (white-perspective per the DB convention), plus the
/// resulting FEN so it can be added as a fresh `CoachVerificationAnchor`.
public struct EngineToolResult: Sendable, Equatable {
    public let resultingFEN: String
    public let scoreCentipawnsWhitePerspective: Int?
    public let mateInWhitePerspective: Int?
    public let evalLabel: String
    public let principalVariationUCI: [String]
    public let principalVariationSAN: [String]
    public let depth: Int

    public init(
        resultingFEN: String,
        scoreCentipawnsWhitePerspective: Int?,
        mateInWhitePerspective: Int?,
        evalLabel: String,
        principalVariationUCI: [String],
        principalVariationSAN: [String],
        depth: Int
    ) {
        self.resultingFEN = resultingFEN
        self.scoreCentipawnsWhitePerspective = scoreCentipawnsWhitePerspective
        self.mateInWhitePerspective = mateInWhitePerspective
        self.evalLabel = evalLabel
        self.principalVariationUCI = principalVariationUCI
        self.principalVariationSAN = principalVariationSAN
        self.depth = depth
    }
}

/// A typed error result returned to the LLM (never thrown across the tool
/// boundary) when its tool-call arguments don't replay - fact 10 showed
/// small models mangle arguments routinely, so the engine must never see
/// garbage (NEXT-SESSION-M6.md's engine-tool-loop decisions).
public struct EngineToolArgumentError: Error, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
