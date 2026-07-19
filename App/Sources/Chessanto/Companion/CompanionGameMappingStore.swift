import CompanionDomain
import Foundation

enum CompanionGameMappingError: Error {
    case missingMapping(CompanionGameID)
}

/// A small sidecar store that keeps opaque companion identifiers out of the
/// live Chessanto schema and prevents local row IDs from crossing devices.
actor CompanionGameMappingStore {
    private struct Entry: Codable {
        let opaqueID: CompanionGameID
        let localGameID: Int64
    }

    private struct Manifest: Codable {
        var entries: [Entry]
    }

    private let fileURL: URL
    private let makeID: @Sendable () -> CompanionGameID

    init(
        fileURL: URL = CompanionGameMappingStore.defaultFileURL(),
        makeID: @escaping @Sendable () -> CompanionGameID = {
            CompanionGameID(UUID().uuidString.lowercased())
        }
    ) {
        self.fileURL = fileURL
        self.makeID = makeID
    }

    func assign(localGameID: Int64) throws -> CompanionGameID {
        var manifest = try load()
        if let existing = manifest.entries.first(where: { $0.localGameID == localGameID }) {
            return existing.opaqueID
        }
        let opaqueID = makeID()
        manifest.entries.append(Entry(opaqueID: opaqueID, localGameID: localGameID))
        try save(manifest)
        return opaqueID
    }

    func localGameID(for opaqueID: CompanionGameID) throws -> Int64 {
        guard let entry = try load().entries.first(where: { $0.opaqueID == opaqueID }) else {
            throw CompanionGameMappingError.missingMapping(opaqueID)
        }
        return entry.localGameID
    }

    func revokeAll() throws {
        try save(Manifest(entries: []))
    }

    private func load() throws -> Manifest {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Manifest(entries: [])
        }
        return try CanonicalCoding.decode(Manifest.self, from: Data(contentsOf: fileURL))
    }

    private func save(_ manifest: Manifest) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CanonicalCoding.encode(manifest).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private nonisolated static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root
            .appendingPathComponent("Chessanto", isDirectory: true)
            .appendingPathComponent("Companion", isDirectory: true)
            .appendingPathComponent("game-map.json")
    }
}
