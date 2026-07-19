import Foundation
import Testing
@testable import CompanionDomain

@Suite("Analysis request ledger")
struct AnalysisRequestLedgerTests {
    @Test("durable nonterminal entries resume after relaunch")
    func durableEntriesRoundTrip() async throws {
        let request = makeRequest()
        let fingerprint = try CanonicalCoding.encode(request)
        let first = AnalysisRequestLedger()
        _ = await first.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 110)
        )

        let restored = AnalysisRequestLedger()
        await restored.restore(await first.durableEntries())
        let admission = await restored.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 111)
        )

        guard case .resumed(let snapshot) = admission else {
            Issue.record("Expected a restored request to resume")
            return
        }
        #expect(snapshot.state == .accepted)
    }

    @Test("durable terminal entries remain duplicates after relaunch")
    func durableTerminalEntriesRemainDuplicates() async throws {
        let request = makeRequest()
        let fingerprint = try CanonicalCoding.encode(request)
        let first = AnalysisRequestLedger()
        guard case .accepted(let accepted) = await first.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 110)
        ) else {
            Issue.record("Expected the first request to be accepted")
            return
        }
        let completed = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: accepted.requestID,
            state: .completed,
            reception: .accepted,
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 120),
            terminalReason: nil,
            reportID: ReportID("report-1")
        )
        await first.update(completed)

        let restored = AnalysisRequestLedger()
        await restored.restore(await first.durableEntries())
        let admission = await restored.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 121)
        )

        #expect(admission == .duplicate(completed))
    }

    @Test("duplicate delivery returns one stored job")
    func duplicateDeliveryReturnsOneStoredJob() async throws {
        let ledger = AnalysisRequestLedger()
        let request = makeRequest()
        let fingerprint = Data("same-payload".utf8)

        let first = await ledger.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 110)
        )
        let duplicate = await ledger.admit(
            request,
            fingerprint: fingerprint,
            now: Date(timeIntervalSince1970: 111)
        )

        guard case .accepted(let firstSnapshot) = first else {
            Issue.record("First delivery was not accepted")
            return
        }
        guard case .duplicate(let duplicateSnapshot) = duplicate else {
            Issue.record("Second delivery was not recognized as a duplicate")
            return
        }
        #expect(firstSnapshot.requestID == duplicateSnapshot.requestID)
        #expect(await ledger.count == 1)
    }

    @Test("expired request is rejected before it is stored")
    func expiredRequestIsRejectedBeforeItIsStored() async {
        let ledger = AnalysisRequestLedger()

        let admission = await ledger.admit(
            makeRequest(),
            fingerprint: Data("payload".utf8),
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(admission == .rejected(.expired))
        #expect(await ledger.count == 0)
    }

    @Test("same request identifier with different payload is tampering")
    func sameRequestIdentifierWithDifferentPayloadIsTampering() async {
        let ledger = AnalysisRequestLedger()
        let request = makeRequest()
        _ = await ledger.admit(
            request,
            fingerprint: Data("payload-a".utf8),
            now: Date(timeIntervalSince1970: 110)
        )

        let admission = await ledger.admit(
            request,
            fingerprint: Data("payload-b".utf8),
            now: Date(timeIntervalSince1970: 111)
        )

        #expect(admission == .rejected(.tamperedPayload))
        #expect(await ledger.count == 1)
    }

    private func makeRequest() -> AnalysisRequest {
        AnalysisRequest(
            protocolVersion: .v1,
            id: AnalysisRequestID("request-1"),
            endpointID: EndpointID("mac-1"),
            senderDeviceID: CompanionDeviceID("phone-1"),
            gameID: CompanionGameID("game-a"),
            quality: .standard,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
    }
}
