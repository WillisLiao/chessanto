import ChessComKit
import SwiftUI

/// Shared two-step chess.com identity confirmation for onboarding and
/// Settings. Looking up an account never persists it. Only the explicit
/// confirmation action crosses the caller's persistence seam.
struct ChessComUsernameField: View {
    @Binding var username: String
    let savedUsername: String?
    var onConfirmed: (ChessComAccount) -> Void
    var onDisconnect: (() -> Void)?

    @StateObject private var model = ChessComAccountLookupModel()
    @State private var isChangingAccount = false
    @State private var isConfirmingDisconnect = false

    init(
        username: Binding<String>,
        savedUsername: String? = nil,
        onConfirmed: @escaping (ChessComAccount) -> Void,
        onDisconnect: (() -> Void)? = nil
    ) {
        _username = username
        self.savedUsername = savedUsername
        self.onConfirmed = onConfirmed
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            if showsConnectedAccount {
                connectedAccount
            } else {
                lookupControls
                lookupResult
            }
        }
        .alert("Disconnect chess.com account?", isPresented: $isConfirmingDisconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                username = ""
                isChangingAccount = false
                model.invalidateCandidate()
                onDisconnect?()
            }
        } message: {
            Text("Your imported games stay on this Mac. Fetching and Player Brief matching will stop until you confirm another account.")
        }
    }

    private var showsConnectedAccount: Bool {
        guard !isChangingAccount,
            let savedUsername,
            !savedUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }

    private var connectedAccount: some View {
        HStack(spacing: DesignSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(savedUsername ?? "")")
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                Text("Connected")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            Spacer()
            Button("Change account") {
                username = ""
                isChangingAccount = true
                model.invalidateCandidate()
            }
            .buttonStyle(.bordered)
            if onDisconnect != nil {
                Button("Disconnect", role: .destructive) {
                    isConfirmingDisconnect = true
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, DesignSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var lookupControls: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text("chess.com username")
                .font(.dsSecondary.weight(.semibold))
                .foregroundStyle(DesignColors.textPrimary)
            HStack(spacing: DesignSpacing.sm) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { startLookup() }
                    .onChange(of: username) { _, newValue in
                        invalidateCandidateIfNeeded(for: newValue)
                    }

                Button {
                    startLookup()
                } label: {
                    if case .lookingUp = model.state {
                        HStack(spacing: DesignSpacing.xs) {
                            ProgressView().controlSize(.small)
                            Text("Finding")
                        }
                    } else {
                        Text("Find account")
                    }
                }
                .disabled(
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isLookingUp
                )
            }
            Text("Chessanto will show the account before saving it. Account proof is text-only, and no remote profile image is loaded.")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
        }
    }

    @ViewBuilder
    private var lookupResult: some View {
        switch model.state {
        case .idle, .lookingUp:
            EmptyView()
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.error)
                .accessibilityLabel("Account lookup failed. \(message)")
        case .candidate(let account):
            candidateCard(account)
        case .confirmed(let account):
            Label(
                "Connected as @\(account.username)",
                systemImage: "checkmark.seal.fill"
            )
            .font(.dsBody.weight(.semibold))
            .foregroundStyle(DesignColors.accentText)
        }
    }

    private func candidateCard(_ account: ChessComAccount) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? account.username)
                        .font(.dsBody.weight(.semibold))
                        .foregroundStyle(DesignColors.textPrimary)
                    Text("@\(account.username)")
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                    if let countryCode = account.countryCode {
                        Text("Country: \(countryCode)")
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                }
                Spacer()
                Link("View on chess.com", destination: account.profileURL)
            }

            if !ratingItems(account).isEmpty {
                HStack(spacing: DesignSpacing.lg) {
                    ForEach(ratingItems(account), id: \.0) { label, rating in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label)
                                .font(.dsSecondary)
                                .foregroundStyle(DesignColors.textSecondary)
                            Text("\(rating)")
                                .font(.dsNotation)
                                .foregroundStyle(DesignColors.textPrimary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Current ratings unavailable")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }

            HStack {
                Button("Not me") {
                    model.invalidateCandidate()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Use this account") {
                    model.confirmCandidate()
                    username = account.username
                    isChangingAccount = false
                    onConfirmed(account)
                }
                .buttonStyle(.dsPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, DesignSpacing.md)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var isLookingUp: Bool {
        if case .lookingUp = model.state {
            return true
        }
        return false
    }

    private func startLookup() {
        Task {
            await model.lookUp(username)
        }
    }

    private func invalidateCandidateIfNeeded(for value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch model.state {
        case .lookingUp(let query):
            if normalized.caseInsensitiveCompare(query) != .orderedSame {
                model.invalidateCandidate()
            }
        case .candidate(let account), .confirmed(let account):
            if normalized.caseInsensitiveCompare(account.username) != .orderedSame {
                model.invalidateCandidate()
            }
        default:
            break
        }
    }

    private func ratingItems(_ account: ChessComAccount) -> [(String, Int)] {
        [
            account.ratings.rapid.map { ("Rapid", $0) },
            account.ratings.blitz.map { ("Blitz", $0) },
            account.ratings.bullet.map { ("Bullet", $0) },
            account.ratings.daily.map { ("Daily", $0) }
        ].compactMap { $0 }
    }
}
