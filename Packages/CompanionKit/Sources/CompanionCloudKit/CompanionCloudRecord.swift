import CompanionDomain
import CompanionSecurity
import Foundation

public enum CompanionCloudRecordType: String, CaseIterable, Codable, Sendable {
    case macEndpoint = "MacEndpoint"
    case pairingCandidate = "PairingCandidate"
    case deviceApproval = "DeviceApproval"
    case gameCatalog = "GameCatalog"
    case analysisRequest = "AnalysisRequest"
    case analysisCancellation = "AnalysisCancellation"
    case analysisStatus = "AnalysisStatus"
    case reportSnapshot = "ReportSnapshot"
}

public struct CompanionCloudRecord: Codable, Equatable, Sendable {
    public let recordName: String
    public let type: CompanionCloudRecordType
    public let queryableFields: [String: String]
    public let encryptedFields: [String: Data]
    public let encryptedAsset: Data?

    public init(
        recordName: String,
        type: CompanionCloudRecordType,
        queryableFields: [String: String],
        encryptedFields: [String: Data],
        encryptedAsset: Data?
    ) {
        self.recordName = recordName
        self.type = type
        self.queryableFields = queryableFields
        self.encryptedFields = encryptedFields
        self.encryptedAsset = encryptedAsset
    }
}

public enum CompanionCloudRecordError: Error, Equatable {
    case missingEnvelope
}

public enum CompanionCloudRecordMapper {
    public static func map(
        _ envelope: AuthenticatedEnvelope,
        type: CompanionCloudRecordType,
        assetThreshold: Int = 800_000
    ) throws -> CompanionCloudRecord {
        let encoded = try CanonicalCoding.encode(envelope)
        let usesAsset = encoded.count > assetThreshold
        return CompanionCloudRecord(
            recordName: envelope.header.recordID,
            type: type,
            queryableFields: [
                "protocolVersion": String(envelope.header.protocolVersion.rawValue),
                "messageID": envelope.header.messageID,
                "sender": envelope.header.sender.rawValue,
                "recipient": envelope.header.recipient.rawValue,
            ],
            encryptedFields: usesAsset ? [:] : ["envelope": encoded],
            encryptedAsset: usesAsset ? encoded : nil
        )
    }

    public static func envelope(
        from record: CompanionCloudRecord
    ) throws -> AuthenticatedEnvelope {
        guard let data = record.encryptedFields["envelope"] ?? record.encryptedAsset else {
            throw CompanionCloudRecordError.missingEnvelope
        }
        return try CanonicalCoding.decode(AuthenticatedEnvelope.self, from: data)
    }
}
