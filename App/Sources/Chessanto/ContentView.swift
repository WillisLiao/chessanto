import SwiftUI
import UniformTypeIdentifiers
import Persistence

struct ContentView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var selectedGameID: Int64?
    @State private var isShowingImporter = false
    @State private var isShowingChessComFetch = false
    @State private var isShowingDashboard = false
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(library.games, selection: $selectedGameID) { game in
                    GameRow(
                        game: game,
                        username: library.chessComUsername,
                        isAnalyzed: game.id.map { library.analyzedGameIDs.contains($0) } ?? false,
                        opening: game.id.flatMap { library.openingByGameID[$0] }
                    ).tag(game.id)
                }
                .overlay {
                    if library.games.isEmpty {
                        ContentUnavailableView(
                            "No games yet",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Import a PGN file or drop one here to get started.")
                        )
                    }
                }
                sidebarBottomBar
            }
            .navigationTitle("Games")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            if let selectedGameID, let game = library.games.first(where: { $0.id == selectedGameID }) {
                GameReplayView(game: game, store: library.store)
                    .id(game.id)
            } else {
                emptySelectionView
            }
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
            ChessComFetchView()
        }
        .sheet(isPresented: $isShowingDashboard) {
            DashboardView()
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importPGNRequested)) { _ in
            isShowingImporter = true
        }
        .alert("Import error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var emptySelectionView: some View {
        ZStack {
            DesignColors.surface0.ignoresSafeArea()

            VStack(spacing: DesignSpacing.lg) {
                ChessantoEmblem(size: 104)

                VStack(spacing: DesignSpacing.xs) {
                    Text(library.games.isEmpty ? "Your chess journey starts here" : "Select a game")
                        .font(.dsTitle)
                        .foregroundStyle(DesignColors.textPrimary)

                    Text(
                        library.games.isEmpty
                            ? "Import a game and Chessanto will turn the engine's numbers into moments you can learn from."
                            : "Choose a game from the sidebar to replay, analyze, and ask the Coach about any position."
                    )
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
                }

                HStack(spacing: DesignSpacing.sm) {
                    Button("Import PGN…") {
                        isShowingImporter = true
                    }
                    .buttonStyle(.dsPrimary)

                    Button("Fetch from chess.com…") {
                        isShowingChessComFetch = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(DesignSpacing.xl)
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
            Button {
                isShowingDashboard = true
            } label: {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .labelStyle(.iconOnly)
            }
            .help("Progress")

            Spacer()

            Menu {
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
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
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
            selectedGameID = saved.id
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
        HStack(alignment: .top, spacing: DesignSpacing.sm) {
            outcomeIndicator
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.white).font(.dsBody.weight(.semibold)).lineLimit(1)
                Text("vs \(game.black)").font(.dsSecondary).foregroundStyle(DesignColors.textSecondary).lineLimit(1)

                HStack(spacing: DesignSpacing.xs) {
                    if let formattedTimeControl {
                        Text(formattedTimeControl)
                    }
                    if let dateText {
                        Text("·")
                        Text(dateText)
                    }
                }
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)

                if let opening {
                    Text(opening)
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isAnalyzed {
                Circle()
                    .fill(DesignColors.accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                    .accessibilityLabel("Analyzed")
            }
        }
        .padding(.vertical, 4)
    }

    /// The user's own win/loss/draw perspective when they played this game,
    /// else the raw result.
    @ViewBuilder
    private var outcomeIndicator: some View {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        if !trimmedUsername.isEmpty, let outcome = userOutcome(username: trimmedUsername) {
            Text(outcome.abbreviation)
                .font(.dsSecondary.weight(.bold))
                .frame(width: 16, height: 16)
                .background(outcome.color.opacity(0.18))
                .foregroundStyle(outcome.color)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(DesignColors.hairline)
                .frame(width: 6, height: 6)
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

        var color: Color {
            switch self {
            case .win: return .green
            case .loss: return .red
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

    /// Turns chess.com's raw `TimeControl` seconds string ("180", "180+2",
    /// "1/259200") into a human-readable label ("3 min", "Blitz", "Rapid").
    private var formattedTimeControl: String? {
        guard let raw = game.timeControl, !raw.isEmpty else { return nil }
        let baseSeconds: Int?
        if raw.contains("/") {
            baseSeconds = nil
        } else {
            baseSeconds = Int(raw.split(separator: "+").first ?? "")
        }
        guard let seconds = baseSeconds else { return raw }
        let minutes = seconds / 60
        switch seconds {
        case ..<180: return "\(seconds) sec"
        case 180..<600: return "\(minutes) min · Blitz"
        case 600..<1800: return "\(minutes) min · Rapid"
        default: return "\(minutes) min"
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
