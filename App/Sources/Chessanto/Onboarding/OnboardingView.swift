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
    @State private var confirmedUsername: String?
    @State private var ratingBand = "adaptive"
    @State private var coachEnabled = false
    @State private var coachModel = ""

    var body: some View {
        HStack(spacing: 0) {
            stepRail
                .frame(width: 150)
            Divider()
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case .welcome: welcomePage
                    case .username: usernamePage
                    case .ratingBand: ratingBandPage
                    case .coach: coachPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DesignSpacing.xl)

                Divider()

                HStack {
                    if page != .welcome {
                        Button("Back") { back() }
                    }
                    Spacer()
                    Button("Set up later") { finish() }
                    Button(page == .coach ? "Finish" : "Continue") { advance() }
                        .buttonStyle(.dsPrimary)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(width: 640, height: 450)
        .background(DesignColors.surface0)
        .onAppear {
            username = library.chessComUsername
            confirmedUsername = library.isChessComAccountConfirmed
                ? library.chessComUsername
                : nil
        }
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Chessanto")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignColors.textPrimary)
                .padding(.bottom, DesignSpacing.lg)
            ForEach(Page.allCases, id: \.self) { candidate in
                HStack(spacing: DesignSpacing.sm) {
                    Text("\(candidate.rawValue + 1)")
                        .font(.dsNotation)
                        .foregroundStyle(candidate == page ? DesignColors.accentText : DesignColors.textSecondary)
                        .frame(width: 14)
                    Text(stepTitle(candidate))
                        .font(.dsBody.weight(candidate == page ? .semibold : .regular))
                        .foregroundStyle(DesignColors.textPrimary)
                }
                .padding(.vertical, 3)
                .overlay(alignment: .leading) {
                    if candidate == page {
                        Rectangle()
                            .fill(DesignColors.accent)
                            .frame(width: 2)
                            .offset(x: -DesignSpacing.sm)
                    }
                }
            }
            Spacer()
            Text("Games and analysis stay on this Mac.")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSpacing.lg)
        .background(DesignColors.surface1)
        .accessibilityElement(children: .contain)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Text("Your games, turned into a study record")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DesignColors.textPrimary)
            Text("Chessanto reviews your own play, keeps every claim tied to analysis, and builds the positions worth revisiting.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                welcomeCommitment("Private by default", "Games and analysis stay on this Mac.")
                welcomeCommitment("Engine verified", "Moves and evaluations come from the local engine.")
                welcomeCommitment("Evidence led", "Player insights show the games and counts behind them.")
            }
        }
    }

    private func welcomeCommitment(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.lg) {
            Text(title)
                .font(.dsBody.weight(.semibold))
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(detail)
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding(.vertical, DesignSpacing.md)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
    }

    private func stepTitle(_ page: Page) -> String {
        switch page {
        case .welcome: return "Welcome"
        case .username: return "Account"
        case .ratingBand: return "Teaching level"
        case .coach: return "Local Coach"
        }
    }

    private var usernamePage: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Text("Your chess.com username")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
            Text("Optional - PGN-only import works fine without one. If you set it, you can fetch your recent games straight from chess.com.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
            ChessComUsernameField(
                username: $username,
                savedUsername: confirmedUsername
            ) { account in
                confirmedUsername = account.username
            }
        }
    }

    private var ratingBandPage: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Text("Teaching level")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
            Text("How the coach pitches its explanations. You can change this any time in Settings.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
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
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Text("Verified Coach")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
            Text("Optional local AI narration on top of the rule-based report, grounded so it never states an unverified move or evaluation. Needs Ollama running locally.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
            CoachSetupView(coachEnabled: $coachEnabled, ratingBand: $ratingBand, coachModel: $coachModel, showsTeachingLevel: false)
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
        if let confirmedUsername {
            library.saveChessComUsername(confirmedUsername, confirmed: true)
        }
        var profile = (try? library.store.userProfile()) ?? UserProfileRecord()
        profile.ratingBand = ratingBand
        profile.coachEnabled = coachEnabled
        profile.coachModel = coachModel.isEmpty ? nil : coachModel
        _ = try? library.store.saveUserProfile(profile)
        library.completeOnboarding()
        dismiss()
    }
}
