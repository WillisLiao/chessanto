import CloudKit
import Foundation

/// Production private-database adapter.
///
/// The caller supplies `CKContainer.privateCloudDatabase`, so this package
/// never guesses a CloudKit container or developer-team identifier.
public final class CompanionCKSyncEngine: CompanionCloudSyncBoundary, CKSyncEngineDelegate, @unchecked Sendable {
    public static let zoneName = "ChessantoCompanionMailbox"
    public static let subscriptionID = "chessanto-companion-mailbox-v1"

    public typealias RecordHandler = @Sendable (CompanionCloudRecord) async -> Void
    public typealias DeletionHandler = @Sendable (String) async -> Void

    public let zoneID: CKRecordZone.ID

    private let database: CKDatabase
    private let stateStore: CompanionSyncStateStore
    private let outbox: CompanionCloudOutboxStore
    private let assetDirectory: URL
    private let initialSerialization: CKSyncEngine.State.Serialization?
    private let onRecord: RecordHandler
    private let onDeletion: DeletionHandler

    public lazy var engine: CKSyncEngine = {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: initialSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = Self.subscriptionID
        return CKSyncEngine(configuration)
    }()

    private init(
        database: CKDatabase,
        stateStore: CompanionSyncStateStore,
        outbox: CompanionCloudOutboxStore,
        assetDirectory: URL,
        initialSerialization: CKSyncEngine.State.Serialization?,
        onRecord: @escaping RecordHandler,
        onDeletion: @escaping DeletionHandler
    ) {
        self.database = database
        self.stateStore = stateStore
        self.outbox = outbox
        self.assetDirectory = assetDirectory
        self.initialSerialization = initialSerialization
        self.onRecord = onRecord
        self.onDeletion = onDeletion
        self.zoneID = CKRecordZone.ID(
            zoneName: Self.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        _ = engine
    }

    public static func make(
        database: CKDatabase,
        stateStore: CompanionSyncStateStore,
        outbox: CompanionCloudOutboxStore,
        assetDirectory: URL,
        onRecord: @escaping RecordHandler,
        onDeletion: @escaping DeletionHandler = { _ in }
    ) async throws -> CompanionCKSyncEngine {
        let state = try await stateStore.load()
        let serialization = try state.engineState.map {
            try JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self,
                from: $0
            )
        }
        return CompanionCKSyncEngine(
            database: database,
            stateStore: stateStore,
            outbox: outbox,
            assetDirectory: assetDirectory,
            initialSerialization: serialization,
            onRecord: onRecord,
            onDeletion: onDeletion
        )
    }

    public func enqueue(_ record: CompanionCloudRecord) async throws {
        try await outbox.put(record)
        ensureZoneIsPending()
        let recordID = CKRecord.ID(
            recordName: record.recordName,
            zoneID: zoneID
        )
        engine.state.add(
            pendingRecordZoneChanges: [.saveRecord(recordID)]
        )
        try await engine.sendChanges()
    }

    public func delete(recordName: String) async throws {
        let recordID = CKRecord.ID(
            recordName: recordName,
            zoneID: zoneID
        )
        engine.state.add(
            pendingRecordZoneChanges: [.deleteRecord(recordID)]
        )
        try await engine.sendChanges(
            .init(scope: .recordIDs([recordID]))
        )
    }

    public func synchronize(reason: CompanionSyncReason) async throws {
        ensureZoneIsPending()
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            try await saveRecovery(.ready, successfulAt: Date())
        } catch {
            try await saveRecovery(
                CompanionCloudErrorMapper.recovery(for: error),
                successfulAt: nil
            )
            throw error
        }
    }

    public func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        switch event {
        case .stateUpdate(let update):
            await persist(update.stateSerialization)
        case .accountChange(let accountChange):
            await handle(accountChange)
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == zoneID {
                let recovery: CompanionSyncRecovery =
                    deletion.reason == .encryptedDataReset
                    ? .encryptionKeyResetRequired
                    : .zoneResetRequired
                try? await saveRecovery(recovery, successfulAt: nil)
            }
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                if let value = try? CompanionCKRecordCodec.value(
                    from: modification.record
                ) {
                    await onRecord(value)
                }
            }
            for deletion in changes.deletions {
                await onDeletion(deletion.recordID.recordName)
            }
        case .sentRecordZoneChanges(let changes):
            for record in changes.savedRecords {
                try? await outbox.remove(named: record.recordID.recordName)
            }
            for failure in changes.failedRecordSaves {
                try? await saveRecovery(
                    CompanionCloudErrorMapper.recovery(for: failure.error),
                    successfulAt: nil
                )
            }
            for error in changes.failedRecordDeletes.values {
                try? await saveRecovery(
                    CompanionCloudErrorMapper.recovery(for: error),
                    successfulAt: nil
                )
            }
        case .sentDatabaseChanges(let changes):
            for failure in changes.failedZoneSaves {
                try? await saveRecovery(
                    CompanionCloudErrorMapper.recovery(for: failure.error),
                    successfulAt: nil
                )
            }
            for error in changes.failedZoneDeletes.values {
                try? await saveRecovery(
                    CompanionCloudErrorMapper.recovery(for: error),
                    successfulAt: nil
                )
            }
        case .didFetchRecordZoneChanges(let result):
            if let error = result.error {
                try? await saveRecovery(
                    CompanionCloudErrorMapper.recovery(for: error),
                    successfulAt: nil
                )
            }
        case .willFetchChanges,
             .willFetchRecordZoneChanges,
             .didFetchChanges,
             .willSendChanges,
             .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: pending
        ) { [outbox, assetDirectory, zoneID] recordID in
            guard
                recordID.zoneID == zoneID,
                let value = try? await outbox.record(named: recordID.recordName)
            else {
                return nil
            }
            return try? CompanionCKRecordCodec.record(
                from: value,
                zoneID: zoneID,
                assetDirectory: assetDirectory
            )
        }
    }

    private func ensureZoneIsPending() {
        let hasZoneChange = engine.state.pendingDatabaseChanges.contains {
            switch $0 {
            case .saveZone(let zone):
                return zone.zoneID == zoneID
            case .deleteZone:
                return false
            @unknown default:
                return false
            }
        }
        guard !hasZoneChange else { return }
        engine.state.add(
            pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID))
            ]
        )
    }

    private func persist(
        _ serialization: CKSyncEngine.State.Serialization
    ) async {
        guard let encoded = try? JSONEncoder().encode(serialization) else {
            return
        }
        let current = (try? await stateStore.load()) ?? .initial
        try? await stateStore.save(
            CompanionSyncState(
                engineState: encoded,
                accountIdentifier: current.accountIdentifier,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                recovery: current.recovery
            )
        )
    }

    private func handle(
        _ accountChange: CKSyncEngine.Event.AccountChange
    ) async {
        let accountIdentifier: String?
        let recovery: CompanionSyncRecovery
        switch accountChange.changeType {
        case .signIn(let currentUser):
            accountIdentifier = currentUser.recordName
            recovery = .ready
        case .signOut:
            accountIdentifier = nil
            recovery = .iCloudAccountRequired
        case .switchAccounts(_, let currentUser):
            accountIdentifier = currentUser.recordName
            recovery = .accountChanged
            try? await outbox.removeAll()
        @unknown default:
            accountIdentifier = nil
            recovery = .accountChanged
        }
        let current = (try? await stateStore.load()) ?? .initial
        try? await stateStore.save(
            CompanionSyncState(
                engineState: current.engineState,
                accountIdentifier: accountIdentifier,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                recovery: recovery
            )
        )
    }

    private func saveRecovery(
        _ recovery: CompanionSyncRecovery,
        successfulAt: Date?
    ) async throws {
        let current = try await stateStore.load()
        try await stateStore.save(
            CompanionSyncState(
                engineState: current.engineState,
                accountIdentifier: current.accountIdentifier,
                lastSuccessfulSyncAt:
                    successfulAt ?? current.lastSuccessfulSyncAt,
                recovery: recovery
            )
        )
    }
}
