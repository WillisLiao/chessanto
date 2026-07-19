import CompanionDomain
import Foundation
import Testing
@testable import ChessantoMobile

@Suite("Phone companion state")
struct PhoneCompanionStateStoreTests {
    @Test("catalog and in-flight jobs survive app relaunch")
    func stateRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhoneCompanionStateStore(
            fileURL: root.appendingPathComponent("state.json")
        )
        let requestID = AnalysisRequestID("request-1")
        let state = PhoneCompanionState(
            catalog: GameCatalogSnapshot(
                protocolVersion: .v1,
                endpointID: EndpointID("mac-1"),
                version: 3,
                generatedAt: Date(timeIntervalSince1970: 1_000),
                games: []
            ),
            jobs: [
                AnalysisJobSnapshot(
                    protocolVersion: .v1,
                    requestID: requestID,
                    state: .analyzing,
                    reception: .accepted,
                    progress: AnalysisProgress(
                        completedPlies: 4,
                        totalPlies: 20
                    ),
                    updatedAt: Date(timeIntervalSince1970: 1_010),
                    terminalReason: nil,
                    reportID: nil
                )
            ]
        )

        try await store.save(state)

        #expect(try await store.load() == state)
    }
}
