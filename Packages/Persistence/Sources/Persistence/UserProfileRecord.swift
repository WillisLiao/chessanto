import Foundation
import GRDB

/// Single-row user settings/profile. The row always has id = 1; there is
/// only ever one user of this local app.
public struct UserProfileRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "userProfile"

    public var id: Int64
    public var chessComUsername: String?
    public var isChessComAccountConfirmed: Bool
    public var ratingBand: String
    public var coachModel: String?
    public var coachEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var analysisQuality: String
    public var boardTheme: String
    public var moveNotationStyle: String
    /// Board move/capture sounds. Defaults on, matching every mainstream
    /// chess board - a learner tracking what just happened is the reason
    /// the sounds exist.
    public var boardSoundsEnabled: Bool

    public init(
        id: Int64 = 1,
        chessComUsername: String? = nil,
        isChessComAccountConfirmed: Bool = false,
        ratingBand: String = "adaptive",
        coachModel: String? = nil,
        coachEnabled: Bool = false,
        hasCompletedOnboarding: Bool = false,
        analysisQuality: String = "standard",
        boardTheme: String = "classic",
        moveNotationStyle: String = "standard",
        boardSoundsEnabled: Bool = true
    ) {
        self.id = id
        self.chessComUsername = chessComUsername
        self.isChessComAccountConfirmed = isChessComAccountConfirmed
        self.ratingBand = ratingBand
        self.coachModel = coachModel
        self.coachEnabled = coachEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.analysisQuality = analysisQuality
        self.boardTheme = boardTheme
        self.moveNotationStyle = moveNotationStyle
        self.boardSoundsEnabled = boardSoundsEnabled
    }
}
