import CompanionDomain
import Foundation

struct PhoneCompanionState: Codable, Equatable, Sendable {
    var catalog: GameCatalogSnapshot?
    var jobs: [AnalysisJobSnapshot]

    static let empty = PhoneCompanionState(catalog: nil, jobs: [])
}

actor PhoneCompanionStateStore {
    private let fileURL: URL

    init(fileURL: URL = PhoneCompanionStateStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> PhoneCompanionState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try CanonicalCoding.decode(
            PhoneCompanionState.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ state: PhoneCompanionState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try CanonicalCoding.encode(state)
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func resetConnectionState() throws {
        try save(.empty)
    }

    private nonisolated static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root
            .appendingPathComponent("CompanionState", isDirectory: true)
            .appendingPathComponent("connection.json")
    }
}
