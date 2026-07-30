import Foundation
import Persistence
import Testing
@testable import Chessanto

struct BriefIdentityTests {
    private func game(_ white: String, _ black: String) -> GameRecord {
        GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: white, black: black)
    }

    @Test
    func confirmedChessComAccountAnswersTheQuestion() {
        #expect(
            BriefIdentity.resolve(
                chessComUsername: "WillisLiao",
                isChessComAccountConfirmed: true,
                playerName: nil
            ) == "WillisLiao"
        )
    }

    /// An unconfirmed username is only a typed guess, so it must not decide
    /// which games count as the user's.
    @Test
    func unconfirmedUsernameIsIgnored() {
        #expect(
            BriefIdentity.resolve(
                chessComUsername: "WillisLiao",
                isChessComAccountConfirmed: false,
                playerName: nil
            ) == nil
        )
    }

    @Test
    func chosenPlayerNameStandsInWithoutAnAccount() {
        #expect(
            BriefIdentity.resolve(
                chessComUsername: "",
                isChessComAccountConfirmed: false,
                playerName: "Alice"
            ) == "Alice"
        )
    }

    @Test
    func confirmedAccountWinsOverAChosenName() {
        #expect(
            BriefIdentity.resolve(
                chessComUsername: "WillisLiao",
                isChessComAccountConfirmed: true,
                playerName: "Alice"
            ) == "WillisLiao"
        )
    }

    @Test
    func blankNamesResolveToNoIdentity() {
        #expect(
            BriefIdentity.resolve(
                chessComUsername: "   ",
                isChessComAccountConfirmed: true,
                playerName: "  "
            ) == nil
        )
    }

    @Test
    func candidatesAreRankedByHowOftenTheyPlayed() {
        let games = [
            game("Alice", "Bob"),
            game("Carol", "Alice"),
            game("Alice", "Dave")
        ]

        #expect(BriefIdentity.candidates(in: games).first == "Alice")
        #expect(BriefIdentity.candidates(in: games).count == 4)
    }

    /// One player written two ways is still one player, and the list must
    /// not reorder between launches.
    @Test
    func candidatesFoldCaseAndBreakTiesAlphabetically() {
        let games = [
            game("willisliao", "Zed"),
            game("Anna", "WillisLiao")
        ]

        let candidates = BriefIdentity.candidates(in: games)

        #expect(candidates.first == "willisliao")
        #expect(candidates == ["willisliao", "Anna", "Zed"])
    }

    @Test
    func emptyRegisterOffersNoCandidates() {
        #expect(BriefIdentity.candidates(in: []).isEmpty)
    }
}
