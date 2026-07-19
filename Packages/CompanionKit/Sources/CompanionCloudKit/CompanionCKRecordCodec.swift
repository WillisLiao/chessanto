import CloudKit
import Foundation

public enum CompanionCKRecordCodecError: Error {
    case unknownRecordType(String)
    case missingAssetFile
}

public enum CompanionCKRecordCodec {
    public static func record(
        from value: CompanionCloudRecord,
        zoneID: CKRecordZone.ID,
        assetDirectory: URL
    ) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: value.recordName,
            zoneID: zoneID
        )
        let record = CKRecord(
            recordType: value.type.rawValue,
            recordID: recordID
        )
        for (key, fieldValue) in value.queryableFields {
            record[key] = fieldValue as CKRecordValue
        }
        for (key, fieldValue) in value.encryptedFields {
            record.encryptedValues[key] = fieldValue as CKRecordValue
        }
        if let asset = value.encryptedAsset {
            try FileManager.default.createDirectory(
                at: assetDirectory,
                withIntermediateDirectories: true
            )
            let url = assetDirectory.appendingPathComponent(
                "\(value.recordName).encrypted"
            )
            try asset.write(to: url, options: [.atomic])
            record.encryptedValues["envelopeAsset"] = CKAsset(fileURL: url)
        }
        return record
    }

    public static func value(from record: CKRecord) throws -> CompanionCloudRecord {
        guard let type = CompanionCloudRecordType(rawValue: record.recordType) else {
            throw CompanionCKRecordCodecError.unknownRecordType(record.recordType)
        }
        var queryable: [String: String] = [:]
        for key in [
            "protocolVersion",
            "messageID",
            "sender",
            "recipient",
            "invitationID",
        ] {
            if let value = record[key] as? String {
                queryable[key] = value
            }
        }
        var encrypted: [String: Data] = [:]
        if let envelope = record.encryptedValues["envelope"] as? Data {
            encrypted["envelope"] = envelope
        }
        if let candidate = record.encryptedValues["candidate"] as? Data {
            encrypted["candidate"] = candidate
        }
        if let approval = record.encryptedValues["approval"] as? Data {
            encrypted["approval"] = approval
        }
        let assetData: Data?
        if let asset = record.encryptedValues["envelopeAsset"] as? CKAsset {
            guard let url = asset.fileURL else {
                throw CompanionCKRecordCodecError.missingAssetFile
            }
            assetData = try Data(contentsOf: url)
        } else {
            assetData = nil
        }
        return CompanionCloudRecord(
            recordName: record.recordID.recordName,
            type: type,
            queryableFields: queryable,
            encryptedFields: encrypted,
            encryptedAsset: assetData
        )
    }
}
