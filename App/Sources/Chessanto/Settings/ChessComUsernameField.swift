import ChessComKit
import SwiftUI

/// Reusable chess.com username entry + validation, shared between onboarding
/// and the General settings tab so there is one implementation of the
/// "Check" round-trip against `ChessComClient.profile`, not two.
struct ChessComUsernameField: View {
    @Binding var username: String
    /// Called with the validated (non-empty) username once a "Check" round
    /// trip confirms the account exists.
    var onValidated: (String) -> Void

    @State private var isChecking = false
    @State private var validationMessage: String?
    @State private var validationSucceeded = false

    private let client = ChessComClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("chess.com username (optional)", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await check() } }
                Button {
                    Task { await check() }
                } label: {
                    if isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check")
                    }
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(validationSucceeded ? Color.secondary : Color.orange)
            }
        }
    }

    private func check() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isChecking = true
        validationMessage = nil
        defer { isChecking = false }
        do {
            _ = try await client.profile(username: trimmed)
            validationSucceeded = true
            validationMessage = "Found \(trimmed) on chess.com."
            onValidated(trimmed)
        } catch ChessComError.notFound {
            validationSucceeded = false
            validationMessage = "No such account on chess.com."
        } catch {
            validationSucceeded = false
            validationMessage = "Couldn't reach chess.com right now."
        }
    }
}
