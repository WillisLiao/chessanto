import AnalysisKit
import Foundation
import Testing
@testable import Chessanto

struct KeyMomentNavigatorTests {
    /// `KeyMoment`'s memberwise initializer is internal to AnalysisKit, so
    /// fixtures are decoded rather than constructed. Only `ply` matters to
    /// navigation; the rest is the report's business.
    private func moment(ply: Int) throws -> KeyMoment {
        let json = """
        {
          "ply": \(ply),
          "evalSwing": {
            "ply": \(ply),
            "moverIsWhite": \(ply % 2 == 1),
            "playedSAN": "e4",
            "moverWinProbabilityBefore": 50,
            "moverWinProbabilityAfter": 30,
            "classification": "mistake"
          }
        }
        """
        return try JSONDecoder().decode(KeyMoment.self, from: Data(json.utf8))
    }

    @Test
    func nextFindsTheFirstMomentAfterThePly() throws {
        let moments = [try moment(ply: 4), try moment(ply: 12), try moment(ply: 30)]

        #expect(KeyMomentNavigator.next(after: 4, in: moments)?.ply == 12)
        #expect(KeyMomentNavigator.next(after: 0, in: moments)?.ply == 4)
        #expect(KeyMomentNavigator.next(after: 13, in: moments)?.ply == 30)
    }

    @Test
    func previousFindsTheLastMomentBeforeThePly() throws {
        let moments = [try moment(ply: 4), try moment(ply: 12), try moment(ply: 30)]

        #expect(KeyMomentNavigator.previous(before: 30, in: moments)?.ply == 12)
        #expect(KeyMomentNavigator.previous(before: 13, in: moments)?.ply == 12)
        #expect(KeyMomentNavigator.previous(before: 5, in: moments)?.ply == 4)
    }

    /// Wrapping would jump from the last mistake in the game back to the
    /// first, which reads as the board losing its place rather than as
    /// navigation.
    @Test
    func navigationStopsAtTheEndsInsteadOfWrapping() throws {
        let moments = [try moment(ply: 4), try moment(ply: 12)]

        #expect(KeyMomentNavigator.next(after: 12, in: moments) == nil)
        #expect(KeyMomentNavigator.previous(before: 4, in: moments) == nil)
    }

    @Test
    func unsortedMomentsAreStillWalkedInPlyOrder() throws {
        let moments = [try moment(ply: 30), try moment(ply: 4), try moment(ply: 12)]

        #expect(KeyMomentNavigator.next(after: 4, in: moments)?.ply == 12)
        #expect(KeyMomentNavigator.previous(before: 30, in: moments)?.ply == 12)
    }

    @Test
    func noMomentsMeansNowhereToGo() {
        #expect(KeyMomentNavigator.next(after: 0, in: []) == nil)
        #expect(KeyMomentNavigator.previous(before: 99, in: []) == nil)
    }
}
