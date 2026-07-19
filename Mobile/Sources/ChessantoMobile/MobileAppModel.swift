import CloudKit
import CompanionCloudKit
import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Network
import SwiftUI
import UIKit

enum PhonePairingStage: Equatable {
    case unpaired
    case submitting
    case awaitingApproval(phrase: String)
    case paired(macName: String)
    case failed(message: String)
}

@MainActor
final class MobileAppModel: ObservableObject {
    @Published private(set) var reports: [PortableAnalysisReport] = []
    @Published private(set) var catalog: GameCatalogSnapshot?
    @Published private(set) var jobs: [AnalysisJobSnapshot] = []
    @Published private(set) var pairingStage: PhonePairingStage = .unpaired
    @Published private(set) var syncRecovery: CompanionSyncRecovery = .ready
    @Published private(set) var isOnline = true
    @Published var notationStyle: MobileNotationStyle = .standard
    @Published private(set) var provisioningBlocker: String?

    private let cache = OfflineReportCache()
    private let pairingStore = PhonePairingStore()
    private let stateStore = PhoneCompanionStateStore()
    private var cloudEngine: CompanionCKSyncEngine?
    private var secureMailbox: SecureCompanionCloudMailbox?
    private var identity: PhoneIdentity?
    private var pairing: StoredPhonePairing?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(
        label: "com.chessanto.companion.network"
    )

    func start() async {
        reports = (try? await cache.reports()) ?? []
        let durableState = (try? await stateStore.load()) ?? .empty
        catalog = durableState.catalog
        jobs = durableState.jobs
        identity = try? await pairingStore.identity()
        pairing = try? await pairingStore.pairing()
        if pairing != nil {
            pairingStage = .paired(macName: "Your Mac")
        }
        startNetworkMonitor()

        do {
            guard
                let containerIdentifier =
                    CompanionCloudKitProvisioning.containerIdentifier()
            else {
                provisioningBlocker =
                    "This build is not signed for Chessanto's private CloudKit container."
                syncRecovery = .retryLater
                return
            }
            let root = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("CloudSync", isDirectory: true)
            let stateStore = CompanionSyncStateStore(
                fileURL: root.appendingPathComponent("state.json")
            )
            let outbox = CompanionCloudOutboxStore(
                fileURL: root.appendingPathComponent("outbox.json")
            )
            let engine = try await CompanionCKSyncEngine.make(
                database: CKContainer(
                    identifier: containerIdentifier
                ).privateCloudDatabase,
                stateStore: stateStore,
                outbox: outbox,
                assetDirectory: root.appendingPathComponent(
                    "Assets",
                    isDirectory: true
                )
            ) { [weak self] record in
                await self?.handle(record)
            }
            cloudEngine = engine
            configureSecureMailboxIfPaired()
            try await synchronize(reason: .launch)
        } catch {
            syncRecovery = CompanionCloudErrorMapper.recovery(for: error)
        }
    }

    func synchronize(reason: CompanionSyncReason) async throws {
        guard let cloudEngine else { return }
        do {
            try await cloudEngine.synchronize(reason: reason)
            syncRecovery = .ready
        } catch {
            syncRecovery = CompanionCloudErrorMapper.recovery(for: error)
            throw error
        }
    }

    func submitPairingCode(_ code: String) async {
        pairingStage = .submitting
        do {
            guard let cloudEngine else {
                throw MobileCompanionError.cloudUnavailable
            }
            let invitation = try PairingInvitationQRCodec.decode(code)
            try PairingInvitationVerification.verify(
                invitation,
                now: Date()
            )
            let identity = try await pairingStore.identity()
            let candidate = try PairingCandidate.make(
                invitation: invitation,
                deviceID: identity.deviceID,
                displayName: UIDevice.current.name,
                keys: identity.keys,
                createdAt: Date()
            )
            try await pairingStore.saveInvitation(invitation)
            try await cloudEngine.enqueue(
                PairingCloudRecordMapper.candidate(
                    candidate,
                    endpointID: invitation.endpointID
                )
            )
            self.identity = identity
            pairingStage = .awaitingApproval(
                phrase: PairingVerification.phrase(
                    invitation: invitation,
                    candidate: candidate
                )
            )
        } catch {
            pairingStage = .failed(message: error.localizedDescription)
        }
    }

    func requestAnalysis(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality
    ) async {
        guard
            let secureMailbox,
            let identity,
            let pairing
        else {
            pairingStage = .failed(
                message: "Pair with your Mac before requesting analysis."
            )
            return
        }
        let now = Date()
        let request = AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID(UUID().uuidString.lowercased()),
            endpointID: pairing.invitation.endpointID,
            senderDeviceID: identity.deviceID,
            gameID: gameID,
            quality: quality,
            createdAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )
        do {
            try await secureMailbox.send(
                .analysisRequest(request),
                to: pairing.invitation.endpointID
            )
            jobs.insert(
                AnalysisJobSnapshot(
                    protocolVersion: .v1,
                    requestID: request.id,
                    state: .submitted,
                    reception: .submitted,
                    progress: nil,
                    updatedAt: now,
                    terminalReason: nil,
                    reportID: nil
                ),
                at: 0
            )
            await persistConnectionState()
        } catch {
            syncRecovery = CompanionCloudErrorMapper.recovery(for: error)
        }
    }

    func cancel(_ job: AnalysisJobSnapshot) async {
        guard
            let secureMailbox,
            let identity,
            let pairing,
            !job.state.isTerminal
        else {
            return
        }
        let cancellation = AnalysisCancellation(
            protocolVersion: .v1,
            id: UUID().uuidString.lowercased(),
            requestID: job.requestID,
            senderDeviceID: identity.deviceID,
            endpointID: pairing.invitation.endpointID,
            createdAt: Date()
        )
        try? await secureMailbox.send(
            .analysisCancellation(cancellation),
            to: pairing.invitation.endpointID
        )
    }

    func deleteReport(_ report: PortableAnalysisReport) async {
        try? await cache.delete(id: report.id)
        reports = (try? await cache.reports()) ?? []
    }

    func revokeLocalPairing() async {
        try? await pairingStore.resetPairing()
        try? await stateStore.resetConnectionState()
        pairing = nil
        secureMailbox = nil
        catalog = nil
        jobs = []
        pairingStage = .unpaired
    }

    private func handle(_ record: CompanionCloudRecord) async {
        if record.type == .deviceApproval {
            await handleApproval(record)
            return
        }
        guard let secureMailbox, let identity else { return }
        do {
            let message = try await secureMailbox.receive(
                record,
                expectedRecipient: EndpointID(identity.deviceID.rawValue)
            )
            switch message {
            case .gameCatalog(let snapshot):
                catalog = snapshot
                await persistConnectionState()
            case .analysisStatus(let snapshot):
                jobs.removeAll { $0.requestID == snapshot.requestID }
                jobs.insert(snapshot, at: 0)
                await persistConnectionState()
            case .report(let report):
                try await cache.save(report)
                reports = try await cache.reports()
            case .analysisRequest, .analysisCancellation:
                break
            }
        } catch {
            if error as? SecureCompanionCloudMailboxError
                == .unapprovedOrRevokedSender
            {
                syncRecovery = .encryptionKeyResetRequired
            }
        }
    }

    private func handleApproval(_ record: CompanionCloudRecord) async {
        do {
            guard let invitation = try await pairingStore.invitation() else {
                return
            }
            let resolvedIdentity: PhoneIdentity
            if let identity {
                resolvedIdentity = identity
            } else {
                resolvedIdentity = try await pairingStore.identity()
            }
            let approval = try PairingCloudRecordMapper.approval(from: record)
            guard
                approval.deviceID == resolvedIdentity.deviceID,
                approval.invitationID == invitation.id
            else {
                return
            }
            let contentKey = try ContentKeyWrapping.unwrap(
                approval,
                invitationSecret: invitation.oneTimeSecret,
                phoneAgreementKey: resolvedIdentity.keys.agreement
            )
            try await pairingStore.complete(
                approval: approval,
                contentKey: contentKey
            )
            pairing = StoredPhonePairing(
                invitation: invitation,
                approval: approval,
                contentKey: contentKey
            )
            self.identity = resolvedIdentity
            configureSecureMailboxIfPaired()
            pairingStage = .paired(macName: "Your Mac")
        } catch {
            pairingStage = .failed(message: error.localizedDescription)
        }
    }

    private func configureSecureMailboxIfPaired() {
        guard
            let cloudEngine,
            let identity,
            let pairing
        else {
            return
        }
        let macSigningKeyData = pairing.invitation.macPublicKeys.signing
        secureMailbox = SecureCompanionCloudMailbox(
            senderDeviceID: identity.deviceID,
            signingKey: identity.keys.signing,
            contentKey: pairing.contentKey,
            transport: cloudEngine
        ) { sender in
            guard sender.rawValue == pairing.invitation.endpointID.rawValue else {
                return nil
            }
            return try? Curve25519.Signing.PublicKey(
                rawRepresentation: macSigningKeyData
            )
        }
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func persistConnectionState() async {
        try? await stateStore.save(
            PhoneCompanionState(catalog: catalog, jobs: jobs)
        )
    }
}

enum MobileCompanionError: LocalizedError {
    case cloudUnavailable

    var errorDescription: String? {
        "iCloud is not ready yet. Check your iCloud account and try again."
    }
}

enum MobileNotationStyle: String, CaseIterable, Identifiable {
    case standard
    case pieceNames

    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: "Standard notation"
        case .pieceNames: "Full piece names"
        }
    }
}
