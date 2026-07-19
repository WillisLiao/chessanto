import Foundation

public enum NarrationSource: String, Codable, Sendable {
    case verifiedCoach
    case engineVerifiedFallback
    case deterministicPrecheck
}

public enum CoachEmotion: String, Codable, CaseIterable, Sendable {
    case resting
    case thoughtful
    case concerned
    case encouraging
    case instructive
    case delighted
}

public struct AuditedCoachNarration: Codable, Equatable, Sendable, Identifiable {
    public let id: NarrationID
    public let text: String
    public let source: NarrationSource
    public let mood: CoachEmotion

    public init(
        id: NarrationID,
        text: String,
        source: NarrationSource,
        mood: CoachEmotion
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.mood = mood
    }
}

public enum CoachSpeechPhase: Equatable, Sendable {
    case idle
    case speaking
    case paused
}

public struct CoachPresentationState: Equatable, Sendable {
    public let narration: AuditedCoachNarration?
    public let emotion: CoachEmotion
    public let speechPhase: CoachSpeechPhase

    public init(
        narration: AuditedCoachNarration?,
        emotion: CoachEmotion,
        speechPhase: CoachSpeechPhase
    ) {
        self.narration = narration
        self.emotion = emotion
        self.speechPhase = speechPhase
    }
}
