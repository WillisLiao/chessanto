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

    @Test("missing envelope data throws missingEnvelope error")
    func missingEnvelopeThrowsError() {
        let emptyRecord = CompanionCloudRecord(
            recordName: "record-1",
            type: .analysisRequest,
            queryableFields: [:],
            encryptedFields: [:],
            encryptedAsset: nil
        )
        #expect(throws: CompanionCloudRecordError.missingEnvelope) {
            try CompanionCloudRecordMapper.envelope(from: emptyRecord)
        }
    }

    @Test("pairing candidate and approval records map cleanly and reject missing payloads")
    func pairingCandidateAndApprovalRecordsMapCleanly() throws {
        let candidate = PairingCandidate(
            invitationID: "inv-1",
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            publicKeys: DevicePublicKeys(signing: Data([1, 2]), agreement: Data([3, 4])),
            createdAt: Date(timeIntervalSince1970: 100),
            invitationProof: Data(repeating: 0x55, count: 32)
        )
        let candidateRecord = try PairingCloudRecordMapper.candidate(
            candidate,
            endpointID: EndpointID("mac-1")
        )
        #expect(candidateRecord.recordName == "pairing-inv-1-phone-1")
        #expect(try PairingCloudRecordMapper.candidate(from: candidateRecord) == candidate)

        let emptyCandidateRecord = CompanionCloudRecord(
            recordName: "pairing-inv-1-phone-1",
            type: .pairingCandidate,
            queryableFields: [:],
            encryptedFields: [:],
            encryptedAsset: nil
        )
        #expect(throws: PairingCloudRecordMapperError.missingPayload) {
            try PairingCloudRecordMapper.candidate(from: emptyCandidateRecord)
        }

        let approval = DeviceApproval(
            invitationID: "inv-1",
            deviceID: CompanionDeviceID("phone-1"),
            verificationPhrase: "amber bishop cedar delta",
            wrappedContentKey: Data(repeating: 0x77, count: 48),
            macAgreementPublicKey: Data(repeating: 0x88, count: 32)
        )
        let approvalRecord = try PairingCloudRecordMapper.approval(
            approval,
            endpointID: EndpointID("mac-1")
        )
        #expect(approvalRecord.recordName == "approval-inv-1-phone-1")
        #expect(try PairingCloudRecordMapper.approval(from: approvalRecord) == approval)

        let emptyApprovalRecord = CompanionCloudRecord(
            recordName: "approval-inv-1-phone-1",
            type: .deviceApproval,
            queryableFields: [:],
            encryptedFields: [:],
            encryptedAsset: nil
        )
        #expect(throws: PairingCloudRecordMapperError.missingPayload) {
            try PairingCloudRecordMapper.approval(from: emptyApprovalRecord)
        }
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
