import Foundation
import Persistence

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [GameRecord] = []
    @Published var errorMessage: String?

    private let store: GameStore

    init() {
        do {
            self.store = try GameStore.defaultStore()
        } catch {
            fatalError("Couldn't open local database: \(error.localizedDescription)")
        }
        reload()
    }

    func reload() {
        do {
            games = try store.allGames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importPGN(_ pgn: String, source: GameSource = .pgnImport, sourceURL: String? = nil) -> GameRecord? {
        guard let tags = PGNTagScanner.tags(from: pgn) else {
            errorMessage = "That file doesn't look like a valid PGN game."
            return nil
        }

        let record = GameRecord(
            source: source,
            sourceURL: sourceURL,
            pgn: pgn,
            white: tags["White"] ?? "White",
            black: tags["Black"] ?? "Black",
            whiteRating: tags["WhiteElo"].flatMap(Int.init),
            blackRating: tags["BlackElo"].flatMap(Int.init),
            result: tags["Result"],
            timeControl: tags["TimeControl"],
            playedAt: PGNTagScanner.date(from: tags)
        )

        do {
            let saved = try store.save(record)
            reload()
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ game: GameRecord) {
        guard let id = game.id else { return }
        do {
            try store.deleteGame(id: id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func alreadyImported(sourceURLs: Set<String>) -> Set<String> {
        (try? store.importedSourceURLs()) ?? []
    }
}
