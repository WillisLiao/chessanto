import CloudKit
import CompanionCloudKit
import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Persistence

@MainActor
final class MacCompanionManager: ObservableObject {
    @Published private(set) var invitationCode: String?
    @Published private(set) var invitationExpiresAt: Date?
    @Published private(set) var pendingCandidate: PairingCandidate?
    @Published private(set) var verificationPhrase: String?
    @Published private(set) var approvedDevices: [ApprovedCompanionDevice] = []
    @Published private(set) var syncRecovery: CompanionSyncRecovery = .ready
    @Published private(set) var statusMessage = "Starting the companion service..."
    @Published private(set) var isStarted = false
    @Published private(set) var isSendingReport = false
    @Published private(set) var provisioningBlocker: String?

    private let persistentStore = MacCompanionStateStore()
    private let secretStore = MacCompanionSecretStore()
    private let mappingStore = CompanionGameMappingStore()

    private weak var library: GameLibrary?
    private weak var engineService: EngineService?
    private var identity: MacCompanionIdentity?
    private var authority: PairingAuthority?
    private var currentInvitation: PairingInvitation?
    private var persistentState = MacCompanionPersistentState.empty
    private var cloudEngine: CompanionCKSyncEngine?
    private var secureMailbox: SecureCompanionCloudMailbox?
    private var coordinator: RemoteAnalysisCoordinator?
    private var analysisApplication: GameAnalysisApplicationService?

    var activeDevices: [ApprovedCompanionDevice] {
        approvedDevices.filter(\.isActive)
    }

    var canSendReports: Bool {
        isStarted && !activeDevices.isEmpty && secureMailbox != nil
    }

    func start(
        library: GameLibrary,
        engineService: EngineService,
        coachService: CoachService
    ) async {
        guard !isStarted else { return }
        self.library = library
        self.engineService = engineService

        do {
            persistentState = try await persistentStore.load()
            approvedDevices = persistentState.devices

            let backend = MacGameAnalysisBackend(
                store: library.store,
                engine: engineService,
                coach: coachService,
                mappingStore: mappingStore
            )
            let analysisApplication = GameAnalysisApplicationService(
                backing: backend
            )
            self.analysisApplication = analysisApplication
            let coordinator = RemoteAnalysisCoordinator(
                application: analysisApplication
            )
            await coordinator.restoreLedger(persistentState.ledgerEntries)
            self.coordinator = coordinator

            guard
                let containerIdentifier =
                    CompanionCloudKitProvisioning.containerIdentifier()
            else {
                provisioningBlocker =
                    "CloudKit signing is not configured for this build. Add an Apple Developer team and private iCloud container to both targets before physical pairing."
                statusMessage = provisioningBlocker ?? ""
                syncRecovery = .retryLater
                isStarted = true
                return
            }

            let identity = try await secretStore.identity()
            self.identity = identity
            let authority = PairingAuthority(
                endpointID: identity.endpointID,
                signingKey: identity.keys.signing,
                agreementKey: identity.keys.agreement,
                contentKey: identity.contentKey
            )
            self.authority = authority

            let root = companionRoot
            let engine = try await CompanionCKSyncEngine.make(
                database: CKContainer(
                    identifier: containerIdentifier
                ).privateCloudDatabase,
                stateStore: CompanionSyncStateStore(
                    fileURL: root.appendingPathComponent("cloud-state.json")
                ),
                outbox: CompanionCloudOutboxStore(
                    fileURL: root.appendingPathComponent("outbox.json")
                ),
                assetDirectory: root.appendingPathComponent(
                    "Assets",
                    isDirectory: true
                )
            ) { [weak self] record in
                await self?.handle(record)
            }
            cloudEngine = engine
            configureSecureMailbox()
            try await renewInvitation()
            isStarted = true
            statusMessage = activeDevices.isEmpty
                ? "Ready to pair an iPhone."
                : "Connected to \(activeDevices.count) approved iPhone\(activeDevices.count == 1 ? "" : "s")."

            try await synchronize(reason: .launch)
            try await publishEndpoint()
            try await publishCatalog()
        } catch {
            isStarted = identity != nil
            syncRecovery = CompanionCloudErrorMapper.recovery(for: error)
            statusMessage = companionErrorMessage(error)
        }
    }

    func renewInvitation() async throws {
        guard let authority else {
            throw MacCompanionError.notReady
        }
        let invitation = await authority.makeInvitation(now: Date())
        currentInvitation = invitation
        invitationCode = try PairingInvitationQRCodec.encode(invitation)
        invitationExpiresAt = invitation.expiresAt
        pendingCandidate = nil
        verificationPhrase = nil
    }

    func approvePendingCandidate() async {
        guard
            let pendingCandidate,
            let authority,
            let cloudEngine
        else {
            return
        }
        do {
            let approval = try await authority.approve(
                pendingCandidate,
                now: Date()
            )
            let device = ApprovedCompanionDevice(
                id: pendingCandidate.deviceID,
                displayName: pendingCandidate.displayName,
                publicKeys: pendingCandidate.publicKeys,
                approvedAt: Date(),
                revokedAt: nil
            )
            persistentState.devices.removeAll { $0.id == device.id }
            persistentState.devices.append(device)
            try await savePersistentState()
            approvedDevices = persistentState.devices
            configureSecureMailbox()
            guard let identity else {
                throw MacCompanionError.notReady
            }
            try await cloudEngine.enqueue(
                PairingCloudRecordMapper.approval(
                    approval,
                    endpointID: identity.endpointID
                )
            )
            self.pendingCandidate = nil
            verificationPhrase = nil
            statusMessage = "\(device.displayName) is approved."
            try await publishCatalog()
            try await renewInvitation()
        } catch {
            statusMessage = companionErrorMessage(error)
        }
    }

    func rejectPendingCandidate() async {
        if let pendingCandidate {
            try? await cloudEngine?.delete(
                recordName: "pairing-\(pendingCandidate.invitationID)-\(pendingCandidate.deviceID.rawValue)"
            )
        }
        pendingCandidate = nil
        verificationPhrase = nil
        statusMessage = "Pairing request rejected."
    }

    func revokeAllDevices() async {
        guard let authority else { return }
        let now = Date()
        persistentState.devices = persistentState.devices.map { device in
            var copy = device
            if copy.isActive {
                copy.revokedAt = now
            }
            return copy
        }
        await authority.rotateContentKey()
        let rotatedData = await authority.contentKeyData()
        let rotatedKey = SymmetricKey(data: rotatedData)
        do {
            try await secretStore.saveContentKey(rotatedKey)
            if let identity {
                self.identity = MacCompanionIdentity(
                    endpointID: identity.endpointID,
                    deviceID: identity.deviceID,
                    keys: identity.keys,
                    contentKey: rotatedKey
                )
            }
            try await mappingStore.revokeAll()
            try await savePersistentState()
            approvedDevices = persistentState.devices
            secureMailbox = nil
            statusMessage = "All iPhones disconnected. Encryption keys were rotated."
            try await renewInvitation()
        } catch {
            statusMessage = companionErrorMessage(error)
        }
    }

    func synchronize(reason: CompanionSyncReason) async throws {
        guard let cloudEngine else {
            throw MacCompanionError.cloudUnavailable
        }
        do {
            try await cloudEngine.synchronize(reason: reason)
            syncRecovery = .ready
        } catch {
            syncRecovery = CompanionCloudErrorMapper.recovery(for: error)
            throw error
        }
    }

    func publishCatalog() async throws {
        guard
            let library,
            let identity,
            let secureMailbox
        else {
            return
        }
        var games: [CatalogGame] = []
        for record in library.games {
            guard let localID = record.id else { continue }
            let opaqueID = try await mappingStore.assign(localGameID: localID)
            games.append(
                CatalogGame(
                    id: opaqueID,
                    white: record.white,
                    black: record.black,
                    result: record.result ?? "*",
                    playedAt: record.playedAt,
                    isAnalyzed: library.analyzedGameIDs.contains(localID)
                )
            )
        }
        persistentState.catalogVersion += 1
        try await savePersistentState()
        let catalog = GameCatalogSnapshot(
            protocolVersion: .v1,
            endpointID: identity.endpointID,
            version: persistentState.catalogVersion,
            generatedAt: Date(),
            games: games
        )
        for device in activeDevices {
            try await secureMailbox.send(
                .gameCatalog(catalog),
                to: EndpointID(device.id.rawValue)
            )
        }
    }

    func analyzeAndSend(
        game: GameRecord,
        quality: AnalysisQuality
    ) async {
        guard
            let localID = game.id,
            let device = activeDevices.first,
            let identity,
            let coordinator
        else {
            statusMessage = "Pair an iPhone before sending a report."
            return
        }
        isSendingReport = true
        defer { isSendingReport = false }
        do {
            let gameID = try await mappingStore.assign(localGameID: localID)
            let now = Date()
            let request = AnalysisRequest(
                protocolVersion: .v1,
                id: AnalysisRequestID(UUID().uuidString.lowercased()),
                endpointID: identity.endpointID,
                senderDeviceID: device.id,
                gameID: gameID,
                quality: CompanionAnalysisQuality(quality),
                createdAt: now,
                expiresAt: now.addingTimeInterval(24 * 60 * 60)
            )
            try await coordinator.process(
                .analysisRequest(request),
                now: now
            ) { [weak self] message in
                try await self?.deliver(
                    message,
                    to: device.id
                )
            }
            try await publishCatalog()
        } catch {
            statusMessage = companionErrorMessage(error)
        }
    }

    func analyzeLocally(
        game: GameRecord,
        quality: AnalysisQuality,
        reanalyze: Bool
    ) async throws {
        guard
            let localID = game.id,
            let analysisApplication,
            let library
        else {
            throw MacCompanionError.notReady
        }
        if reanalyze {
            try await library.store.deleteAnalysis(gameId: localID)
        }
        let gameID = try await mappingStore.assign(localGameID: localID)
        let request = LocalAnalysisRequestFactory.make(
            gameID: gameID,
            quality: CompanionAnalysisQuality(quality)
        )
        for try await _ in analysisApplication.analyze(request: request) {}
        try? await publishCatalog()
    }

    private func handle(_ record: CompanionCloudRecord) async {
        switch record.type {
        case .pairingCandidate:
            await handlePairingCandidate(record)
        case .analysisRequest, .analysisCancellation:
            await handleSecureCommand(record)
        case .macEndpoint,
             .deviceApproval,
             .gameCatalog,
             .analysisStatus,
             .reportSnapshot:
            break
        }
    }

    private func handlePairingCandidate(
        _ record: CompanionCloudRecord
    ) async {
        do {
            guard
                let identity,
                record.queryableFields["recipient"]
                    == identity.endpointID.rawValue
            else {
                return
            }
            let candidate = try PairingCloudRecordMapper.candidate(from: record)
            guard
                let invitation = currentInvitation,
                candidate.invitationID == invitation.id,
                invitation.expiresAt > Date()
            else {
                return
            }
            pendingCandidate = candidate
            verificationPhrase = PairingVerification.phrase(
                invitation: invitation,
                candidate: candidate
            )
            statusMessage = "Confirm the four words on both devices."
        } catch {
            statusMessage = companionErrorMessage(error)
        }
    }

    private func handleSecureCommand(
        _ record: CompanionCloudRecord
    ) async {
        guard
            let identity,
            let secureMailbox,
            let senderValue = record.queryableFields["sender"]
        else {
            return
        }
        let sender = CompanionDeviceID(senderValue)
        do {
            let message = try await secureMailbox.receive(
                record,
                expectedRecipient: identity.endpointID
            )
            guard command(message, belongsTo: sender) else {
                throw MacCompanionError.senderMismatch
            }
            Task { [weak self] in
                guard let self, let coordinator = self.coordinator else {
                    return
                }
                do {
                    try await coordinator.process(
                        message,
                        now: Date()
                    ) { [weak self] response in
                        try await self?.deliver(response, to: sender)
                    }
                } catch {
                    self.show(error)
                }
            }
        } catch {
            statusMessage = companionErrorMessage(error)
        }
    }

    private func deliver(
        _ message: CompanionMessage,
        to recipient: CompanionDeviceID
    ) async throws {
        guard let secureMailbox else {
            throw MacCompanionError.notReady
        }
        if case .analysisStatus(let snapshot) = message {
            statusMessage = statusText(snapshot)
            if let coordinator {
                persistentState.ledgerEntries =
                    await coordinator.durableLedgerEntries()
                try await savePersistentState()
            }
        }
        if case .report = message {
            statusMessage = "Transferring the completed report to iPhone..."
        }
        try await secureMailbox.send(
            message,
            to: EndpointID(recipient.rawValue)
        )
    }

    private func configureSecureMailbox() {
        guard
            let identity,
            let cloudEngine,
            !activeDevices.isEmpty
        else {
            secureMailbox = nil
            return
        }
        let persistentStore = self.persistentStore
        secureMailbox = SecureCompanionCloudMailbox(
            senderDeviceID: identity.deviceID,
            signingKey: identity.keys.signing,
            contentKey: identity.contentKey,
            transport: cloudEngine
        ) { sender in
            try? await persistentStore.signingKey(for: sender)
        }
    }

    private func publishEndpoint() async throws {
        guard let identity, let cloudEngine else { return }
        try await cloudEngine.enqueue(
            CompanionCloudRecord(
                recordName: "mac-endpoint-\(identity.endpointID.rawValue)",
                type: .macEndpoint,
                queryableFields: [
                    "protocolVersion": "1",
                    "sender": identity.endpointID.rawValue,
                    "recipient": identity.endpointID.rawValue,
                ],
                encryptedFields: [:],
                encryptedAsset: nil
            )
        )
    }

    private func savePersistentState() async throws {
        try await persistentStore.save(persistentState)
    }

    private func command(
        _ message: CompanionMessage,
        belongsTo sender: CompanionDeviceID
    ) -> Bool {
        switch message {
        case .analysisRequest(let request):
            return request.senderDeviceID == sender
        case .analysisCancellation(let cancellation):
            return cancellation.senderDeviceID == sender
        case .gameCatalog, .analysisStatus, .report:
            return false
        }
    }

    private func statusText(_ snapshot: AnalysisJobSnapshot) -> String {
        switch snapshot.state {
        case .accepted:
            return "Request received from iPhone."
        case .waitingForEngine:
            return "Waiting for the local engine..."
        case .analyzing:
            if let progress = snapshot.progress {
                return "Analyzing \(progress.completedPlies) of \(progress.totalPlies) positions..."
            }
            return "Analyzing on this Mac..."
        case .packaging:
            return "Packaging the offline report..."
        case .transferring:
            return "Transferring the report..."
        case .completed:
            return "Report delivered to iPhone."
        case .cancelled:
            return "Analysis cancelled."
        case .failed:
            return "Analysis failed on this Mac."
        case .expired:
            return "The request expired before it could start."
        case .rejected:
            return "The request was rejected."
        case .submitted, .queued:
            return "Request queued."
        }
    }

    private func show(_ error: Error) {
        statusMessage = companionErrorMessage(error)
    }

    private var companionRoot: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Chessanto", isDirectory: true)
        .appendingPathComponent("Companion", isDirectory: true)
    }

    private func companionErrorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
            let description = localized.errorDescription
        {
            return description
        }
        return error.localizedDescription
    }
}

enum MacCompanionError: LocalizedError {
    case notReady
    case cloudUnavailable
    case senderMismatch

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The companion service is still starting."
        case .cloudUnavailable:
            return "iCloud is not ready. Check the Mac's iCloud account and CloudKit configuration."
        case .senderMismatch:
            return "The signed sender did not match the request payload."
        }
    }
}

private extension CompanionAnalysisQuality {
    init(_ quality: AnalysisQuality) {
        switch quality {
        case .fast:
            self = .fast
        case .standard:
            self = .standard
        case .deep:
            self = .deep
        }
    }
}
