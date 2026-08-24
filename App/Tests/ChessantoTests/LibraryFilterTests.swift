import Foundation
import Persistence
import Testing
@testable import Chessanto

struct LibraryFilterTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func game(
        white: String,
        black: String,
        result: String? = "1-0",
        timeControl: String? = "600",
        playedAt: Date? = nil
    ) -> GameRecord {
        GameRecord(
            source: .chessCom,
            pgn: "1. e4 e5",
            white: white,
            black: black,
            result: result,
            timeControl: timeControl,
            playedAt: playedAt
        )
    }

    private func matches(
        _ filter: LibraryFilter,
        _ record: GameRecord,
        openingName: String? = nil,
        openingECO: String? = nil,
        userAccuracy: Double? = nil,
        identity: String? = nil
    ) -> Bool {
        filter.matches(
            record,
            openingName: openingName,
            openingECO: openingECO,
            userAccuracy: userAccuracy,
            identity: identity,
            calendar: calendar
        )
    }

    // MARK: - Search

    @Test
    func searchMatchesOpponentSubstringCaseInsensitively() {
        let filter = LibraryFilter(searchText: "magnus")
        #expect(matches(filter, game(white: "me", black: "MagnusCarlsen"), identity: "me"))
        #expect(!matches(filter, game(white: "me", black: "Hikaru"), identity: "me"))
    }

    @Test
    func searchMatchesOpeningNameAndECOCode() {
        let caroKann = LibraryFilter(searchText: "caro")
        #expect(matches(caroKann, game(white: "me", black: "opponent"), openingName: "Caro-Kann Defense", identity: "me"))
        #expect(!matches(caroKann, game(white: "me", black: "opponent"), openingName: "Sicilian Defense", identity: "me"))

        let ecoSearch = LibraryFilter(searchText: "b01")
        #expect(matches(ecoSearch, game(white: "me", black: "opponent"), openingECO: "B01", identity: "me"))
    }

    /// Searching your own username must not match every game - only the
    /// opponent side and the opening are searchable.
    @Test
    func searchExcludesTheUsersOwnName() {
        let filter = LibraryFilter(searchText: "willisliao")
        #expect(!matches(filter, game(white: "WillisLiao", black: "Hikaru"), identity: "WillisLiao"))
        #expect(matches(filter, game(white: "WillisLiao", black: "willisliao-fan"), identity: "WillisLiao"))
    }

    @Test
    func whitespaceOnlySearchImposesNoConstraint() {
        let filter = LibraryFilter(searchText: "   ")
        #expect(matches(filter, game(white: "a", black: "b")))
        #expect(!filter.isActive)
    }

    // MARK: - Opponent

    @Test
    func opponentFilterMatchesCaseInsensitively() {
        let filter = LibraryFilter(opponent: "Hikaru")
        #expect(matches(filter, game(white: "me", black: "HIKARU"), identity: "me"))
        #expect(!matches(filter, game(white: "me", black: "Magnus"), identity: "me"))
    }

    // MARK: - Outcome

    @Test
    func outcomeResolvesFromTheUsersPerspective() {
        #expect(LibraryFilter.outcome(of: game(white: "me", black: "x", result: "1-0"), identity: "me") == .win)
        #expect(LibraryFilter.outcome(of: game(white: "x", black: "me", result: "1-0"), identity: "me") == .loss)
        #expect(LibraryFilter.outcome(of: game(white: "me", black: "x", result: "0-1"), identity: "me") == .loss)
        #expect(LibraryFilter.outcome(of: game(white: "me", black: "x", result: "1/2-1/2"), identity: "me") == .draw)
        #expect(LibraryFilter.outcome(of: game(white: "me", black: "x", result: "*"), identity: "me") == nil)
    }

    @Test
    func outcomeNeedsAnIdentityAndParticipation() {
        #expect(LibraryFilter.outcome(of: game(white: "a", black: "b"), identity: nil) == nil)
        #expect(LibraryFilter.outcome(of: game(white: "a", black: "b"), identity: "me") == nil)

        let lossFilter = LibraryFilter(outcome: .loss)
        #expect(!matches(lossFilter, game(white: "a", black: "b", result: "0-1"), identity: nil))
        #expect(matches(lossFilter, game(white: "a", black: "me", result: "1-0"), identity: "me"))
    }

    // MARK: - Opening family

    @Test
    func openingFamilyComesFromTheECOLetter() {
        #expect(LibraryFilter.openingFamily(fromECO: "B01") == "B")
        #expect(LibraryFilter.openingFamily(fromECO: "e99") == "E")
        #expect(LibraryFilter.openingFamily(fromECO: nil) == nil)
        #expect(LibraryFilter.openingFamily(fromECO: "") == nil)
        #expect(LibraryFilter.openingFamily(fromECO: "X99") == nil)
    }

    @Test
    func openingFamilyFilterExcludesUnmatchedGames() {
        let filter = LibraryFilter(openingFamily: "B")
        #expect(matches(filter, game(white: "a", black: "b"), openingECO: "B01"))
        #expect(!matches(filter, game(white: "a", black: "b"), openingECO: "C42"))
        #expect(!matches(filter, game(white: "a", black: "b"), openingECO: nil))
    }

    // MARK: - Time control

    @Test
    func timeControlCategoriesMirrorTheRowFormatterBands() {
        #expect(TimeControlCategory(rawTimeControl: "60") == .bullet)
        #expect(TimeControlCategory(rawTimeControl: "120+1") == .bullet)
        #expect(TimeControlCategory(rawTimeControl: "180+2") == .blitz)
        #expect(TimeControlCategory(rawTimeControl: "300") == .blitz)
        #expect(TimeControlCategory(rawTimeControl: "600") == .rapid)
        #expect(TimeControlCategory(rawTimeControl: "900+10") == .rapid)
        #expect(TimeControlCategory(rawTimeControl: "1800") == .classical)
        #expect(TimeControlCategory(rawTimeControl: "7200") == .classical)
        #expect(TimeControlCategory(rawTimeControl: "1/259200") == .daily)
        #expect(TimeControlCategory(rawTimeControl: "-") == nil)
        #expect(TimeControlCategory(rawTimeControl: "") == nil)
        #expect(TimeControlCategory(rawTimeControl: nil) == nil)
    }

    @Test
    func timeControlFilterExcludesUncategorizableGames() {
        let filter = LibraryFilter(timeControl: .blitz)
        #expect(matches(filter, game(white: "a", black: "b", timeControl: "300")))
        #expect(!matches(filter, game(white: "a", black: "b", timeControl: "600")))
        #expect(!matches(filter, game(white: "a", black: "b", timeControl: nil)))
    }

    // MARK: - Accuracy

    @Test
    func accuracyBandsAreDisjointAndBoundaryCorrect() {
        #expect(AccuracyBand.ninetyPlus.contains(90))
        #expect(AccuracyBand.ninetyPlus.contains(100))
        #expect(!AccuracyBand.eightyToNinety.contains(90))
        #expect(AccuracyBand.eightyToNinety.contains(80))
        #expect(AccuracyBand.eightyToNinety.contains(89.9))
        #expect(!AccuracyBand.belowEighty.contains(80))
        #expect(AccuracyBand.belowEighty.contains(79.9))
        #expect(AccuracyBand.belowEighty.contains(0))
    }

    @Test
    func accuracyFilterExcludesGamesWithoutAKnownUserAccuracy() {
        let filter = LibraryFilter(accuracyBand: .ninetyPlus)
        #expect(matches(filter, game(white: "a", black: "b"), userAccuracy: 94.2))
        #expect(!matches(filter, game(white: "a", black: "b"), userAccuracy: 88))
        #expect(!matches(filter, game(white: "a", black: "b"), userAccuracy: nil))
    }

    // MARK: - Date range

    @Test
    func dateBoundsAreInclusiveOfTheirWholeDays() {
        let filter = LibraryFilter(playedFrom: date(2026, 3, 5), playedTo: date(2026, 3, 10))
        #expect(matches(filter, game(white: "a", black: "b", playedAt: date(2026, 3, 5, hour: 0))))
        #expect(matches(filter, game(white: "a", black: "b", playedAt: date(2026, 3, 10, hour: 23))))
        #expect(!matches(filter, game(white: "a", black: "b", playedAt: date(2026, 3, 4))))
        #expect(!matches(filter, game(white: "a", black: "b", playedAt: date(2026, 3, 11))))
    }

    @Test
    func openEndedDateBoundsWorkAlone() {
        #expect(matches(LibraryFilter(playedFrom: date(2026, 1, 1)), game(white: "a", black: "b", playedAt: date(2026, 6, 1))))
        #expect(!matches(LibraryFilter(playedFrom: date(2027, 1, 1)), game(white: "a", black: "b", playedAt: date(2026, 6, 1))))
        #expect(matches(LibraryFilter(playedTo: date(2026, 6, 1)), game(white: "a", black: "b", playedAt: date(2026, 6, 1))))
        #expect(!matches(LibraryFilter(playedTo: date(2026, 1, 1)), game(white: "a", black: "b", playedAt: date(2026, 6, 1))))
    }

    /// Games without a play date cannot satisfy any date constraint.
    @Test
    func undatedGamesAreExcludedByDateFilters() {
        #expect(!matches(LibraryFilter(playedFrom: date(2026, 1, 1)), game(white: "a", black: "b", playedAt: nil)))
    }

    // MARK: - Composition

    @Test
    func constraintsComposeWithANDSemantics() {
        var filter = LibraryFilter()
        filter.opponent = "hikaru"
        filter.outcome = .loss
        // Me vs Hikaru, Hikaru won: opponent matches AND I lost.
        #expect(matches(filter, game(white: "me", black: "Hikaru", result: "0-1"), identity: "me"))
        // Me vs Hikaru, I won: the outcome constraint fails.
        #expect(!matches(filter, game(white: "me", black: "Hikaru", result: "1-0"), identity: "me"))
        // I lost, but against Magnus: the opponent constraint fails.
        #expect(!matches(filter, game(white: "me", black: "Magnus", result: "0-1"), identity: "me"))

        filter.timeControl = .bullet
        #expect(matches(filter, game(white: "me", black: "Hikaru", result: "0-1", timeControl: "60"), identity: "me"))
        #expect(!matches(filter, game(white: "me", black: "Hikaru", result: "0-1", timeControl: "600"), identity: "me"))
    }

    @Test
    func unsetFilterPassesEverything() {
        let filter = LibraryFilter()
        #expect(matches(filter, game(white: "a", black: "b", result: nil, timeControl: nil, playedAt: nil)))
        #expect(filter.activeCount == 0)
        #expect(!filter.isActive)
    }

    @Test
    func activeCountCountsConstraintFieldsNotSearch() {
        var filter = LibraryFilter()
        filter.searchText = "magnus"
        #expect(filter.activeCount == 0)
        #expect(filter.isActive)
        filter.opponent = "Hikaru"
        filter.playedFrom = date(2026, 1, 1)
        filter.playedTo = date(2026, 1, 31)
        #expect(filter.activeCount == 3)
        #expect(filter.isActive)
    }

    // MARK: - Opponent candidates

    @Test
    func opponentsExcludeTheIdentityAndFoldCase() {
        let games = [
            game(white: "me", black: "Hikaru"),
            game(white: "HIKARU", black: "me"),
            game(white: "me", black: "Magnus"),
            game(white: "me", black: "Magnus"),
            game(white: "me", black: "Magnus"),
            game(white: "Me", black: "Me")
        ]
        let opponents = LibraryFilter.opponents(in: games, excluding: "ME")
        #expect(opponents == ["Magnus", "Hikaru"])
        #expect(LibraryFilter.opponents(in: games, excluding: nil).count == 3)
    }

    // MARK: - Filter cost at archive scale

    /// Not an assertion about a threshold - prints the measured per-keystroke
    /// reduce cost over a 2500-game register so the no-debounce decision in
    /// the devlog quotes a real number.
    @Test
    func measuresFilterCostOverAnArchiveSizedRegister() {
        var records: [GameRecord] = []
        var openings: [Int64: String] = [:]
        var ecos: [Int64: String] = [:]
        var accuracies: [Int64: Double] = [:]
        for index in 0..<2500 {
            var record = game(
                white: "WillisLiao",
                black: index % 10 == 0 ? "Annie" : "Bob\(index)",
                result: ["1-0", "0-1", "1/2-1/2"][index % 3],
                timeControl: "180+2",
                playedAt: date(2026, (index % 12) + 1, (index % 28) + 1)
            )
            record.id = Int64(index + 1)
            guard let id = record.id else { continue }
            openings[id] = "Caro-Kann Defense"
            ecos[id] = "B01"
            accuracies[id] = index % 4 == 0 ? 95.0 : 60.0
            records.append(record)
        }

        // Matches exactly the indices with i % 60 == 20 (Annie + a draw +
        // 95% accuracy together): 20, 80, ..., 2480.
        var filter = LibraryFilter()
        filter.opponent = "Annie"
        filter.outcome = .draw
        filter.accuracyBand = .ninetyPlus

        func countMatches(_ candidate: LibraryFilter) -> Int {
            var count = 0
            for record in records {
                guard let id = record.id else { continue }
                if candidate.matches(
                    record,
                    openingName: openings[id],
                    openingECO: ecos[id],
                    userAccuracy: accuracies[id],
                    identity: "WillisLiao",
                    calendar: calendar
                ) {
                    count += 1
                }
            }
            return count
        }

        _ = countMatches(filter) // warm-up
        let start = Date()
        var matched = 0
        for _ in 0..<50 {
            matched = countMatches(filter)
        }
        let perPassMs = Date().timeIntervalSince(start) * 1000 / 50
        print("[perf] LibraryFilter.reduce over \(records.count) games: \(String(format: "%.3f", perPassMs))ms per pass (\(matched) matched)")
        #expect(matched == 42)
    }
}
