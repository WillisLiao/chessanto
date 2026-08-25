import SwiftUI
import UniformTypeIdentifiers
import Persistence

struct ContentView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var companion: MacCompanionManager
    @EnvironmentObject private var engineService: EngineService
    @Environment(\.scenePhase) private var scenePhase
    private enum LibrarySource: Equatable {
        case allGames
        case favorites
        case playerBrief
        case recentlyDeleted
    }

    private enum DetailDestination: Equatable {
        case empty
        case game(Int64)
        case playerBrief
        case recentlyDeleted
        case playVsEngine
    }

    @State private var librarySource: LibrarySource = .allGames
    @State private var detailDestination: DetailDestination = .empty
    @State private var isOrganizing = false
    @State private var organizedSelection: Set<Int64> = []
    @State private var pendingMoveIDs: Set<Int64> = []
    @State private var lastMovedIDs: Set<Int64> = []
    @State private var isShowingImporter = false
    @State private var isShowingChessComFetch = false
    @State private var isTargeted = false
    /// Set by the dashboard's "Review next lesson"/"Practice any position"
    /// (DD1) - `ContentView` owns game selection already, so it's the
    /// natural owner of "select this game, then enter practice mode".
    @State private var pendingPracticeGameID: Int64?
    @State private var pendingPracticeLoadCards: (() async throws -> [TrainingCardRecord])?
    /// Search text and every library filter dimension in one value; the
    /// sidebar list reduces the register against it.
    @State private var filter = LibraryFilter()
    @State private var isShowingFilterPanel = false
    @StateObject private var batchAnalysis = BatchAnalysisCoordinator()

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .onDrop(of: [.text, .pgn], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pgn, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .sheet(isPresented: $isShowingChessComFetch) {
            ChessComFetchView { imported in
                startBatchAnalysis(of: imported)
            }
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView { didConfirmAccount in
                // Straight from "this is my account" to "here are your
                // games", instead of an empty register and a menu to hunt
                // for. Imports flow on into analysis from there, since
                // "Analyze after import" is on by default.
                if didConfirmAccount, library.games.isEmpty {
                    isShowingChessComFetch = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importPGNRequested)) { _ in
            isShowingImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .playVsEngineRequested)) { _ in
            detailDestination = .playVsEngine
        }
        .alert("Import error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .alert(moveConfirmationTitle, isPresented: moveConfirmationBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Recently Deleted", role: .destructive) {
                movePendingGames()
            }
        } message: {
            Text("Their analysis, saved variations, Coach conversations, and practice history will be hidden with them. You can restore them later.")
        }
        .onChange(of: library.games.map(\.id)) { _, currentIDs in
            let existingIDs = Set(currentIDs.compactMap { $0 })
            organizedSelection.formIntersection(existingIDs)
            if case .game(let gameID) = detailDestination,
                !existingIDs.contains(gameID)
            {
                detailDestination = .empty
            }
            Task { try? await companion.publishCatalog() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                try? await companion.synchronize(reason: .foreground)
                try? await companion.publishCatalog()
            }
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            libraryControls
            if isOrganizing {
                organizingList
            } else {
                browsingList
            }
            BatchAnalysisBar(coordinator: batchAnalysis)
            sidebarBottomBar
        }
        .navigationTitle("Games")
        .searchable(
            text: $filter.searchText,
            placement: .sidebar,
            prompt: "Search opponent or opening"
        )
        .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 340)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch detailDestination {
        case .game(let gameID):
            if let game = library.games.first(where: { $0.id == gameID }) {
                GameReplayView(
                    game: game,
                    store: library.store,
                    pendingPracticeLoadCards: pendingPracticeGameID == game.id ? pendingPracticeLoadCards : nil,
                    onPendingPracticeConsumed: {
                        pendingPracticeGameID = nil
                        pendingPracticeLoadCards = nil
                    }
                )
                .id(game.id)
            } else {
                emptySelectionView
            }
        case .playerBrief:
            PlayerBriefView(onOpenPractice: openPractice)
        case .recentlyDeleted:
            RecentlyDeletedView()
        case .playVsEngine:
            PlayVsEngineView(
                store: library.store,
                engineOpponent: engineService,
                onReviewGame: handleReviewGame
            )
        case .empty:
            emptySelectionView
        }
    }

    private func handleReviewGame(_ game: GameRecord) {
        library.reload()
        if let gameID = game.id {
            librarySource = .allGames
            detailDestination = .game(gameID)
        }
    }

    private var libraryControls: some View {
        VStack(spacing: DesignSpacing.xs) {
            sourceRow("All Games", systemImage: "list.bullet", isSelected: librarySource == .allGames) {
                selectLibrarySource(.allGames)
            }
            sourceRow("Favorites", systemImage: "star", isSelected: librarySource == .favorites) {
                selectLibrarySource(.favorites)
            }
            sourceRow("Player Brief", systemImage: "doc.text.magnifyingglass", isSelected: librarySource == .playerBrief) {
                selectLibrarySource(.playerBrief)
            }
            sourceRow("Play vs Engine", systemImage: "cpu", isSelected: detailDestination == .playVsEngine) {
                detailDestination = .playVsEngine
            }
            sourceRow(
                "Recently Deleted",
                systemImage: "trash",
                count: library.recentlyDeletedGames.isEmpty ? nil : library.recentlyDeletedGames.count,
                isSelected: librarySource == .recentlyDeleted
            ) {
                selectLibrarySource(.recentlyDeleted)
            }

            Divider().padding(.vertical, DesignSpacing.xs)

            HStack {
                Text(librarySource == .favorites ? "Favorite games" : "Game register")
                    .font(.dsSectionHeader)
                    .foregroundStyle(DesignColors.textSecondary)
                Spacer()
                filterButton
                Button(isOrganizing ? "Done" : "Organize") {
                    isOrganizing.toggle()
                    if !isOrganizing {
                        organizedSelection.removeAll()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignColors.surface1)
    }

    private var filterButton: some View {
        Button {
            isShowingFilterPanel = true
        } label: {
            Label(
                filter.activeCount > 0 ? "Filter (\(filter.activeCount))" : "Filter",
                systemImage: "line.3.horizontal.decrease"
            )
            // The active-count variant doubles as the visible state, so the
            // label itself carries the accent rather than a new style.
            .foregroundStyle(filter.activeCount > 0 ? DesignColors.accentText : DesignColors.textPrimary)
        }
        .buttonStyle(.borderless)
        .help("Search and filter the register")
        .popover(isPresented: $isShowingFilterPanel, arrowEdge: .bottom) {
            LibraryFilterPanel(
                filter: $filter,
                options: filterOptions,
                matchingCount: filteredGames.count
            )
        }
    }

    /// What the filter panel offers right now, counted against this source's
    /// unfiltered list so every option is honest about its result size.
    private var filterOptions: LibraryFilterOptions {
        LibraryFilterOptions.build(
            games: sourceGames,
            openingECOByGameID: library.openingECOByGameID,
            accuracyByGameID: library.accuracyByGameID,
            identity: library.briefIdentity
        )
    }

    private func sourceRow(
        _ title: String,
        systemImage: String,
        count: Int? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? DesignColors.accentText : DesignColors.textSecondary)
                Text(title)
                    .foregroundStyle(DesignColors.textPrimary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.dsNotation)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
            .font(.dsBody)
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? DesignColors.selection : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(DesignColors.accent).frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectLibrarySource(_ source: LibrarySource) {
        librarySource = source
        switch source {
        case .allGames:
            if detailDestination == .playerBrief || detailDestination == .recentlyDeleted {
                detailDestination = .empty
            }
        case .favorites:
            if case .game(let gameID) = detailDestination,
                library.games.first(where: { $0.id == gameID })?.isFavorite == true
            {
                return
            }
            detailDestination = .empty
        case .playerBrief:
            detailDestination = .playerBrief
        case .recentlyDeleted:
            detailDestination = .recentlyDeleted
        }
    }

    private var browsingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !pinnedGames.isEmpty {
                    Section {
                        ForEach(pinnedGames) { game in
                            browsingGameRow(game)
                        }
                    } header: {
                        registerHeader("Pinned")
                    }
                }
                Section {
                    ForEach(unpinnedGames) { game in
                        browsingGameRow(game)
                    }
                } header: {
                    registerHeader(pinnedGames.isEmpty ? "Games" : "Recent games")
                }
            }
        }
        .overlay { emptyLibraryOverlay }
    }

    private func browsingGameRow(_ game: GameRecord) -> some View {
        let isSelected = game.id.map { detailDestination == .game($0) } ?? false
        return Button {
            if let id = game.id {
                if librarySource == .playerBrief || librarySource == .recentlyDeleted {
                    librarySource = .allGames
                }
                detailDestination = .game(id)
            }
        } label: {
            gameRow(game)
                .padding(.horizontal, DesignSpacing.md)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? DesignColors.selection : Color.clear)
                .overlay(alignment: .leading) {
                    if isSelected {
                        Rectangle().fill(DesignColors.accent).frame(width: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu { contextMenu(for: game) }
    }

    private func registerHeader(_ title: String) -> some View {
        Text(title)
            .font(.dsSecondary.weight(.semibold))
            .foregroundStyle(DesignColors.textSecondary)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignColors.surface0)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignColors.hairline).frame(height: 1)
            }
    }

    private var organizingList: some View {
        List(selection: $organizedSelection) {
            if !pinnedGames.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedGames) { game in
                        if let id = game.id {
                            gameRow(game).tag(id)
                        }
                    }
                }
            }
            Section(pinnedGames.isEmpty ? "Games" : "Recent games") {
                ForEach(unpinnedGames) { game in
                    if let id = game.id {
                        gameRow(game).tag(id)
                    }
                }
            }
        }
        .overlay { emptyLibraryOverlay }
        .safeAreaInset(edge: .bottom) {
            organizationBar
        }
        .onDeleteCommand {
            requestMoveToRecentlyDeleted(organizedSelection)
        }
    }

    /// This source's games before any search/filter constraint - the base
    /// the filter panel counts its options against.
    private var sourceGames: [GameRecord] {
        librarySource == .favorites ? library.games.filter(\.isFavorite) : library.games
    }

    private var filteredGames: [GameRecord] {
        let identity = library.briefIdentity
        return sourceGames.filter { game in
            filter.matches(
                game,
                openingName: game.id.flatMap { library.openingByGameID[$0] },
                openingECO: game.id.flatMap { library.openingECOByGameID[$0] },
                userAccuracy: game.id.flatMap { library.accuracyByGameID[$0] },
                identity: identity
            )
        }
    }

    private var pinnedGames: [GameRecord] {
        filteredGames.filter { $0.pinnedAt != nil }
    }

    private var unpinnedGames: [GameRecord] {
        filteredGames.filter { $0.pinnedAt == nil }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        GameRow(
            game: game,
            username: library.chessComUsername,
            isAnalyzed: game.id.map { library.analyzedGameIDs.contains($0) } ?? false,
            opening: game.id.flatMap { library.openingByGameID[$0] }
        )
    }

    @ViewBuilder
    private func contextMenu(for game: GameRecord) -> some View {
        if let id = game.id {
            Button(game.pinnedAt == nil ? "Pin" : "Unpin") {
                library.apply(.setPinned([id], game.pinnedAt == nil))
            }
            Button(game.isFavorite ? "Remove from Favorites" : "Mark as Favorite") {
                library.apply(.setFavorite([id], !game.isFavorite))
            }
            Divider()
            Button("Move to Recently Deleted…", role: .destructive) {
                requestMoveToRecentlyDeleted([id])
            }
        }
    }

    private var organizationBar: some View {
        VStack(spacing: DesignSpacing.xs) {
            HStack {
                Text("\(organizedSelection.count) selected")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                Spacer()
                Menu("Organize") {
                    Button("Pin") {
                        applyToOrganizedSelection { .setPinned($0, true) }
                    }
                    Button("Unpin") {
                        applyToOrganizedSelection { .setPinned($0, false) }
                    }
                    Button("Mark as Favorite") {
                        applyToOrganizedSelection { .setFavorite($0, true) }
                    }
                    Button("Remove from Favorites") {
                        applyToOrganizedSelection { .setFavorite($0, false) }
                    }
                }
                .disabled(organizedSelection.isEmpty)
                Button("Move to Recently Deleted…", role: .destructive) {
                    requestMoveToRecentlyDeleted(organizedSelection)
                }
                .disabled(organizedSelection.isEmpty)
            }
            if !lastMovedIDs.isEmpty {
                HStack {
                    Text("\(lastMovedIDs.count) game\(lastMovedIDs.count == 1 ? "" : "s") moved")
                        .font(.dsSecondary)
                    Spacer()
                    Button("Undo") {
                        library.apply(.restore(lastMovedIDs))
                        lastMovedIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var emptyLibraryOverlay: some View {
        if filteredGames.isEmpty {
            let registerIsEmpty = sourceGames.isEmpty
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(emptyStateTitle).font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                Text(emptyStateMessage)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !registerIsEmpty {
                    Button("Clear search and filters") {
                        filter.reset()
                        // The search field is native toolbar UI; its text is
                        // part of the filter value and clears with it.
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(DesignSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var emptyStateTitle: String {
        guard !sourceGames.isEmpty else {
            return librarySource == .favorites ? "No favorite games" : "No games yet"
        }
        return filter.searchText.isEmpty ? "No matching games" : "No results"
    }

    private var emptyStateMessage: String {
        guard !sourceGames.isEmpty else {
            return librarySource == .favorites
                ? "Mark a game as a favorite to find it here."
                : "Import a PGN file or drop one here to get started."
        }
        return "Nothing in the register matches the current search and filters."
    }

    private var emptySelectionView: some View {
        ZStack {
            DesignColors.surface0.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                Text(library.games.isEmpty ? "No games in the register" : "Select a game")
                    .font(.dsTitle)
                    .foregroundStyle(DesignColors.textPrimary)

                Rectangle()
                    .fill(DesignColors.accent)
                    .frame(width: 36, height: 2)

                Text(
                    library.games.isEmpty
                        ? "Import a PGN or fetch your recent chess.com games to begin."
                        : "Choose a game to open the board, score sheet, and analysis."
                )
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
                .frame(maxWidth: 360, alignment: .leading)

                if library.games.isEmpty {
                    HStack(spacing: DesignSpacing.sm) {
                        Button("Play vs Engine") {
                            detailDestination = .playVsEngine
                        }
                        .buttonStyle(.dsPrimary)

                        if library.isChessComAccountConfirmed {
                            Button("Fetch chess.com games") {
                                isShowingChessComFetch = true
                            }
                            Button("Import PGN…") {
                                isShowingImporter = true
                            }
                        } else {
                            Button("Import PGN…") {
                                isShowingImporter = true
                            }
                            Button("Fetch from chess.com…") {
                                isShowingChessComFetch = true
                            }
                        }
                    }
                }
            }
            .padding(DesignSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// Sidebar-bottom action bar - Progress and Add-game live here instead of
    /// the window toolbar. The unified toolbar's native title reserves
    /// nearly all its width for the window title text, forcing anything
    /// placed there behind the ">>" overflow chevron at every supported
    /// width (fact 1 in the redesign plan); the sidebar-bottom bar is the
    /// plan's own documented fallback for exactly this. Import PGN in
    /// particular must never be hidden behind an overflow menu again.
    private var sidebarBottomBar: some View {
        HStack(spacing: DesignSpacing.sm) {
            Menu {
                Button {
                    detailDestination = .playVsEngine
                } label: {
                    Label("Play vs Engine…", systemImage: "cpu")
                }
                Button {
                    isShowingImporter = true
                } label: {
                    Label("Import PGN…", systemImage: "square.and.arrow.down")
                }
                Button {
                    isShowingChessComFetch = true
                } label: {
                    Label("Fetch from chess.com…", systemImage: "globe")
                }
            } label: {
                Label("Add game", systemImage: "plus")
            }
            .help("Add a game")
            Spacer()
            if !unanalyzedGames.isEmpty && !batchAnalysis.isRunning {
                Button {
                    startBatchAnalysis()
                } label: {
                    Label(
                        "Analyze \(unanalyzedGames.count)",
                        systemImage: "wand.and.stars"
                    )
                }
                .help(
                    "Analyze the \(unanalyzedGames.count) game\(unanalyzedGames.count == 1 ? "" : "s") that have no analysis yet, one after another"
                )
            }
            SettingsLink {
                Label(
                    companion.activeDevices.isEmpty
                        ? "Pair iPhone"
                        : "iPhone connected",
                    systemImage: companion.activeDevices.isEmpty
                        ? "iphone.and.arrow.forward"
                        : "iphone.gen3.circle.fill"
                )
            }
            .help("Open Companion settings")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
    }

    /// The games the batch action would work on: everything currently in the
    /// register with no analysis stored.
    private var unanalyzedGames: [GameRecord] {
        BatchAnalysisCoordinator.unanalyzed(
            in: library.games,
            analyzedGameIDs: library.analyzedGameIDs
        )
    }

    private func startBatchAnalysis() {
        startBatchAnalysis(of: unanalyzedGames)
    }

    private func startBatchAnalysis(of candidates: [GameRecord]) {
        let games = BatchAnalysisCoordinator.unanalyzed(
            in: candidates,
            analyzedGameIDs: library.analyzedGameIDs
        )
        let quality = library.analysisQuality
        batchAnalysis.start(games: games) { game in
            try await companion.analyzeLocally(
                game: game,
                quality: quality,
                reanalyze: false
            )
            library.reload()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !library.hasCompletedOnboarding },
            set: { isPresented in if !isPresented { library.completeOnboarding() } }
        )
    }

    private var moveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !pendingMoveIDs.isEmpty },
            set: { if !$0 { pendingMoveIDs.removeAll() } }
        )
    }

    private var moveConfirmationTitle: String {
        "Move \(pendingMoveIDs.count) game\(pendingMoveIDs.count == 1 ? "" : "s") to Recently Deleted?"
    }

    private func requestMoveToRecentlyDeleted(_ gameIDs: Set<Int64>) {
        guard !gameIDs.isEmpty else { return }
        pendingMoveIDs = gameIDs
    }

    private func movePendingGames() {
        let gameIDs = pendingMoveIDs
        pendingMoveIDs.removeAll()
        guard library.apply(.moveToRecentlyDeleted(gameIDs)) != nil else { return }
        organizedSelection.subtract(gameIDs)
        lastMovedIDs = gameIDs
    }

    private func applyToOrganizedSelection(
        command: (Set<Int64>) -> LibraryCommand
    ) {
        guard !organizedSelection.isEmpty else { return }
        library.apply(command(organizedSelection))
    }

    private func openPractice(
        gameID: Int64,
        loadCards: @escaping () async throws -> [TrainingCardRecord]
    ) {
        librarySource = .allGames
        detailDestination = .game(gameID)
        pendingPracticeGameID = gameID
        pendingPracticeLoadCards = loadCards
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importFile(at: url)
            }
        case .failure(let error):
            library.errorMessage = error.localizedDescription
        }
    }

    private func importFile(at url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            importPGNText(contents)
        } catch {
            library.errorMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            if let text {
                Task { @MainActor in
                    importPGNText(text)
                }
            }
        }
        return true
    }

    private func importPGNText(_ text: String) {
        if let saved = library.importPGN(text) {
            if let gameID = saved.id {
                librarySource = .allGames
                detailDestination = .game(gameID)
            }
        }
    }
}

extension UTType {
    static let pgn = UTType(filenameExtension: "pgn") ?? .plainText
}

private struct GameRow: View {
    let game: GameRecord
    let username: String
    let isAnalyzed: Bool
    let opening: String?

    var body: some View {
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            outcomeIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.white) - \(game.black)")
                    .font(.dsBody.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let formattedTimeControl = GameRowMetadata.formattedTimeControl(game.timeControl) {
                        Text(formattedTimeControl)
                    }
                    if let dateText {
                        Text("·")
                        Text(dateText)
                    }
                    if let opening {
                        Text("·")
                        Text(opening).lineLimit(1)
                    }
                }
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if game.pinnedAt != nil {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(DesignColors.accentText)
                    .accessibilityLabel("Pinned")
            }
            if game.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(DesignColors.accentText)
                    .accessibilityLabel("Favorite")
            }
            if isAnalyzed {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignColors.textSecondary)
                    .accessibilityLabel("Analyzed")
            }
        }
        .padding(.vertical, 3)
    }

    /// The user's own win/loss/draw perspective when they played this game,
    /// else the raw result.
    @ViewBuilder
    private var outcomeIndicator: some View {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        if !trimmedUsername.isEmpty, let outcome = userOutcome(username: trimmedUsername) {
            Text(outcome.abbreviation)
                .font(.dsNotation.weight(.semibold))
                .frame(width: 18)
                .foregroundStyle(outcome.color)
                .accessibilityLabel(outcome.accessibilityLabel)
        } else if let resultText = GameRowMetadata.plainResult(game.result) {
            Text(resultText)
                .font(.dsSecondary)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DesignColors.textSecondary)
                .accessibilityLabel(resultText)
        } else {
            Text("·")
                .font(.dsNotation)
                .frame(width: 18)
                .foregroundStyle(DesignColors.textSecondary)
        }
    }

    private enum Outcome {
        case win, loss, draw

        var abbreviation: String {
            switch self {
            case .win: return "W"
            case .loss: return "L"
            case .draw: return "D"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .win: return "You won"
            case .loss: return "You lost"
            case .draw: return "Draw"
            }
        }

        var color: Color {
            switch self {
            case .win: return DesignColors.accentText
            case .loss: return DesignColors.error
            case .draw: return DesignColors.textSecondary
            }
        }
    }

    private func userOutcome(username: String) -> Outcome? {
        guard let result = game.result else { return nil }
        let isWhite = game.white.caseInsensitiveCompare(username) == .orderedSame
        let isBlack = game.black.caseInsensitiveCompare(username) == .orderedSame
        guard isWhite || isBlack else { return nil }
        switch result {
        case "1-0": return isWhite ? .win : .loss
        case "0-1": return isBlack ? .win : .loss
        case "1/2-1/2": return .draw
        default: return nil
        }
    }

    private var dateText: String? {
        guard let date = game.playedAt else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum GameRowMetadata {
    /// Formats a chess result string ("1-0", "0-1", "1/2-1/2") into plain language
    /// ("White won", "Black won", "Draw") so learners do not read raw numbers as sports scores.
    static func plainResult(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "1-0": return "White won"
        case "0-1": return "Black won"
        case "1/2-1/2": return "Draw"
        case "*": return nil
        default: return raw
        }
    }

    /// Turns chess.com's raw `TimeControl` seconds string ("180", "180+2",
    /// "1/259200") into a human-readable label ("3 min", "3+2 · Blitz").
    static func formattedTimeControl(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let components = raw.split(separator: "+", maxSplits: 1)
        let baseSeconds: Int?
        if raw.contains("/") {
            baseSeconds = nil
        } else {
            baseSeconds = components.first.flatMap { Int($0) }
        }
        guard let seconds = baseSeconds else { return raw }
        let increment = components.count == 2 ? Int(components[1]) : nil
        let minutes = seconds / 60
        let clock = increment.map { "\(minutes)+\($0)" } ?? "\(minutes) min"
        switch seconds {
        case ..<180:
            return increment.map { "\(seconds)+\($0) sec" } ?? "\(seconds) sec"
        case 180..<600:
            return "\(clock) · Blitz"
        case 600..<1800:
            return "\(clock) · Rapid"
        default:
            return clock
        }
    }
}
