import SwiftUI

/// The General settings tab: analysis quality default, board theme, and the
/// chess.com username - the settings that aren't specific to the coach.
struct GeneralSettingsView: View {
    @EnvironmentObject private var library: GameLibrary

    @State private var quality: AnalysisQuality = .standard
    @State private var theme: BoardTheme = .classic
    @State private var notationStyle: MoveNotationStyle = .standard
    @State private var username: String = ""

    var body: some View {
        Form {
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
