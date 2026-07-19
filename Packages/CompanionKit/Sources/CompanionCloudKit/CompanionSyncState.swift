import CloudKit
import CompanionDomain
import Foundation

public enum CompanionSyncRecovery: String, Codable, Equatable, Sendable {
    case ready
    case iCloudAccountRequired
    case accountChanged
    case storageFull
    case zoneResetRequired
    case encryptionKeyResetRequired
    case retryWhenOnline
    case retryLater
}

public struct CompanionSyncState: Codable, Equatable, Sendable {
    public let engineState: Data?
    public let accountIdentifier: String?
    public let lastSuccessfulSyncAt: Date?
    public let recovery: CompanionSyncRecovery

    public init(
        engineState: Data?,
        accountIdentifier: String?,
        lastSuccessfulSyncAt: Date?,
        recovery: CompanionSyncRecovery
    ) {
        self.engineState = engineState
        self.accountIdentifier = accountIdentifier
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.recovery = recovery
    }

    public static let initial = CompanionSyncState(
        engineState: nil,
        accountIdentifier: nil,
        lastSuccessfulSyncAt: nil,
        recovery: .ready
    )
}

public actor CompanionSyncStateStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CompanionSyncState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .initial
        }
        return try CanonicalCoding.decode(
            CompanionSyncState.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ state: CompanionSyncState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CanonicalCoding.encode(state).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func reset() throws {
        try save(.initial)
    }
}

public enum CompanionCloudErrorMapper {
    public static func recovery(for error: Error) -> CompanionSyncRecovery {
        guard let cloudError = error as? CKError else {
            return .retryLater
        }
        switch cloudError.code {
        case .notAuthenticated:
            return .iCloudAccountRequired
        case .quotaExceeded:
            return .storageFull
        case .zoneNotFound, .changeTokenExpired, .userDeletedZone:
            return .zoneResetRequired
        case .networkFailure, .networkUnavailable:
            return .retryWhenOnline
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .retryLater
        default:
            return .retryLater
        }
    }
}

public enum CompanionSyncReason: String, Codable, Equatable, Sendable {
    case launch
    case foreground
    case pullToRefresh
    case lifecycleChange
    case advisoryPush
}

public protocol CompanionCloudSyncBoundary: Sendable {
    func synchronize(reason: CompanionSyncReason) async throws
}

public actor CompanionSyncController {
    private let boundary: any CompanionCloudSyncBoundary

    public init(boundary: any CompanionCloudSyncBoundary) {
        self.boundary = boundary
    }

    public func synchronize(reason: CompanionSyncReason) async throws {
        try await boundary.synchronize(reason: reason)
    }
}
