import CompanionDomain
import CompanionSecurity
import Foundation
import Testing
@testable import CompanionCloudKit

@Suite("Companion CloudKit record mapper")
struct CompanionCloudRecordMapperTests {
    @Test("record types match the approved immutable mailbox model")
    func recordTypesMatchApprovedModel() {
        #expect(
            Set(CompanionCloudRecordType.allCases.map(\.rawValue)) == [
                "MacEndpoint",
                "PairingCandidate",
                "DeviceApproval",
                "GameCatalog",
                "AnalysisRequest",
                "AnalysisCancellation",
                "AnalysisStatus",
                "ReportSnapshot",
            ]
        )
    }

    @Test("small envelope keeps only routing metadata queryable")
    func smallEnvelopeKeepsOnlyRoutingMetadataQueryable() throws {
        let envelope = makeEnvelope(payload: Data("secret-report".utf8))

        let record = try CompanionCloudRecordMapper.map(
            envelope,
            type: .analysisRequest,
            assetThreshold: 1_000
        )

        #expect(record.recordName == "record-1")
        #expect(record.queryableFields.keys.sorted() == [
            "messageID",
            "protocolVersion",
            "recipient",
            "sender",
        ])
        #expect(record.encryptedFields["envelope"] != nil)
        #expect(record.encryptedAsset == nil)
        #expect(record.queryableFields.values.contains("secret-report") == false)
        #expect(try CompanionCloudRecordMapper.envelope(from: record) == envelope)
    }

    @Test("large encrypted envelope spills into an encrypted asset")
    func largeEnvelopeSpillsIntoAsset() throws {
        let envelope = makeEnvelope(payload: Data(repeating: 0xA5, count: 500))

        let record = try CompanionCloudRecordMapper.map(
            envelope,
            type: .reportSnapshot,
            assetThreshold: 32
        )

        #expect(record.encryptedFields["envelope"] == nil)
        #expect(record.encryptedAsset != nil)
        #expect(try CompanionCloudRecordMapper.envelope(from: record) == envelope)
    }

    private func makeEnvelope(payload: Data) -> AuthenticatedEnvelope {
        AuthenticatedEnvelope(
            header: AuthenticatedEnvelopeHeader(
                recordID: "record-1",
                protocolVersion: .v1,
                messageID: "message-1",
                sender: CompanionDeviceID("phone-1"),
                recipient: EndpointID("mac-1")
            ),
            sealedPayload: payload,
            signature: Data([1, 2, 3])
        )
    }
}
