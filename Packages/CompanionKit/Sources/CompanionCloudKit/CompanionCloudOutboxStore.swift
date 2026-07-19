import CompanionDomain
import Foundation

public actor CompanionCloudOutboxStore {
    private struct Outbox: Codable {
        var records: [CompanionCloudRecord]
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func put(_ record: CompanionCloudRecord) throws {
        var outbox = try load()
        outbox.records.removeAll { $0.recordName == record.recordName }
        outbox.records.append(record)
        try save(outbox)
    }

    public func record(named name: String) throws -> CompanionCloudRecord? {
        try load().records.first { $0.recordName == name }
    }

    public func remove(named name: String) throws {
        var outbox = try load()
        outbox.records.removeAll { $0.recordName == name }
        try save(outbox)
    }

    public func removeAll() throws {
        try save(Outbox(records: []))
    }

    private func load() throws -> Outbox {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Outbox(records: [])
        }
        return try CanonicalCoding.decode(
            Outbox.self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func save(_ outbox: Outbox) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CanonicalCoding.encode(outbox).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
