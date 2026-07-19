import CloudKit
import Foundation
import Testing
@testable import CompanionCloudKit

@Suite("Companion sync state and recovery")
struct CompanionSyncStateTests {
    @Test("sync state survives relaunch")
    func syncStateSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sync-state.json")
        let first = CompanionSyncStateStore(fileURL: url)
        let state = CompanionSyncState(
            engineState: Data([4, 5, 6]),
            accountIdentifier: "account-a",
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 100),
            recovery: .ready
        )

        try await first.save(state)
        let reopened = CompanionSyncStateStore(fileURL: url)

        #expect(try await reopened.load() == state)
    }

    @Test(
        "CloudKit errors map to honest recovery states",
        arguments: [
            (CKError(.notAuthenticated), CompanionSyncRecovery.iCloudAccountRequired),
            (CKError(.quotaExceeded), CompanionSyncRecovery.storageFull),
            (CKError(.zoneNotFound), CompanionSyncRecovery.zoneResetRequired),
            (CKError(.changeTokenExpired), CompanionSyncRecovery.zoneResetRequired),
            (CKError(.networkFailure), CompanionSyncRecovery.retryWhenOnline),
            (CKError(.networkUnavailable), CompanionSyncRecovery.retryWhenOnline),
        ]
    )
    func cloudKitErrorsMapToRecovery(
        error: CKError,
        expected: CompanionSyncRecovery
    ) {
        #expect(CompanionCloudErrorMapper.recovery(for: error) == expected)
    }

    @Test("explicit lifecycle sync reasons reach the mocked CloudKit boundary")
    func lifecycleSyncReasonsReachBoundary() async throws {
        let boundary = MockCloudSyncBoundary()
        let controller = CompanionSyncController(boundary: boundary)

        try await controller.synchronize(reason: .launch)
        try await controller.synchronize(reason: .foreground)
        try await controller.synchronize(reason: .pullToRefresh)
        try await controller.synchronize(reason: .lifecycleChange)
        try await controller.synchronize(reason: .advisoryPush)

        #expect(
            await boundary.reasons == [
                .launch,
                .foreground,
                .pullToRefresh,
                .lifecycleChange,
                .advisoryPush,
            ]
        )
    }
}

private actor MockCloudSyncBoundary: CompanionCloudSyncBoundary {
    private(set) var reasons: [CompanionSyncReason] = []

    func synchronize(reason: CompanionSyncReason) async throws {
        reasons.append(reason)
    }
}
