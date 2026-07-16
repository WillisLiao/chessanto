import SwiftUI
import UniformTypeIdentifiers
import Persistence

struct ContentView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var selectedGameID: Int64?
    @State private var isShowingImporter = false
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            List(library.games, selection: $selectedGameID) { game in
                GameRow(game: game).tag(game.id)
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingImporter = true
                    } label: {
                        Label("Import PGN", systemImage: "square.and.arrow.down")
                    }
                }
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
        } detail: {
            if let selectedGameID, let game = library.games.first(where: { $0.id == selectedGameID }) {
                GameReplayView(game: game, store: library.store)
            } else {
                ContentUnavailableView(
                    "Select a game",
                    systemImage: "checkerboard.rectangle",
                    description: Text("Choose a game from the sidebar to replay and analyze it.")
                )
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
        .onReceive(NotificationCenter.default.publisher(for: .importPGNRequested)) { _ in
            isShowingImporter = true
        }
        .alert("Import error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(game.white) vs \(game.black)")
                .font(.headline)
            HStack(spacing: 6) {
                if let result = game.result {
                    Text(result)
                }
                if let timeControl = game.timeControl {
                    Text(timeControl)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
