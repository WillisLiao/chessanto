import Persistence
import SwiftUI

/// A one-time, four-page flow shown from `ContentView` when
/// `hasCompletedOnboarding` is false. Every page is skippable; finishing (or
/// skipping out of) the flow sets the flag so it never reappears.
/// `CoachSettingsView` stays the ongoing settings surface - this reuses its
/// pieces (`CoachSetupView`) rather than duplicating them.
struct OnboardingView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss

    private enum Page: Int, CaseIterable {
        case welcome, username, ratingBand, coach
    }

    @State private var page: Page = .welcome
    @State private var username = ""
    @State private var ratingBand = "adaptive"
    @State private var coachEnabled = false
    @State private var coachModel = ""

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .welcome: welcomePage
                case .username: usernamePage
                case .ratingBand: ratingBandPage
                case .coach: coachPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            Divider()

            HStack {
                if page != .welcome {
                    Button("Back") { back() }
                }
                Spacer()
                Button("Skip") { finish() }
                Button(page == .coach ? "Finish" : "Next") { advance() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
        .onAppear {
            username = library.chessComUsername
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Welcome to Chessanto")
                .font(.title.bold())
            Text("Import your chess.com or PGN games, analyze them with a local chess engine, and get a coached report explaining your key moments - all running on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var usernamePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your chess.com username")
                .font(.title2.bold())
            Text("Optional - PGN-only import works fine without one. If you set it, you can fetch your recent games straight from chess.com.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ChessComUsernameField(username: $username) { validated in
                library.saveChessComUsername(validated)
            }
        }
    }

    private var ratingBandPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teaching level")
                .font(.title2.bold())
            Text("How the coach pitches its explanations. You can change this any time in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Teaching level", selection: $ratingBand) {
                Text("Adaptive (recommended)").tag("adaptive")
                Text("Beginner").tag("beginner")
                Text("Intermediate").tag("intermediate")
                Text("Advanced").tag("advanced")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    private var coachPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verified Coach")
                .font(.title2.bold())
            Text("Optional local AI narration on top of the rule-based report, grounded so it never states an unverified move or evaluation. Needs Ollama running locally.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                CoachSetupView(coachEnabled: $coachEnabled, ratingBand: $ratingBand, coachModel: $coachModel, showsTeachingLevel: false)
            }
        }
    }

    private func back() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        page = previous
    }

    private func advance() {
        if let next = Page(rawValue: page.rawValue + 1) {
            page = next
        } else {
            finish()
        }
    }

    private func finish() {
        library.saveChessComUsername(username)
        var profile = (try? library.store.userProfile()) ?? UserProfileRecord()
        profile.ratingBand = ratingBand
        profile.coachEnabled = coachEnabled
        profile.coachModel = coachModel.isEmpty ? nil : coachModel
        try? library.store.saveUserProfile(profile)
        library.completeOnboarding()
        dismiss()
    }
}
