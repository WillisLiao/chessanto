import Foundation
import Persistence

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [GameRecord] = []
    @Published var errorMessage: String?
    @Published var chessComUsername: String
    @Published var analysisQuality: AnalysisQuality
    @Published var boardTheme: BoardTheme
    @Published private(set) var hasCompletedOnboarding: Bool

    let store: GameStore

    init() {
        do {
            self.store = try GameStore.defaultStore()
        } catch {
            fatalError("Couldn't open local database: \(error.localizedDescription)")
        }
        let profile = (try? store.userProfile())
        self.chessComUsername = profile?.chessComUsername ?? ""
        self.analysisQuality = profile.flatMap { AnalysisQuality(rawValue: $0.analysisQuality) } ?? .standard
        self.boardTheme = profile.flatMap { BoardTheme(rawValue: $0.boardTheme) } ?? .classic
        self.hasCompletedOnboarding = profile?.hasCompletedOnboarding ?? false
        reload()
    }

    func saveChessComUsername(_ username: String) {
        chessComUsername = username
        do {
            var profile = try store.userProfile()
            profile.chessComUsername = username
            try store.saveUserProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAnalysisQuality(_ quality: AnalysisQuality) {
        analysisQuality = quality
        do {
            var profile = try store.userProfile()
            profile.analysisQuality = quality.rawValue
            try store.saveUserProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveBoardTheme(_ theme: BoardTheme) {
        boardTheme = theme
        do {
            var profile = try store.userProfile()
            profile.boardTheme = theme.rawValue
            try store.saveUserProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        do {
            var profile = try store.userProfile()
            profile.hasCompletedOnboarding = true
            try store.saveUserProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
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
        let imported = (try? store.importedSourceURLs()) ?? []
        return imported.intersection(sourceURLs)
    }
}
