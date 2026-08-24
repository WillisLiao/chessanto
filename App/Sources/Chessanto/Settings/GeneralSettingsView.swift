import SwiftUI

/// The General settings tab: analysis quality default, board theme, and the
/// chess.com username - the settings that aren't specific to the coach.
struct GeneralSettingsView: View {
    @EnvironmentObject private var library: GameLibrary

    @State private var quality: AnalysisQuality = .standard
    @State private var theme: BoardTheme = .classic
    @State private var notationStyle: MoveNotationStyle = .standard
    @State private var soundsEnabled = true
    @State private var playerName = ""
    @State private var username: String = ""
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode", isOn: $prefersDarkMode)
                Text("Chessanto defaults to light. Enable dark mode for evening or low-light study.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Analysis") {
                Picker("Default quality", selection: $quality) {
                    ForEach(AnalysisQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .onChange(of: quality) { _, newValue in library.saveAnalysisQuality(newValue) }
            }

            Section("Board") {
                Picker("Theme", selection: $theme) {
                    ForEach(BoardTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .onChange(of: theme) { _, newValue in library.saveBoardTheme(newValue) }

                HStack(spacing: DesignSpacing.md) {
                    ForEach(BoardTheme.allCases) { candidate in
                        themeSwatch(candidate)
                    }
                }
                .padding(.vertical, DesignSpacing.xs)

                Toggle("Play move and capture sounds", isOn: $soundsEnabled)
                    .onChange(of: soundsEnabled) { _, newValue in
                        library.saveBoardSoundsEnabled(newValue)
                        // Sound the change so the toggle demonstrates what it
                        // controls instead of only describing it.
                        if newValue { BoardSounds.shared.play(.move) }
                    }

                Text("Captures sound different from quiet moves, so you can hear what happened while stepping through a game.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Move notation") {
                Picker("Show moves as", selection: $notationStyle) {
                    ForEach(MoveNotationStyle.allCases) { style in
                        Text(style.settingsExample)
                            .accessibilityLabel(
                                "\(style.settingsLabel), \(style.settingsExample)"
                            )
                        .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: notationStyle) { _, newValue in
                    library.saveMoveNotationStyle(newValue)
                }

                Text("Nf3 uses standard chess notation. Knight f3 spells out piece names. Imported games and analysis remain unchanged.")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("You") {
                Picker("Your name in imported games", selection: $playerName) {
                    Text("Not set").tag("")
                    ForEach(library.playerNameCandidates, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(library.isChessComAccountConfirmed)
                .onChange(of: playerName) { _, newValue in
                    library.savePlayerName(newValue.isEmpty ? nil : newValue)
                }

                Text(
                    library.isChessComAccountConfirmed
                        ? "Your confirmed chess.com account already identifies you, so Player Brief uses that."
                        : "Player Brief and the practice queue track the games you played. Pick your name from the games you have imported."
                )
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("chess.com account") {
                ChessComUsernameField(
                    username: $username,
                    savedUsername: library.isChessComAccountConfirmed
                        ? library.chessComUsername
                        : nil,
                    onConfirmed: { account in
                        username = account.username
                        library.saveChessComUsername(account.username, confirmed: true)
                    },
                    onDisconnect: {
                        username = ""
                        library.saveChessComUsername("")
                    }
                )
            }
        }
        .formStyle(.grouped)
        .background(DesignColors.surface0)
        .frame(minWidth: 640, minHeight: 560)
        .onAppear {
            quality = library.analysisQuality
            theme = library.boardTheme
            notationStyle = library.moveNotationStyle
            soundsEnabled = library.boardSoundsEnabled
            playerName = library.playerName ?? ""
            username = library.chessComUsername
        }
    }

    /// A live-colored 4x4 preview of the theme's actual square colors, not
    /// a bare menu entry - lets the user see what they're picking.
    private func themeSwatch(_ candidate: BoardTheme) -> some View {
        Button {
            theme = candidate
            library.saveBoardTheme(candidate)
        } label: {
            VStack(spacing: DesignSpacing.xs) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<2) { row in
                        GridRow {
                            ForEach(0..<2) { col in
                                ((row + col) % 2 == 0 ? candidate.lightSquare : candidate.darkSquare)
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(candidate == theme ? DesignColors.accent : DesignColors.hairline, lineWidth: candidate == theme ? 2 : 1)
                )
                Text(candidate.label).font(.dsSecondary).foregroundStyle(DesignColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.label) board theme")
    }
}
