import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation

struct PhoneIdentity: Sendable {
    let deviceID: CompanionDeviceID
    let keys: DevicePrivateKeys
}

struct StoredPhonePairing: Sendable {
    let invitation: PairingInvitation
    let approval: DeviceApproval
    let contentKey: SymmetricKey
}

actor PhonePairingStore {
    private enum Account {
        static let deviceID = "phone-device-id"
        static let signingKey = "phone-signing-key"
        static let agreementKey = "phone-agreement-key"
        static let invitation = "pairing-invitation"
        static let approval = "device-approval"
        static let contentKey = "endpoint-content-key"
    }

    private let secrets: any SecretStoring

    init(
        secrets: any SecretStoring = KeychainSecretStore(
            service: "com.chessanto.companion.pairing"
        )
    ) {
        self.secrets = secrets
    }

    func identity() throws -> PhoneIdentity {
        if
            let deviceData = try secrets.load(account: Account.deviceID),
            let deviceString = String(data: deviceData, encoding: .utf8),
            let signingData = try secrets.load(account: Account.signingKey),
            let agreementData = try secrets.load(account: Account.agreementKey)
        {
            return PhoneIdentity(
                deviceID: CompanionDeviceID(deviceString),
                keys: DevicePrivateKeys(
                    signing: try .init(rawRepresentation: signingData),
                    agreement: try .init(rawRepresentation: agreementData)
                )
            )
        }

        let identity = PhoneIdentity(
            deviceID: CompanionDeviceID(UUID().uuidString.lowercased()),
            keys: DevicePrivateKeys()
        )
        try secrets.save(
            Data(identity.deviceID.rawValue.utf8),
            account: Account.deviceID
        )
        try secrets.save(
            identity.keys.signing.rawRepresentation,
            account: Account.signingKey
        )
        try secrets.save(
            identity.keys.agreement.rawRepresentation,
            account: Account.agreementKey
        )
        return identity
    }

    func saveInvitation(_ invitation: PairingInvitation) throws {
        try secrets.save(
            CanonicalCoding.encode(invitation),
            account: Account.invitation
        )
    }

    func invitation() throws -> PairingInvitation? {
        guard let data = try secrets.load(account: Account.invitation) else {
            return nil
        }
        return try CanonicalCoding.decode(PairingInvitation.self, from: data)
    }

    func complete(
        approval: DeviceApproval,
        contentKey: SymmetricKey
    ) throws {
        try secrets.save(
            CanonicalCoding.encode(approval),
            account: Account.approval
        )
        try secrets.save(
            contentKey.withUnsafeBytes { Data($0) },
            account: Account.contentKey
        )
    }

    func pairing() throws -> StoredPhonePairing? {
        guard
            let invitation = try invitation(),
            let approvalData = try secrets.load(account: Account.approval),
            let contentKeyData = try secrets.load(account: Account.contentKey)
        else {
            return nil
        }
        return StoredPhonePairing(
            invitation: invitation,
            approval: try CanonicalCoding.decode(
                DeviceApproval.self,
                from: approvalData
            ),
            contentKey: SymmetricKey(data: contentKeyData)
        )
    }

    func resetPairing() throws {
        try secrets.remove(account: Account.invitation)
        try secrets.remove(account: Account.approval)
        try secrets.remove(account: Account.contentKey)
    }
}
