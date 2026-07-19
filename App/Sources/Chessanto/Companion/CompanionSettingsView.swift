import AppKit
import CompanionCloudKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct CompanionSettingsView: View {
    @EnvironmentObject private var companion: MacCompanionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                pairingSection
                approvedDevicesSection
                syncSection
                privacySection
            }
            .padding(DesignSpacing.xl)
        }
        .frame(width: 610, height: 650)
        .background(DesignColors.surface0)
    }

    private var pairingSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                Label("Pair an iPhone", systemImage: "iphone.and.arrow.forward")
                    .font(.dsTitle)
                    .foregroundStyle(DesignColors.textPrimary)
                Text(
                    "On your iPhone, open the Mac tab and scan this five-minute code. Pairing is not complete until you approve the matching four-word phrase here."
                )
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)

                if let blocker = companion.provisioningBlocker {
                    Label(
                        blocker,
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                    .padding(DesignSpacing.md)
                    .background(DesignColors.selection)
                } else if let phrase = companion.verificationPhrase,
                    let candidate = companion.pendingCandidate
                {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        Label(
                            "\(candidate.displayName) wants to pair",
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .font(.dsSectionHeader)
                        Text("Confirm that both devices show:")
                            .font(.dsSecondary)
                            .foregroundStyle(DesignColors.textSecondary)
                        Text(phrase)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityLabel(
                                "Verification phrase: \(phrase)"
                            )
                        HStack {
                            Button("Approve iPhone") {
                                Task {
                                    await companion.approvePendingCandidate()
                                }
                            }
                            .buttonStyle(.dsPrimary)
                            Button("Reject") {
                                Task {
                                    await companion.rejectPendingCandidate()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(DesignSpacing.md)
                    .background(DesignColors.selection)
                } else if let code = companion.invitationCode {
                    HStack(alignment: .center, spacing: DesignSpacing.lg) {
                        if let image = PairingQRCode.image(for: code) {
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 190, height: 190)
                                .padding(10)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(
                                    "Chessanto iPhone pairing QR code"
                                )
                        }
                        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                            Label(
                                "Approval required",
                                systemImage: "lock.shield.fill"
                            )
                            .font(.dsSectionHeader)
                            Text(expirationText)
                                .font(.dsSecondary)
                                .foregroundStyle(DesignColors.textSecondary)
                            Button("New pairing code") {
                                Task {
                                    try? await companion.renewInvitation()
                                }
                            }
                            .buttonStyle(.bordered)
                            DisclosureGroup("Enter code manually") {
                                Text(code)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                            }
                            .font(.dsSecondary)
                        }
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Preparing a secure pairing code...")
                    }
                    .font(.dsBody)
                }
            }
        }
    }

    private var approvedDevicesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Label("Approved iPhones", systemImage: "checkmark.shield")
                    .font(.dsSectionHeader)
                if companion.activeDevices.isEmpty {
                    Text("No iPhone can request analysis or receive new reports.")
                        .font(.dsBody)
                        .foregroundStyle(DesignColors.textSecondary)
                } else {
                    ForEach(companion.activeDevices) { device in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(DesignColors.accentText)
                            VStack(alignment: .leading) {
                                Text(device.displayName)
                                    .font(.dsBody.weight(.semibold))
                                Text(
                                    "Approved \(device.approvedAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                                .font(.dsSecondary)
                                .foregroundStyle(DesignColors.textSecondary)
                            }
                            Spacer()
                            Label("Encrypted", systemImage: "lock.fill")
                                .font(.dsSecondary)
                                .foregroundStyle(DesignColors.accentText)
                        }
                    }
                    Button("Disconnect all iPhones", role: .destructive) {
                        Task { await companion.revokeAllDevices() }
                    }
                    Text(
                        "Disconnecting rotates the encryption key and blocks future commands. Reports already downloaded to an iPhone remain available there."
                    )
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                }
            }
        }
    }

    private var syncSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                HStack {
                    Label("Companion mailbox", systemImage: syncIcon)
                        .font(.dsSectionHeader)
                    Spacer()
                    Text(syncTitle)
                        .font(.dsSecondary.weight(.semibold))
                        .foregroundStyle(DesignColors.accentText)
                }
                Text(companion.statusMessage)
                    .font(.dsBody)
                    .foregroundStyle(DesignColors.textSecondary)
                Text(syncExplanation)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                HStack {
                    Button("Check now") {
                        Task {
                            try? await companion.synchronize(
                                reason: .pullToRefresh
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Refresh game list") {
                        Task { try? await companion.publishCatalog() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(companion.activeDevices.isEmpty)
                }
            }
        }
    }

    private var privacySection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Label("Private by design", systemImage: "hand.raised.fill")
                    .font(.dsSectionHeader)
                Text(
                    "The iPhone sends a signed, encrypted request. Stockfish and the Coach run on this Mac while Chessanto is open. Chessanto encrypts catalogs, requests, progress, reports, and Coach text before CloudKit upload."
                )
                .font(.dsBody)
                Text(
                    "CloudKit can still observe record type, size, timing, and account-level metadata. The iPhone stores completed reports in its own encrypted offline archive."
                )
                .font(.dsSecondary)
                .foregroundStyle(DesignColors.textSecondary)
            }
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            content()
        }
    }

    private var expirationText: String {
        guard let date = companion.invitationExpiresAt else {
            return "This code expires shortly."
        }
        return "Expires \(date.formatted(date: .omitted, time: .shortened))."
    }

    private var syncTitle: String {
        switch companion.syncRecovery {
        case .ready: return "Ready"
        case .iCloudAccountRequired: return "Sign in to iCloud"
        case .accountChanged: return "Account changed"
        case .storageFull: return "Storage full"
        case .zoneResetRequired: return "Mailbox reset"
        case .encryptionKeyResetRequired: return "Pair again"
        case .retryWhenOnline: return "Offline"
        case .retryLater: return "Try again later"
        }
    }

    private var syncExplanation: String {
        switch companion.syncRecovery {
        case .ready:
            return "Requests are accepted only from an approved signing key."
        case .iCloudAccountRequired:
            return "Sign in to iCloud on both devices, then check again."
        case .accountChanged:
            return "The iCloud account changed. Disconnect devices and pair again."
        case .storageFull:
            return "Free iCloud storage before transferring another report."
        case .zoneResetRequired:
            return "The private mailbox was deleted or reset. Pair again to rebuild it."
        case .encryptionKeyResetRequired:
            return "CloudKit encryption data changed. Pair again with fresh keys."
        case .retryWhenOnline:
            return "Chessanto will retry when the network returns."
        case .retryLater:
            return "CloudKit is temporarily unavailable. Local analysis still works."
        }
    }

    private var syncIcon: String {
        companion.syncRecovery == .ready ? "icloud.fill" : "icloud.slash"
    }
}

private enum PairingQRCode {
    static func image(for value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: 8, y: 8)
        )
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
