import ChessComKit
import Foundation
import Testing
@testable import Chessanto

@MainActor
struct ChessComAccountLookupModelTests {
    private struct StubLookup: ChessComAccountLookingUp {
        let result: Result<ChessComAccount, Error>

        func account(username: String) async throws -> ChessComAccount {
            try result.get()
        }
    }

    private struct DelayedLookup: ChessComAccountLookingUp {
        func account(username: String) async throws -> ChessComAccount {
            try await Task.sleep(
                for: username == "older" ? .milliseconds(80) : .milliseconds(5)
            )
            return ChessComAccount(
                username: username,
                name: nil,
                countryCode: nil,
                profileURL: URL(string: "https://www.chess.com/member/\(username)")!,
                ratings: ChessComRatings()
            )
        }
    }

    @Test func lookupPresentsCandidateWithoutConfirmingIt() async {
        let account = ChessComAccount(
            username: "WillisLiao",
            name: "Willis Liao",
            countryCode: "TW",
            profileURL: URL(string: "https://www.chess.com/member/willisliao")!,
            ratings: ChessComRatings(rapid: 307, blitz: 231, bullet: 137)
        )
        let model = ChessComAccountLookupModel(
            lookup: StubLookup(result: .success(account))
        )

        await model.lookUp("  willisliao ")

        #expect(model.state == .candidate(account))
        #expect(model.confirmedCandidate == nil)

        model.confirmCandidate()

        #expect(model.confirmedCandidate == account)
        #expect(model.state == .confirmed(account))
    }

    @Test func slowerOlderLookupCannotReplaceTheNewestCandidate() async {
        let model = ChessComAccountLookupModel(lookup: DelayedLookup())

        let olderLookup = Task {
            await model.lookUp("older")
        }
        try? await Task.sleep(for: .milliseconds(10))
        await model.lookUp("newer")
        await olderLookup.value

        guard case .candidate(let account) = model.state else {
            Issue.record("Expected the newer lookup candidate")
            return
        }
        #expect(account.username == "newer")
    }
}
