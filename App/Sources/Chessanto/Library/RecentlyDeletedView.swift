import Persistence
import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var selection: Set<Int64> = []
    @State private var pendingPermanentDeletion: Set<Int64> = []
    @State private var confirmationPhrase = ""

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text("Recently Deleted")
                        .font(.dsTitle)
                        .foregroundStyle(DesignColors.textPrimary)
                    Text("Restore games here, or permanently delete them and all related analysis, variations, Coach conversations, and practice history.")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()

                Divider().overlay(DesignColors.hairline)

                if library.recentlyDeletedGames.isEmpty {
                    ContentUnavailableView(
                        "Recently Deleted is empty",
                        systemImage: "trash",
                        description: Text("Games moved here remain recoverable until you permanently delete them.")
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(200, proxy.size.height - 170),
                        maxHeight: .infinity
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(library.recentlyDeletedGames) { game in
                                if let id = game.id {
                                    Button {
                                        if selection.contains(id) {
                                            selection.remove(id)
                                        } else {
                                            selection.insert(id)
                                        }
                                    } label: {
                                        RecentlyDeletedGameRow(game: game)
                                            .padding(.horizontal, DesignSpacing.md)
                                            .background(
                                                selection.contains(id)
                                                    ? DesignColors.selection : Color.clear
                                            )
                                            .overlay(alignment: .leading) {
                                                if selection.contains(id) {
                                                    Rectangle()
                                                        .fill(DesignColors.accent)
                                                        .frame(width: 2)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(height: max(200, proxy.size.height - 170))
                    .onChange(of: library.recentlyDeletedGames.map(\.id)) { _, currentIDs in
                        selection.formIntersection(Set(currentIDs.compactMap { $0 }))
                    }
                }

                Divider().overlay(DesignColors.hairline)

                HStack {
                    Text("\(selection.count) selected")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                    Spacer()
                    Button("Restore") {
                        library.apply(.restore(selection))
                        selection.removeAll()
                    }
                    .disabled(selection.isEmpty)
                    Button("Delete Permanently…", role: .destructive) {
                        confirmationPhrase = ""
                        pendingPermanentDeletion = selection
                    }
                    .disabled(selection.isEmpty)
                }
                .padding()
            }
        }
        .background(DesignColors.surface0)
        .alert(
            permanentDeletionTitle,
            isPresented: permanentDeletionBinding
        ) {
            TextField(requiredConfirmationPhrase, text: $confirmationPhrase)
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                let deletedIDs = pendingPermanentDeletion
                pendingPermanentDeletion.removeAll()
                library.apply(.deletePermanently(deletedIDs))
                selection.subtract(deletedIDs)
            }
            .disabled(confirmationPhrase != requiredConfirmationPhrase)
        } message: {
            Text("This cannot be undone. Type \(requiredConfirmationPhrase) to confirm deletion of the selected games and all related data.")
        }
    }

    private var permanentDeletionBinding: Binding<Bool> {
        Binding(
            get: { !pendingPermanentDeletion.isEmpty },
            set: {
                if !$0 {
                    pendingPermanentDeletion.removeAll()
                    confirmationPhrase = ""
                }
            }
        )
    }

    private var permanentDeletionTitle: String {
        "Permanently delete \(pendingPermanentDeletion.count) game\(pendingPermanentDeletion.count == 1 ? "" : "s")?"
    }

    private var requiredConfirmationPhrase: String {
        "DELETE \(pendingPermanentDeletion.count)"
    }
}

private struct RecentlyDeletedGameRow: View {
    let game: GameRecord

    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DesignColors.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.white) vs \(game.black)")
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                if let deletedAt = game.deletedAt {
                    Text("Moved \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
            }
            Spacer()
            if game.pinnedAt != nil {
                Image(systemName: "pin.fill")
                    .foregroundStyle(DesignColors.accentText)
                    .accessibilityLabel("Pinned")
            }
            if game.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(DesignColors.accentText)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, DesignSpacing.xs)
    }
}
