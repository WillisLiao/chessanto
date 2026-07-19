import CompanionDomain
import CompanionSecurity
import Foundation

public enum PairingCloudRecordMapperError: Error {
    case missingPayload
}

public enum PairingCloudRecordMapper {
    public static func candidate(
        _ candidate: PairingCandidate,
        endpointID: EndpointID
    ) throws -> CompanionCloudRecord {
        CompanionCloudRecord(
            recordName: "pairing-\(candidate.invitationID)-\(candidate.deviceID.rawValue)",
            type: .pairingCandidate,
            queryableFields: [
                "protocolVersion": "1",
                "invitationID": candidate.invitationID,
                "recipient": endpointID.rawValue,
                "sender": candidate.deviceID.rawValue,
            ],
            encryptedFields: [
                "candidate": try CanonicalCoding.encode(candidate)
            ],
            encryptedAsset: nil
        )
    }

    public static func candidate(
        from record: CompanionCloudRecord
    ) throws -> PairingCandidate {
        guard let data = record.encryptedFields["candidate"] else {
            throw PairingCloudRecordMapperError.missingPayload
        }
        return try CanonicalCoding.decode(PairingCandidate.self, from: data)
    }

    public static func approval(
        _ approval: DeviceApproval,
        endpointID: EndpointID
    ) throws -> CompanionCloudRecord {
        CompanionCloudRecord(
            recordName: "approval-\(approval.invitationID)-\(approval.deviceID.rawValue)",
            type: .deviceApproval,
            queryableFields: [
                "protocolVersion": "1",
                "invitationID": approval.invitationID,
                "recipient": approval.deviceID.rawValue,
                "sender": endpointID.rawValue,
            ],
            encryptedFields: [
                "approval": try CanonicalCoding.encode(approval)
            ],
            encryptedAsset: nil
        )
    }

    public static func approval(
        from record: CompanionCloudRecord
    ) throws -> DeviceApproval {
        guard let data = record.encryptedFields["approval"] else {
            throw PairingCloudRecordMapperError.missingPayload
        }
        return try CanonicalCoding.decode(DeviceApproval.self, from: data)
    }
}
