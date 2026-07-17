import ChessCore
import Foundation

/// A single named opening line from the bundled dataset
/// ([lichess-org/chess-openings](https://github.com/lichess-org/chess-openings),
/// CC0-1.0).
public struct OpeningEntry: Decodable, Sendable {
    public let eco: String
    public let name: String
    public let pgn: String

    public init(eco: String, name: String, pgn: String) {
        self.eco = eco
        self.name = name
        self.pgn = pgn
    }
}

/// One resolved (final-position EPD -> name) row, as committed to
/// `eco-index.json`. Precomputed at build time by `eco-indexer` instead of
/// being replayed at app-launch time - replaying the full ~3.8k-line raw
/// dataset through `ChessGame` on every run measured at several seconds,
/// well past the "well under a second" budget in the M5 plan.
struct OpeningIndexEntry: Codable {
    let epd: String
    let eco: String
    let name: String
}

/// A game's classification against the opening book: the deepest matching
/// entry and the ply at which it matched.
public struct OpeningMatch: Equatable, Sendable {
    public let eco: String
    public let name: String
    /// The mainline ply index (1-based, i.e. `mainlineIndices[deepestBookPly - 1]`)
    /// of the last book-matching position.
    public let deepestBookPly: Int
}

/// Indexes named opening lines by final-position EPD, so a game can be
/// matched to the deepest known theoretical line it followed. The index is
/// keyed using `ChessGame`-generated FENs on both sides (never the
/// lichess-precomputed EPD column - see the M5 plan's verified fact about
/// chesskit omitting the en-passant square), so both sides of every lookup
/// share the same FEN convention.
public struct OpeningBook: Sendable {
    /// A process-lifetime shared instance, built once from the precomputed
    /// index (a plain dictionary decode, well under a second - see
    /// `loadFromBundle()`). The app builds this off the main thread at
    /// first report request.
    public static let shared = OpeningBook.loadFromBundle()

    /// EPD -> (eco, name, line length in plies), keeping the entry with the
    /// longest line on a transposition, then the lexicographically smaller
    /// name for a deterministic tie-break.
    private let byEPD: [String: (eco: String, name: String, plyCount: Int)]

    private init(byEPD: [String: (eco: String, name: String, plyCount: Int)]) {
        self.byEPD = byEPD
    }

    /// Loads and decodes the raw `eco.json` dataset from the bundle
    /// (exposed for tests/tools that need the pre-replay entries directly;
    /// `loadFromBundle()` is the fast path apps should use).
    public static func loadRawEntriesFromBundle() -> [OpeningEntry] {
        guard
            let url = Bundle.module.url(forResource: "eco", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([OpeningEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    /// Loads the precomputed `eco-index.json` from the bundle (fast: no
    /// replay, just dictionary construction). Falls back to replaying the
    /// raw `eco.json` dataset if the precomputed index isn't present.
    public static func loadFromBundle() -> OpeningBook {
        if let url = Bundle.module.url(forResource: "eco-index", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let indexEntries = try? JSONDecoder().decode([OpeningIndexEntry].self, from: data)
        {
            return build(fromIndex: indexEntries)
        }
        return build(from: loadRawEntriesFromBundle())
    }

    static func build(fromIndex indexEntries: [OpeningIndexEntry]) -> OpeningBook {
        var byEPD: [String: (eco: String, name: String, plyCount: Int)] = [:]
        for entry in indexEntries {
            // plyCount isn't needed post-resolution (the indexer already
            // broke transposition ties); store 0 as a placeholder.
            byEPD[entry.epd] = (entry.eco, entry.name, 0)
        }
        return OpeningBook(byEPD: byEPD)
    }

    /// Replays every entry's PGN through `ChessGame` and resolves
    /// transpositions, producing the raw (unsorted) index. Used both by
    /// `eco-indexer` (to precompute `eco-index.json`) and directly by tests
    /// on small hand-written datasets.
    public static func build(from entries: [OpeningEntry]) -> OpeningBook {
        var byEPD: [String: (eco: String, name: String, plyCount: Int)] = [:]
        for entry in entries {
            let sans = tokenize(pgn: entry.pgn)
            guard !sans.isEmpty else { continue }
            var game = ChessGame()
            var index = game.startIndex
            var played = 0
            for san in sans {
                guard let next = game.playMove(san: san, at: index) else { break }
                index = next
                played += 1
            }
            guard played == sans.count, let fen = game.fen(at: index) else { continue }
            let epd = ChessGame.epd(fromFEN: fen)
            if let existing = byEPD[epd] {
                let preferNew = played > existing.plyCount
                    || (played == existing.plyCount && entry.name < existing.name)
                if !preferNew { continue }
            }
            byEPD[epd] = (entry.eco, entry.name, played)
        }
        return OpeningBook(byEPD: byEPD)
    }

    /// Serializes a raw dataset (as decoded from `eco.json`) into the
    /// precomputed `eco-index.json` format: replays every line, resolves
    /// transpositions, and emits one row per surviving EPD, sorted by EPD
    /// for a deterministic diff. Used by the `eco-indexer` executable.
    public static func precomputedIndexData(from entries: [OpeningEntry]) throws -> Data {
        let book = build(from: entries)
        let rows = book.byEPD
            .map { OpeningIndexEntry(epd: $0.key, eco: $0.value.eco, name: $0.value.name) }
            .sorted { $0.epd < $1.epd }
        let encoder = JSONEncoder()
        return try encoder.encode(rows)
    }

    /// Total entries actually indexed (post transposition-resolution) -
    /// exposed so the indexer/tests can assert nothing unexpected was
    /// dropped, distinct from the raw dataset count (which collapses
    /// transpositions by design).
    public var indexedEntryCount: Int {
        byEPD.count
    }

    /// Entries whose PGN failed to fully replay through `ChessGame` (a
    /// converter/tokenizer bug, unlike a transposition collapse which is
    /// expected). Should be empty for the real dataset.
    public static func unreplayableEntries(in entries: [OpeningEntry]) -> [OpeningEntry] {
        entries.filter { entry in
            let sans = tokenize(pgn: entry.pgn)
            guard !sans.isEmpty else { return true }
            var game = ChessGame()
            var index = game.startIndex
            for san in sans {
                guard let next = game.playMove(san: san, at: index) else { return true }
                index = next
            }
            return false
        }
    }

    /// Strips PGN move-number tokens (`"12."`) from a movetext string,
    /// leaving only SAN tokens in play order.
    static func tokenize(pgn: String) -> [String] {
        pgn.split(separator: " ").compactMap { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.allSatisfy({ $0.isNumber || $0 == "." }) { return nil }
            return trimmed
        }
    }

    /// Matches a game's FENs (index 0 = starting position) against the book,
    /// scanning plies 1...min(N, 40) and returning the entry at the deepest
    /// matching ply, or `nil` if no position in the game is in the book
    /// (including from-FEN games whose starting position is already
    /// non-standard).
    public func lookup(fens: [String]) -> OpeningMatch? {
        var best: OpeningMatch?
        let upperBound = min(fens.count - 1, 40)
        guard upperBound >= 1 else { return nil }
        for ply in 1...upperBound {
            let epd = ChessGame.epd(fromFEN: fens[ply])
            guard let entry = byEPD[epd] else { continue }
            best = OpeningMatch(eco: entry.eco, name: entry.name, deepestBookPly: ply)
        }
        return best
    }
}
