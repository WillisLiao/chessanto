import SwiftUI

/// The General settings tab: analysis quality default, board theme, and the
/// chess.com username - the settings that aren't specific to the coach.
struct GeneralSettingsView: View {
    @EnvironmentObject private var library: GameLibrary

    @State private var quality: AnalysisQuality = .standard
    @State private var theme: BoardTheme = .classic
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
            }

            Section("chess.com") {
                ChessComUsernameField(username: $username) { validated in
                    library.saveChessComUsername(validated)
                }
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 280)
        .onAppear {
            quality = library.analysisQuality
            theme = library.boardTheme
            username = library.chessComUsername
        }
    }
}
