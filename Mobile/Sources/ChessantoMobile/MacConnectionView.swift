import CompanionCloudKit
import SwiftUI

struct MacConnectionView: View {
    @EnvironmentObject private var model: MobileAppModel
    @State private var showsScanner = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionCard
                syncCard
                privacyCard
                notationCard
            }
            .padding(16)
        }
        .navigationTitle("Mac")
        .companionBackground()
        .sheet(isPresented: $showsScanner) {
            PairingScannerSheet()
        }
    }

    @ViewBuilder
    private var connectionCard: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Secure Mac pairing", systemImage: "lock.shield.fill")
                    .font(.headline)
                switch model.pairingStage {
                case .unpaired:
                    Text(
                        "Open Chessanto on your Mac, choose Companion, then scan its five-minute pairing code."
                    )
                    .foregroundStyle(MobileColors.graphiteSoft)
                    Button {
                        showsScanner = true
                    } label: {
                        Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                case .submitting:
                    HStack {
                        ProgressView()
                        Text("Sending secure pairing request")
                    }
                    .frame(minHeight: 44)
                case .awaitingApproval(let phrase):
                    StatusPill(text: "Waiting for Mac approval")
                    Text("Confirm that both devices show:")
                        .foregroundStyle(MobileColors.graphiteSoft)
                    Text(phrase)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityLabel("Verification phrase: \(phrase)")
                    Text(
                        "Leave Chessanto open on the Mac and approve this iPhone there."
                    )
                    .font(.footnote)
                    .foregroundStyle(MobileColors.graphiteSoft)
                case .paired(let macName):
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(macName)
                                .font(.headline)
                            Label(
                                "Paired with end-to-end encryption",
                                systemImage: "checkmark.shield.fill"
                            )
                            .font(.subheadline)
                            .foregroundStyle(MobileColors.success)
                        }
                        Spacer()
                        Image(systemName: "laptopcomputer")
                            .font(.title)
                            .foregroundStyle(MobileColors.brass)
                    }
                    Button("Remove pairing", role: .destructive) {
                        Task { await model.revokeLocalPairing() }
                    }
                    .frame(minHeight: 44)
                    Text(
                        "Removing pairing blocks future transfers. It does not erase reports already saved on this iPhone."
                    )
                    .font(.footnote)
                    .foregroundStyle(MobileColors.graphiteSoft)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MobileColors.danger)
                    Button("Try scanning again") {
                        showsScanner = true
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private var syncCard: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Companion sync", systemImage: syncIcon)
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        text: syncTitle,
                        color: syncColor
                    )
                }
                Text(syncExplanation)
                    .font(.subheadline)
                    .foregroundStyle(MobileColors.graphiteSoft)
                Button {
                    Task {
                        try? await model.synchronize(reason: .pullToRefresh)
                    }
                } label: {
                    Label("Check now", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
                .disabled(!model.isOnline)
            }
        }
    }

    private var privacyCard: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Privacy", systemImage: "hand.raised.fill")
                    .font(.headline)
                Text(
                    "Chessanto encrypts game catalogs, requests, reports, and Coach text before upload. CloudKit can still observe record type, size, timing, and account-level metadata."
                )
                .font(.subheadline)
                .foregroundStyle(MobileColors.graphiteSoft)
            }
        }
    }

    private var notationCard: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Move notation", systemImage: "textformat")
                    .font(.headline)
                Picker("Move notation", selection: $model.notationStyle) {
                    ForEach(MobileNotationStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(
                    model.notationStyle == .standard
                        ? "Example: Nf3"
                        : "Example: Knight f3"
                )
                .font(.footnote)
                .foregroundStyle(MobileColors.graphiteSoft)
            }
        }
    }

    private var syncTitle: String {
        guard model.isOnline else { return "Offline" }
        switch model.syncRecovery {
        case .ready: return "Ready"
        case .iCloudAccountRequired: return "iCloud sign-in needed"
        case .accountChanged: return "Account changed"
        case .storageFull: return "iCloud storage full"
        case .zoneResetRequired: return "Mailbox needs repair"
        case .encryptionKeyResetRequired: return "Pair again"
        case .retryWhenOnline: return "Waiting for network"
        case .retryLater: return "Temporarily unavailable"
        }
    }

    private var syncExplanation: String {
        if let blocker = model.provisioningBlocker {
            return blocker
                + " Add the Apple Developer team and iCloud container to the iPhone and Mac targets, then rebuild."
        }
        guard model.isOnline else {
            return "Saved reports remain available. New requests will wait until this iPhone reconnects."
        }
        switch model.syncRecovery {
        case .ready:
            return "CloudKit carries encrypted messages between this iPhone and your Mac."
        case .iCloudAccountRequired:
            return "Sign in to iCloud in Settings, then return and check again."
        case .accountChanged:
            return "The iCloud account changed. Pair this iPhone with the Mac again."
        case .storageFull:
            return "Free iCloud storage before sending or receiving another report."
        case .zoneResetRequired:
            return "The private companion mailbox was deleted or reset. Pair again to rebuild it."
        case .encryptionKeyResetRequired:
            return "Encrypted CloudKit data was reset. Pair again to establish fresh keys."
        case .retryWhenOnline:
            return "Chessanto will retry when the network is available."
        case .retryLater:
            return "CloudKit is temporarily unavailable. Your offline reports are safe."
        }
    }

    private var syncIcon: String {
        model.isOnline ? "icloud.fill" : "icloud.slash.fill"
    }

    private var syncColor: Color {
        model.syncRecovery == .ready && model.isOnline
            ? MobileColors.success
            : MobileColors.brass
    }
}

private struct PairingScannerSheet: View {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var didScan = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                QRCodeCameraView { code in
                    guard !didScan else { return }
                    didScan = true
                    dismiss()
                    Task { await model.submitPairingCode(code) }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(MobileColors.brass, lineWidth: 3)
                        .padding(28)
                }
                .accessibilityLabel("Pairing QR code scanner")

                Text("Point this iPhone at the pairing code on your Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MobileColors.graphiteSoft)

                DisclosureGroup("Enter code manually") {
                    TextEditor(text: $manualCode)
                        .frame(minHeight: 88)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(MobileColors.hairline)
                        }
                    Button("Submit code") {
                        dismiss()
                        Task { await model.submitPairingCode(manualCode) }
                    }
                    .disabled(manualCode.isEmpty)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(20)
            .navigationTitle("Pair with Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .companionBackground()
        }
    }
}
