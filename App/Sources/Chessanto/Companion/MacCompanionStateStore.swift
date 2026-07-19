import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation

struct ApprovedCompanionDevice: Codable, Equatable, Identifiable, Sendable {
    let id: CompanionDeviceID
    let displayName: String
    let publicKeys: DevicePublicKeys
    let approvedAt: Date
    var revokedAt: Date?

    var isActive: Bool {
        revokedAt == nil
    }
}

struct MacCompanionPersistentState: Codable, Equatable, Sendable {
    var devices: [ApprovedCompanionDevice]
    var ledgerEntries: [AnalysisRequestLedgerEntry]
    var catalogVersion: Int

    static let empty = MacCompanionPersistentState(
        devices: [],
        ledgerEntries: [],
        catalogVersion: 0
    )
}

actor MacCompanionStateStore {
    private let fileURL: URL

    init(fileURL: URL = MacCompanionStateStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> MacCompanionPersistentState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try CanonicalCoding.decode(
            MacCompanionPersistentState.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ state: MacCompanionPersistentState) throws {
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

    func signingKey(
        for deviceID: CompanionDeviceID
    ) throws -> Curve25519.Signing.PublicKey? {
        guard
            let device = try load().devices.first(where: {
                $0.id == deviceID && $0.isActive
            })
        else {
            return nil
        }
        return try .init(rawRepresentation: device.publicKeys.signing)
    }

    private nonisolated static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root
            .appendingPathComponent("Chessanto", isDirectory: true)
            .appendingPathComponent("Companion", isDirectory: true)
            .appendingPathComponent("mac-state.json")
    }
}

struct MacCompanionIdentity: Sendable {
    let endpointID: EndpointID
    let deviceID: CompanionDeviceID
    let keys: DevicePrivateKeys
    let contentKey: SymmetricKey
}

actor MacCompanionSecretStore {
    private enum Account {
        static let endpointID = "mac-endpoint-id"
        static let signingKey = "mac-signing-key"
        static let agreementKey = "mac-agreement-key"
        static let contentKey = "endpoint-content-key"
    }

    private let secrets: any SecretStoring

    init(
        secrets: any SecretStoring = KeychainSecretStore(
            service: "com.chessanto.app.companion"
        )
    ) {
        self.secrets = secrets
    }

    func identity() throws -> MacCompanionIdentity {
        if
            let endpointData = try secrets.load(account: Account.endpointID),
            let endpointString = String(data: endpointData, encoding: .utf8),
            let signingData = try secrets.load(account: Account.signingKey),
            let agreementData = try secrets.load(account: Account.agreementKey),
            let contentData = try secrets.load(account: Account.contentKey)
        {
            return MacCompanionIdentity(
                endpointID: EndpointID(endpointString),
                deviceID: CompanionDeviceID(endpointString),
                keys: DevicePrivateKeys(
                    signing: try .init(rawRepresentation: signingData),
                    agreement: try .init(rawRepresentation: agreementData)
                ),
                contentKey: SymmetricKey(data: contentData)
            )
        }

        let endpointString = UUID().uuidString.lowercased()
        let keys = DevicePrivateKeys()
        let contentKey = SymmetricKey(size: .bits256)
        try secrets.save(
            Data(endpointString.utf8),
            account: Account.endpointID
        )
        try secrets.save(
            keys.signing.rawRepresentation,
            account: Account.signingKey
        )
        try secrets.save(
            keys.agreement.rawRepresentation,
            account: Account.agreementKey
        )
        try saveContentKey(contentKey)
        return MacCompanionIdentity(
            endpointID: EndpointID(endpointString),
            deviceID: CompanionDeviceID(endpointString),
            keys: keys,
            contentKey: contentKey
        )
    }

    func saveContentKey(_ contentKey: SymmetricKey) throws {
        try secrets.save(
            contentKey.withUnsafeBytes { Data($0) },
            account: Account.contentKey
        )
    }
}
