import SwiftUI
import ChessComKit
import Persistence

/// Sheet: enter a chess.com username, fetch recent games, multi-select and
/// import. Every chess.com-specific failure surfaces as an alert rather than
/// blocking the rest of the app - PGN import and analysis never depend on
/// this view working.
struct ChessComFetchView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var games: [ChessComGame] = []
    @State private var alreadyImportedURLs: Set<String> = []
    @State private var selection: Set<String> = []
    @State private var isLoading = false
    @State private var fetchError: String?
    @State private var didFetch = false

    private let client = ChessComClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { username = library.chessComUsername }
        .alert("Couldn't fetch from chess.com", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fetchError ?? "")
        }
    }

    private var header: some View {
        HStack {
            TextField("chess.com username", text: $username)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await fetch() } }
            Button {
                Task { await fetch() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Fetch")
                }
            }
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if games.isEmpty {
            ContentUnavailableView(
                didFetch ? "No games found" : "Enter a username",
                systemImage: "network",
                description: Text(
                    didFetch
                        ? "This account has no recent games, or chess.com returned nothing."
                        : "Fetches recent games from chess.com's public API."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(games, selection: $selection) { game in
                gameRow(game).tag(game.url)
            }
            .listStyle(.inset)
        }
    }

    private func gameRow(_ game: ChessComGame) -> some View {
        let imported = alreadyImportedURLs.contains(game.url)
        return HStack {
            Button {
                toggle(game.url)
            } label: {
                Image(systemName: imported ? "checkmark.circle.fill" : (selection.contains(game.url) ? "checkmark.square.fill" : "square"))
            }
            .buttonStyle(.plain)
            .disabled(imported)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.white.username) (\(game.white.rating)) vs \(game.black.username) (\(game.black.rating))")
                    .font(.body)
                HStack(spacing: 6) {
                    Text(game.white.result)
                    Text(game.timeControl)
                    Text(game.endTime, style: .date)
                    if imported {
                        Text("Already imported").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .opacity(imported ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { toggle(game.url) }
    }

    private var footer: some View {
        HStack {
            Text(footerSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Import \(selection.count) Game\(selection.count == 1 ? "" : "s")") {
                importSelected()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection.isEmpty)
        }
        .padding()
    }

    private var footerSummary: String {
        guard !games.isEmpty else { return "" }
        return "\(games.count) games fetched, \(alreadyImportedURLs.count) already imported"
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { fetchError != nil }, set: { if !$0 { fetchError = nil } })
    }

    private func toggle(_ url: String) {
        guard !alreadyImportedURLs.contains(url) else { return }
        if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }
    }

    private func fetch() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await client.recentGames(username: trimmed)
            games = fetched
            let urls = Set(fetched.map(\.url))
            alreadyImportedURLs = library.alreadyImported(sourceURLs: urls)
            selection = []
            library.saveChessComUsername(trimmed)
            didFetch = true
        } catch {
            games = []
            fetchError = error.localizedDescription
        }
    }

    private func importSelected() {
        for game in games where selection.contains(game.url) {
            library.importPGN(game.pgn, source: .chessCom, sourceURL: game.url)
        }
        dismiss()
    }
}
