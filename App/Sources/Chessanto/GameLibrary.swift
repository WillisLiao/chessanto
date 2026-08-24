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
    @Published var boardSoundsEnabled: Bool
    @Published private(set) var playerName: String?
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var analyzedGameIDs: Set<Int64> = []
    @Published private(set) var openingByGameID: [Int64: String] = [:]
    /// ECO code ("B01") per game, alongside `openingByGameID`'s name - the
    /// opening filter groups by family letter and search matches the code.
    @Published private(set) var openingECOByGameID: [Int64: String] = [:]
    /// The user's own accuracy in each analyzed game they played, computed
    /// once per reload off the main thread from the stored analysis rows -
    /// never re-derived on every filter change.
    @Published private(set) var accuracyByGameID: [Int64: Double] = [:]

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
        self.boardSoundsEnabled = profile?.boardSoundsEnabled ?? true
        self.playerName = profile?.playerName
        self.hasCompletedOnboarding = profile?.hasCompletedOnboarding ?? false
        // The board plays sound through a shared player rather than reading
        // this object, so the stored preference has to be pushed to it once
        // at launch and again on every change.
        BoardSounds.shared.isEnabled = self.boardSoundsEnabled
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

    /// Who the user is among the players in their own games.
    ///
    /// A confirmed chess.com account answers this implicitly, so it wins;
    /// otherwise the user picks a name from their imported PGNs. Without
    /// this, every progress surface was unreachable for the PGN-only user
    /// the README explicitly supports.
    var briefIdentity: String? {
        BriefIdentity.resolve(
            chessComUsername: chessComUsername,
            isChessComAccountConfirmed: isChessComAccountConfirmed,
            playerName: playerName
        )
    }

    /// Every name appearing in the register, most-played first - the
    /// candidates for "which of these is you".
    var playerNameCandidates: [String] {
        BriefIdentity.candidates(in: games)
    }

    func savePlayerName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (trimmed?.isEmpty ?? true) ? nil : trimmed
        playerName = stored
        do {
            var profile = try store.userProfile()
            profile.playerName = stored
            try store.saveUserProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveBoardSoundsEnabled(_ isEnabled: Bool) {
        boardSoundsEnabled = isEnabled
        BoardSounds.shared.isEnabled = isEnabled
        do {
            var profile = try store.userProfile()
            profile.boardSoundsEnabled = isEnabled
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
        let username = chessComUsername
        let userProfile = (try? store.userProfile())
        enrichmentTask = Task { [weak self] in
            let ids = (try? await store.analyzedGameIDs()) ?? []
            guard !Task.isCancelled else { return }

            let parsingTask = Task.detached(priority: .utility) {
                let openings = Self.openingEnrichment(for: currentGames)
                let accuracies = await Self.userAccuracies(
                    games: currentGames,
                    analyzedGameIDs: ids,
                    store: store,
                    username: username,
                    userProfile: userProfile
                )
                return (openings.names, openings.ecos, accuracies)
            }
            let (names, ecos, accuracies) = await withTaskCancellationHandler {
                await parsingTask.value
            } onCancel: {
                parsingTask.cancel()
            }

            guard let self, !Task.isCancelled, generation == self.reloadGeneration else { return }
            self.analyzedGameIDs = ids
            self.openingByGameID = names
            self.openingECOByGameID = ecos
            self.accuracyByGameID = accuracies
        }
    }

    /// Opening names and ECO codes for the whole register - pure move replay
    /// against the opening book, no analysis rows needed (M8's `OpeningBook`
    /// only needs FENs), so this stays cheap even for a full library. The
    /// sidebar rows, free-text search, and the opening filter all read this.
    nonisolated private static func openingEnrichment(for games: [GameRecord]) -> (
        names: [Int64: String], ecos: [Int64: String]
    ) {
        var names: [Int64: String] = [:]
        var ecos: [Int64: String] = [:]
        for game in games {
            guard !Task.isCancelled else { break }
            guard let id = game.id,
                let chessGame = try? ChessGame(pgn: game.pgn)
            else { continue }
            let moveIndices = [chessGame.startIndex] + chessGame.mainlineIndices
            let fens = moveIndices.map { chessGame.fen(at: $0) ?? "" }
            guard let match = OpeningBook.shared.lookup(fens: fens) else { continue }
            names[id] = match.name
            ecos[id] = match.eco
        }
        return (names, ecos)
    }

    /// The user-side accuracy for every analyzed game they played, following
    /// `DashboardView.computeDashboard`'s precedent of building the shared
    /// report per analyzed game off the main actor. Cancelled reloads stop
    /// early; a partially filled dictionary is still valid (a missing entry
    /// just reads as "not yet known").
    nonisolated private static func userAccuracies(
        games: [GameRecord],
        analyzedGameIDs: Set<Int64>,
        store: GameStore,
        username: String,
        userProfile: UserProfileRecord?
    ) async -> [Int64: Double] {
        var result: [Int64: Double] = [:]
        for game in games {
            guard !Task.isCancelled else { break }
            guard let id = game.id, analyzedGameIDs.contains(id) else { continue }
            let isWhite = game.white.caseInsensitiveCompare(username) == .orderedSame
            let isBlack = game.black.caseInsensitiveCompare(username) == .orderedSame
            guard isWhite || isBlack else { continue }
            guard let analysisRows = try? await store.analysis(gameId: id), !analysisRows.isEmpty else { continue }
            guard let report = ReportBuilding.buildReport(
                record: game,
                analysisRows: analysisRows,
                chessComUsername: username,
                userProfile: userProfile
            ) else { continue }
            result[id] = isWhite ? report.whiteAccuracy : report.blackAccuracy
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
