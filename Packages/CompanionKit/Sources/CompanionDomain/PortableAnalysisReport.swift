import Foundation

public struct PortableGameMetadata: Codable, Equatable, Sendable {
    public let white: String
    public let black: String
    public let result: String
    public let playedAt: Date?
    public let timeControl: String?

    public init(
        white: String,
        black: String,
        result: String,
        playedAt: Date?,
        timeControl: String?
    ) {
        self.white = white
        self.black = black
        self.result = result
        self.playedAt = playedAt
        self.timeControl = timeControl
    }
}

public struct PortablePosition: Codable, Equatable, Sendable {
    public let ply: Int
    public let fen: String
    public let playedSAN: String?

    public init(ply: Int, fen: String, playedSAN: String?) {
        self.ply = ply
        self.fen = fen
        self.playedSAN = playedSAN
    }
}

public struct PortableEvaluation: Codable, Equatable, Sendable {
    public let ply: Int
    public let scoreCentipawns: Int?
    public let mateIn: Int?

    public init(ply: Int, scoreCentipawns: Int?, mateIn: Int?) {
        self.ply = ply
        self.scoreCentipawns = scoreCentipawns
        self.mateIn = mateIn
    }
}

public struct PortableRankedLine: Codable, Equatable, Sendable {
    public let ply: Int
    public let rank: Int
    public let depth: Int
    public let scoreCentipawns: Int?
    public let mateIn: Int?
    public let principalVariationUCI: [String]
    public let principalVariationSAN: [String]

    public init(
        ply: Int,
        rank: Int,
        depth: Int,
        scoreCentipawns: Int?,
        mateIn: Int?,
        principalVariationUCI: [String],
        principalVariationSAN: [String]
    ) {
        self.ply = ply
        self.rank = rank
        self.depth = depth
        self.scoreCentipawns = scoreCentipawns
        self.mateIn = mateIn
        self.principalVariationUCI = principalVariationUCI
        self.principalVariationSAN = principalVariationSAN
    }
}

public struct PortableMoveClassification: Codable, Equatable, Sendable {
    public let ply: Int
    public let canonicalSAN: String
    public let classification: String

    public init(ply: Int, canonicalSAN: String, classification: String) {
        self.ply = ply
        self.canonicalSAN = canonicalSAN
        self.classification = classification
    }
}

public struct PortableOpening: Codable, Equatable, Sendable {
    public let eco: String
    public let name: String
    public let deepestBookPly: Int

    public init(eco: String, name: String, deepestBookPly: Int) {
        self.eco = eco
        self.name = name
        self.deepestBookPly = deepestBookPly
    }
}

public struct PortableKeyMoment: Codable, Equatable, Sendable {
    public let ply: Int
    public let canonicalPlayedSAN: String
    public let classification: String
    public let summary: String
    public let betterLineSAN: [String]
    public let playedContinuationSAN: [String]
    public let narration: AuditedCoachNarration?

    public init(
        ply: Int,
        canonicalPlayedSAN: String,
        classification: String,
        summary: String,
        betterLineSAN: [String],
        playedContinuationSAN: [String],
        narration: AuditedCoachNarration?
    ) {
        self.ply = ply
        self.canonicalPlayedSAN = canonicalPlayedSAN
        self.classification = classification
        self.summary = summary
        self.betterLineSAN = betterLineSAN
        self.playedContinuationSAN = playedContinuationSAN
        self.narration = narration
    }
}

public struct PortableAnalysisReport: Codable, Equatable, Sendable, Identifiable {
    public let protocolVersion: CompanionProtocolVersion
    public let id: ReportID
    public let gameID: CompanionGameID
    public let generatedAt: Date
    public let analysisQuality: CompanionAnalysisQuality
    public let metadata: PortableGameMetadata
    public let pgn: String
    public let positions: [PortablePosition]
    public let evaluations: [PortableEvaluation]
    public let rankedLines: [PortableRankedLine]
    public let classifications: [PortableMoveClassification]
    public let opening: PortableOpening?
    public let keyMoments: [PortableKeyMoment]
    public let takeaways: [String]

    public init(
        protocolVersion: CompanionProtocolVersion,
        id: ReportID,
        gameID: CompanionGameID,
        generatedAt: Date,
        analysisQuality: CompanionAnalysisQuality,
        metadata: PortableGameMetadata,
        pgn: String,
        positions: [PortablePosition],
        evaluations: [PortableEvaluation],
        rankedLines: [PortableRankedLine],
        classifications: [PortableMoveClassification],
        opening: PortableOpening?,
        keyMoments: [PortableKeyMoment],
        takeaways: [String]
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.gameID = gameID
        self.generatedAt = generatedAt
        self.analysisQuality = analysisQuality
        self.metadata = metadata
        self.pgn = pgn
        self.positions = positions
        self.evaluations = evaluations
        self.rankedLines = rankedLines
        self.classifications = classifications
        self.opening = opening
        self.keyMoments = keyMoments
        self.takeaways = takeaways
    }
}
