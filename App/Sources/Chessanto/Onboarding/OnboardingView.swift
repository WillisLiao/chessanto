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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

            pageProgress

            Divider()

            HStack {
                if page != .welcome {
                    Button("Back") { back() }
                }
                Spacer()
                Button("Skip") { finish() }
                Button(page == .coach ? "Finish" : "Next") { advance() }
                    .buttonStyle(.dsPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 460)
        .background(DesignColors.surface0)
        .onAppear {
            username = library.chessComUsername
        }
    }

    private var pageProgress: some View {
        HStack(spacing: DesignSpacing.sm) {
            ForEach(Page.allCases, id: \.self) { candidate in
                Circle()
                    .fill(candidate == page ? DesignColors.accent : DesignColors.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, DesignSpacing.sm)
        .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xl) {
            HStack(spacing: DesignSpacing.lg) {
                ChessantoEmblem(size: 112)

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("Welcome to Chessanto")
                        .font(.dsTitle)
                        .foregroundStyle(DesignColors.textPrimary)
                    Text("Turn your own games into clear, trustworthy lessons - privately on this Mac.")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                welcomeBenefit(
                    icon: "lock.shield.fill",
                    title: "Private by default",
                    detail: "Your games and analysis stay on this Mac."
                )
                welcomeBenefit(
                    icon: "checkmark.seal.fill",
                    title: "Engine-verified guidance",
                    detail: "Coaching stays grounded in legal moves and real evaluation."
                )
                welcomeBenefit(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Built for improvement",
                    detail: "See the moments and patterns that will help your next game."
                )
            }
        }
    }

    private func welcomeBenefit(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: DesignSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignColors.accent)
                .frame(width: 28, height: 28)
                .background(DesignColors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DesignShape.controlRadius))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                Text(detail)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
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
            ChessComUsernameField(username: $username) { validated in
                library.saveChessComUsername(validated)
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
        library.saveChessComUsername(username)
        var profile = (try? library.store.userProfile()) ?? UserProfileRecord()
        profile.ratingBand = ratingBand
        profile.coachEnabled = coachEnabled
        profile.coachModel = coachModel.isEmpty ? nil : coachModel
        _ = try? library.store.saveUserProfile(profile)
        library.completeOnboarding()
        dismiss()
    }
}
