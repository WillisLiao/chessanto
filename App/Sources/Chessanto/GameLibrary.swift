import Foundation
import Persistence
import ChessCore
import AnalysisKit

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [GameRecord] = []
    @Published private(set) var recentlyDeletedGames: [GameRecord] = []
    @Published var errorMessage: String?
    @Published var chessComUsername: String
    @Published private(set) var isChessComAccountConfirmed: Bool
    @Published var analysisQuality: AnalysisQuality
    @Published var boardTheme: BoardTheme
    @Published var moveNotationStyle: MoveNotationStyle
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var analyzedGameIDs: Set<Int64> = []
    @Published private(set) var openingByGameID: [Int64: String] = [:]

    let store: GameStore
    private var enrichmentTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init() {
        do {
            self.store = try GameStore.defaultStore()
        } catch {
            fatalError("Couldn't open local database: \(error.localizedDescription)")
        }
        let profile = (try? store.userProfile())
        self.chessComUsername = profile?.chessComUsername ?? ""
        self.isChessComAccountConfirmed = profile?.isChessComAccountConfirmed ?? false
        self.analysisQuality = profile.flatMap { AnalysisQuality(rawValue: $0.analysisQuality) } ?? .standard
        self.boardTheme = profile.flatMap { BoardTheme(rawValue: $0.boardTheme) } ?? .classic
        self.moveNotationStyle = profile.flatMap { MoveNotationStyle(rawValue: $0.moveNotationStyle) } ?? .standard
        self.hasCompletedOnboarding = profile?.hasCompletedOnboarding ?? false
        reload()
    }

    func saveChessComUsername(_ username: String, confirmed: Bool = false) {
        chessComUsername = username
        isChessComAccountConfirmed = confirmed && !username.isEmpty
        do {
            var profile = try store.userProfile()
            profile.chessComUsername = username
            profile.isChessComAccountConfirmed = isChessComAccountConfirmed
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

    func saveMoveNotationStyle(_ style: MoveNotationStyle) {
        moveNotationStyle = style
        do {
            var profile = try store.userProfile()
            profile.moveNotationStyle = style.rawValue
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
        reloadGeneration += 1
        let generation = reloadGeneration
        enrichmentTask?.cancel()

        do {
            games = try store.allGames()
            recentlyDeletedGames = try store.recentlyDeletedGames()
        } catch {
            errorMessage = error.localizedDescription
        }
        let store = self.store
        let currentGames = games
        enrichmentTask = Task { [weak self] in
            let ids = (try? await store.analyzedGameIDs()) ?? []
            guard !Task.isCancelled else { return }

            let parsingTask = Task.detached(priority: .utility) {
                Self.openings(for: currentGames, analyzedGameIDs: ids)
            }
            let openings = await withTaskCancellationHandler {
                await parsingTask.value
            } onCancel: {
                parsingTask.cancel()
            }

            guard let self, !Task.isCancelled, generation == self.reloadGeneration else { return }
            self.analyzedGameIDs = ids
            self.openingByGameID = openings
        }
    }

    /// Opening names for the sidebar's "analyzed" rows - pure move replay
    /// against the opening book, no analysis rows needed (M8's `OpeningBook`
    /// only needs FENs), so this stays cheap even for a full library.
    nonisolated private static func openings(for games: [GameRecord], analyzedGameIDs: Set<Int64>) -> [Int64: String] {
        var result: [Int64: String] = [:]
        for game in games {
            guard !Task.isCancelled else { break }
            guard let id = game.id, analyzedGameIDs.contains(id) else { continue }
            guard let chessGame = try? ChessGame(pgn: game.pgn) else { continue }
            let moveIndices = [chessGame.startIndex] + chessGame.mainlineIndices
            let fens = moveIndices.map { chessGame.fen(at: $0) ?? "" }
            guard let match = OpeningBook.shared.lookup(fens: fens) else { continue }
            result[id] = match.name
        }
        return result
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
        apply(.moveToRecentlyDeleted([id]))
    }

    @discardableResult
    func apply(_ command: LibraryCommand) -> LibraryMutationResult? {
        do {
            let result = try store.perform(command)
            reload()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func alreadyImported(sourceURLs: Set<String>) -> Set<String> {
        let imported = (try? store.importedSourceURLs()) ?? []
        return imported.intersection(sourceURLs)
    }
}
