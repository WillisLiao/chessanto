import Foundation
import Persistence

/// The user-perspective outcome of a game, matching the W/L/D badge the
/// sidebar rows already render.
enum GameOutcome: String, CaseIterable, Sendable {
    case win
    case loss
    case draw

    var label: String {
        switch self {
        case .win: return "Wins"
        case .loss: return "Losses"
        case .draw: return "Draws"
        }
    }
}

/// Coarse time-control buckets a filter menu can offer regardless of how
/// many exact base+increment combinations an archive contains. The bands
/// mirror `GameRowMetadata.formattedTimeControl`'s seconds cutoffs.
enum TimeControlCategory: String, CaseIterable, Sendable {
    case bullet
    case blitz
    case rapid
    case classical
    case daily

    /// `nil` when there is nothing to bucket (no tag, or unparseable), so
    /// such games simply cannot be selected by this filter.
    init?(rawTimeControl: String?) {
        guard let raw = rawTimeControl?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        // chess.com writes correspondence clocks as "1/259200" (seconds per move).
        if raw.contains("/") {
            self = .daily
            return
        }
        guard let baseSeconds = Int(raw.split(separator: "+", maxSplits: 1)[0]) else {
            return nil
        }
        switch baseSeconds {
        case ..<180: self = .bullet
        case 180..<600: self = .blitz
        case 600..<1800: self = .rapid
        default: self = .classical
        }
    }

    var label: String {
        switch self {
        case .bullet: return "Bullet"
        case .blitz: return "Blitz"
        case .rapid: return "Rapid"
        case .classical: return "Classical"
        case .daily: return "Daily"
        }
    }
}

/// Preset accuracy ranges for the accuracy filter.
enum AccuracyBand: String, CaseIterable, Sendable {
    case ninetyPlus
    case eightyToNinety
    case belowEighty

    var label: String {
        switch self {
        case .ninetyPlus: return "90%+"
        case .eightyToNinety: return "80 to 90%"
        case .belowEighty: return "Below 80%"
        }
    }

    func contains(_ accuracy: Double) -> Bool {
        switch self {
        case .ninetyPlus: return accuracy >= 90
        case .eightyToNinety: return accuracy >= 80 && accuracy < 90
        case .belowEighty: return accuracy < 80
        }
    }
}

/// One small value describing every active library search/filter constraint.
/// The sidebar list reduces the register against it; any unset field imposes
/// no constraint. Pure and database-free so it can be tested without a store.
///
/// Per-game derived values (opening name/ECO, the user's accuracy) arrive as
/// parameters rather than being looked up here, so the same `matches` drives
/// both tests and the real list without reaching into `GameLibrary`.
struct LibraryFilter: Equatable, Sendable {
    var searchText = ""
    var opponent: String?
    var outcome: GameOutcome?
    /// The ECO family letter, "A" through "E".
    var openingFamily: String?
    var timeControl: TimeControlCategory?
    var accuracyBand: AccuracyBand?
    /// Inclusive day bounds on `playedAt`.
    var playedFrom: Date?
    var playedTo: Date?

    /// How many constraint fields are set - the count shown on the Filter
    /// button. Search text has its own field and is not counted.
    var activeCount: Int {
        var count = 0
        if opponent != nil { count += 1 }
        if outcome != nil { count += 1 }
        if openingFamily != nil { count += 1 }
        if timeControl != nil { count += 1 }
        if accuracyBand != nil { count += 1 }
        if playedFrom != nil { count += 1 }
        if playedTo != nil { count += 1 }
        return count
    }

    var isActive: Bool {
        activeCount > 0 || !normalizedSearchText.isEmpty
    }

    mutating func reset() {
        self = LibraryFilter()
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The ECO family letter of an ECO code ("B01" -> "B"), or `nil` for
    /// anything that is not one of the five families.
    static func openingFamily(fromECO eco: String?) -> String? {
        guard let first = eco?.trimmingCharacters(in: .whitespaces).first,
            let family = String(first).uppercased().first,
            "ABCDE".contains(family)
        else { return nil }
        return String(family)
    }

    /// The user's own result in a game, or `nil` when it cannot be known:
    /// no identity is configured, the user did not play, or the result tag
    /// is missing/unrecognized. Mirrors the sidebar row badge exactly.
    static func outcome(of game: GameRecord, identity: String?) -> GameOutcome? {
        guard let identity, !identity.isEmpty, let result = game.result else { return nil }
        let isWhite = game.white.caseInsensitiveCompare(identity) == .orderedSame
        let isBlack = game.black.caseInsensitiveCompare(identity) == .orderedSame
        guard isWhite || isBlack else { return nil }
        switch result {
        case "1-0": return isWhite ? .win : .loss
        case "0-1": return isBlack ? .win : .loss
        case "1/2-1/2": return .draw
        default: return nil
        }
    }

    /// Distinct opponent names in the register, most-played first - the
    /// candidates menu for the opponent filter. Reuses `BriefIdentity`'s
    /// candidate ranking with the user's own name removed.
    static func opponents(in games: [GameRecord], excluding identity: String?) -> [String] {
        BriefIdentity.candidates(in: games).filter { name in
            guard let identity, !identity.isEmpty else { return true }
            return name.caseInsensitiveCompare(identity) != .orderedSame
        }
    }

    func matches(
        _ game: GameRecord,
        openingName: String?,
        openingECO: String?,
        userAccuracy: Double?,
        identity: String?,
        calendar: Calendar = .current
    ) -> Bool {
        if !searchMatches(game: game, openingName: openingName, openingECO: openingECO, identity: identity) {
            return false
        }
        if let opponent,
            ![game.white, game.black].contains(where: {
                $0.caseInsensitiveCompare(opponent) == .orderedSame
            })
        {
            return false
        }
        if let wanted = outcome {
            guard Self.outcome(of: game, identity: identity) == wanted else { return false }
        }
        if let family = openingFamily {
            guard Self.openingFamily(fromECO: openingECO) == family else { return false }
        }
        if let timeControl {
            guard TimeControlCategory(rawTimeControl: game.timeControl) == timeControl else { return false }
        }
        if let band = accuracyBand {
            guard let userAccuracy, band.contains(userAccuracy) else { return false }
        }
        if playedFrom != nil || playedTo != nil {
            guard let played = game.playedAt else { return false }
            let day = calendar.startOfDay(for: played)
            if let from = playedFrom, day < calendar.startOfDay(for: from) { return false }
            if let to = playedTo, day > calendar.startOfDay(for: to) { return false }
        }
        return true
    }

    /// Free text matches the opponent names and the opening name/ECO,
    /// case-insensitively. The user's own name is excluded from the haystack
    /// so searching your own username does not match every game.
    private func searchMatches(
        game: GameRecord,
        openingName: String?,
        openingECO: String?,
        identity: String?
    ) -> Bool {
        let needle = normalizedSearchText
        guard !needle.isEmpty else { return true }

        var names = [game.white, game.black]
        if let identity, !identity.isEmpty {
            names.removeAll { $0.caseInsensitiveCompare(identity) == .orderedSame }
            // A game against yourself has no opponent name left; fall back
            // to the raw names so it stays findable at all.
            if names.isEmpty { names = [game.white, game.black] }
        }
        let haystack = names + [openingName, openingECO].compactMap { $0 }
        return haystack.contains { $0.lowercased().contains(needle) }
    }
}

/// The choices the filter panel offers, counted against the register (or the
/// favorites subset) the panel was opened from, so every option is honest
/// about what selecting it would show.
struct LibraryFilterOptions: Sendable {
    let opponents: [String]
    let outcomeAvailable: Bool
    let families: [(family: String, count: Int)]
    let timeControls: [(category: TimeControlCategory, count: Int)]
    let accuracyAvailable: Bool
    let totalCount: Int

    static func build(
        games: [GameRecord],
        openingECOByGameID: [Int64: String],
        accuracyByGameID: [Int64: Double],
        identity: String?
    ) -> LibraryFilterOptions {
        var familyCounts: [String: Int] = [:]
        var timeControlCounts: [TimeControlCategory: Int] = [:]
        var hasAccuracy = false
        for game in games {
            if let id = game.id, let eco = openingECOByGameID[id],
                let family = LibraryFilter.openingFamily(fromECO: eco)
            {
                familyCounts[family, default: 0] += 1
            }
            if let category = TimeControlCategory(rawTimeControl: game.timeControl) {
                timeControlCounts[category, default: 0] += 1
            }
            if let id = game.id, accuracyByGameID[id] != nil {
                hasAccuracy = true
            }
        }

        let fixedFamilies = ["A", "B", "C", "D", "E"]
        return LibraryFilterOptions(
            opponents: LibraryFilter.opponents(in: games, excluding: identity),
            outcomeAvailable: identity?.isEmpty == false && games.contains {
                LibraryFilter.outcome(of: $0, identity: identity) != nil
            },
            families: fixedFamilies.map { family in
                (family: family, count: familyCounts[family] ?? 0)
            },
            timeControls: TimeControlCategory.allCases.map { category in
                (category: category, count: timeControlCounts[category] ?? 0)
            },
            accuracyAvailable: hasAccuracy,
            totalCount: games.count
        )
    }
}
