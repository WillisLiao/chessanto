import CompanionDomain
import CryptoKit
import Foundation

public struct DevicePrivateKeys: Sendable {
    public let signing: Curve25519.Signing.PrivateKey
    public let agreement: Curve25519.KeyAgreement.PrivateKey

    public init(
        signing: Curve25519.Signing.PrivateKey = .init(),
        agreement: Curve25519.KeyAgreement.PrivateKey = .init()
    ) {
        self.signing = signing
        self.agreement = agreement
    }

    public var publicKeys: DevicePublicKeys {
        DevicePublicKeys(
            signing: signing.publicKey.rawRepresentation,
            agreement: agreement.publicKey.rawRepresentation
        )
    }
}

public struct DevicePublicKeys: Codable, Equatable, Sendable {
    public let signing: Data
    public let agreement: Data

    public init(signing: Data, agreement: Data) {
        self.signing = signing
        self.agreement = agreement
    }
}

public struct PairingInvitation: Codable, Equatable, Sendable {
    public let id: String
    public let endpointID: EndpointID
    public let macPublicKeys: DevicePublicKeys
    public let oneTimeSecret: Data
    public let createdAt: Date
    public let expiresAt: Date
    public let signature: Data

    public init(
        id: String,
        endpointID: EndpointID,
        macPublicKeys: DevicePublicKeys,
        oneTimeSecret: Data,
        createdAt: Date,
        expiresAt: Date,
        signature: Data
    ) {
        self.id = id
        self.endpointID = endpointID
        self.macPublicKeys = macPublicKeys
        self.oneTimeSecret = oneTimeSecret
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.signature = signature
    }
}

public struct PairingCandidate: Codable, Equatable, Sendable {
    public let invitationID: String
    public let deviceID: CompanionDeviceID
    public let displayName: String
    public let publicKeys: DevicePublicKeys
    public let createdAt: Date
    public let invitationProof: Data

    public init(
        invitationID: String,
        deviceID: CompanionDeviceID,
        displayName: String,
        publicKeys: DevicePublicKeys,
        createdAt: Date,
        invitationProof: Data
    ) {
        self.invitationID = invitationID
        self.deviceID = deviceID
        self.displayName = displayName
        self.publicKeys = publicKeys
        self.createdAt = createdAt
        self.invitationProof = invitationProof
    }

    public static func make(
        invitation: PairingInvitation,
        deviceID: CompanionDeviceID,
        displayName: String,
        keys: DevicePrivateKeys,
        createdAt: Date
    ) throws -> PairingCandidate {
        let publicKeys = keys.publicKeys
        let proofPayload = PairingProofPayload(
            invitationID: invitation.id,
            deviceID: deviceID,
            displayName: displayName,
            publicKeys: publicKeys,
            createdAt: createdAt
        )
        let proof = HMAC<SHA256>.authenticationCode(
            for: try CanonicalCoding.encode(proofPayload),
            using: SymmetricKey(data: invitation.oneTimeSecret)
        )
        return PairingCandidate(
            invitationID: invitation.id,
            deviceID: deviceID,
            displayName: displayName,
            publicKeys: publicKeys,
            createdAt: createdAt,
            invitationProof: Data(proof)
        )
    }
}

public struct DeviceApproval: Codable, Equatable, Sendable {
    public let invitationID: String
    public let deviceID: CompanionDeviceID
    public let verificationPhrase: String
    public let wrappedContentKey: Data
    public let macAgreementPublicKey: Data

    public init(
        invitationID: String,
        deviceID: CompanionDeviceID,
        verificationPhrase: String,
        wrappedContentKey: Data,
        macAgreementPublicKey: Data
    ) {
        self.invitationID = invitationID
        self.deviceID = deviceID
        self.verificationPhrase = verificationPhrase
        self.wrappedContentKey = wrappedContentKey
        self.macAgreementPublicKey = macAgreementPublicKey
    }
}

public enum PairingError: Error, Equatable {
    case unknownInvitation
    case invitationExpired
    case invitationAlreadyUsed
    case invalidInvitationSignature
    case invalidInvitationProof
    case invalidPublicKey
    case keyAgreementFailed
    case malformedWrappedKey
}

public enum PairingInvitationVerification {
    @discardableResult
    public static func verify(
        _ invitation: PairingInvitation,
        now: Date
    ) throws -> Bool {
        guard invitation.expiresAt > now else {
            throw PairingError.invitationExpired
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try .init(
                rawRepresentation: invitation.macPublicKeys.signing
            )
        } catch {
            throw PairingError.invalidPublicKey
        }
        let unsigned = UnsignedPairingInvitation(
            id: invitation.id,
            endpointID: invitation.endpointID,
            macPublicKeys: invitation.macPublicKeys,
            oneTimeSecret: invitation.oneTimeSecret,
            createdAt: invitation.createdAt,
            expiresAt: invitation.expiresAt
        )
        guard publicKey.isValidSignature(
            invitation.signature,
            for: try CanonicalCoding.encode(unsigned)
        ) else {
            throw PairingError.invalidInvitationSignature
        }
        return true
    }
}

public actor PairingAuthority {
    private struct InvitationState: Sendable {
        let invitation: PairingInvitation
        var isUsed: Bool
    }

    private let endpointID: EndpointID
    private let signingKey: Curve25519.Signing.PrivateKey
    private let agreementKey: Curve25519.KeyAgreement.PrivateKey
    private var contentKey: SymmetricKey
    private var invitations: [String: InvitationState] = [:]

    public init(
        endpointID: EndpointID,
        signingKey: Curve25519.Signing.PrivateKey,
        agreementKey: Curve25519.KeyAgreement.PrivateKey,
        contentKey: SymmetricKey
    ) {
        self.endpointID = endpointID
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        self.contentKey = contentKey
    }

    public func makeInvitation(
        now: Date,
        lifetime: TimeInterval = 300
    ) -> PairingInvitation {
        let id = UUID().uuidString.lowercased()
        let secret = randomData(count: 32)
        let unsigned = UnsignedPairingInvitation(
            id: id,
            endpointID: endpointID,
            macPublicKeys: DevicePublicKeys(
                signing: signingKey.publicKey.rawRepresentation,
                agreement: agreementKey.publicKey.rawRepresentation
            ),
            oneTimeSecret: secret,
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime)
        )
        let signature = (try? signingKey.signature(
            for: CanonicalCoding.encode(unsigned)
        )) ?? Data()
        let invitation = PairingInvitation(
            id: unsigned.id,
            endpointID: unsigned.endpointID,
            macPublicKeys: unsigned.macPublicKeys,
            oneTimeSecret: unsigned.oneTimeSecret,
            createdAt: unsigned.createdAt,
            expiresAt: unsigned.expiresAt,
            signature: signature
        )
        invitations[id] = InvitationState(
            invitation: invitation,
            isUsed: false
        )
        return invitation
    }

    public func approve(
        _ candidate: PairingCandidate,
        now: Date
    ) throws -> DeviceApproval {
        guard var state = invitations[candidate.invitationID] else {
            throw PairingError.unknownInvitation
        }
        guard !state.isUsed else {
            throw PairingError.invitationAlreadyUsed
        }
        guard state.invitation.expiresAt > now else {
            throw PairingError.invitationExpired
        }
        let proofPayload = PairingProofPayload(
            invitationID: candidate.invitationID,
            deviceID: candidate.deviceID,
            displayName: candidate.displayName,
            publicKeys: candidate.publicKeys,
            createdAt: candidate.createdAt
        )
        let expectedProof = HMAC<SHA256>.authenticationCode(
            for: try CanonicalCoding.encode(proofPayload),
            using: SymmetricKey(data: state.invitation.oneTimeSecret)
        )
        guard Data(expectedProof) == candidate.invitationProof else {
            throw PairingError.invalidInvitationProof
        }

        let phoneAgreementKey: Curve25519.KeyAgreement.PublicKey
        do {
            phoneAgreementKey = try .init(
                rawRepresentation: candidate.publicKeys.agreement
            )
        } catch {
            throw PairingError.invalidPublicKey
        }
        let wrappingKey = try deriveWrappingKey(
            privateKey: agreementKey,
            publicKey: phoneAgreementKey,
            invitationSecret: state.invitation.oneTimeSecret
        )
        let contentKeyData = contentKey.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(contentKeyData, using: wrappingKey)
        guard let wrappedContentKey = sealed.combined else {
            throw PairingError.malformedWrappedKey
        }

        state.isUsed = true
        invitations[candidate.invitationID] = state
        return DeviceApproval(
            invitationID: candidate.invitationID,
            deviceID: candidate.deviceID,
            verificationPhrase: PairingVerification.phrase(
                invitation: state.invitation,
                candidate: candidate
            ),
            wrappedContentKey: wrappedContentKey,
            macAgreementPublicKey: agreementKey.publicKey.rawRepresentation
        )
    }

    public func rotateContentKey() {
        contentKey = SymmetricKey(size: .bits256)
    }

    public func contentKeyData() -> Data {
        contentKey.withUnsafeBytes { Data($0) }
    }
}

public enum PairingVerification {
    public static func phrase(
        invitation: PairingInvitation,
        candidate: PairingCandidate
    ) -> String {
        var transcript = Data()
        transcript.append(invitation.oneTimeSecret)
        transcript.append(candidate.invitationProof)
        let digest = SHA256.hash(data: transcript)
        let bytes = Array(digest)
        return (0..<4)
            .map { verificationWords[Int(bytes[$0]) % verificationWords.count] }
            .joined(separator: " ")
    }

    private static let verificationWords = [
        "amber", "bishop", "cedar", "delta",
        "ember", "falcon", "garden", "harbor",
        "ivory", "knight", "lantern", "maple",
        "north", "olive", "paper", "quiet",
    ]
}

public enum ContentKeyWrapping {
    public static func unwrap(
        _ approval: DeviceApproval,
        invitationSecret: Data,
        phoneAgreementKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> SymmetricKey {
        let macPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            macPublicKey = try .init(
                rawRepresentation: approval.macAgreementPublicKey
            )
        } catch {
            throw PairingError.invalidPublicKey
        }
        let wrappingKey = try deriveWrappingKey(
            privateKey: phoneAgreementKey,
            publicKey: macPublicKey,
            invitationSecret: invitationSecret
        )
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try .init(combined: approval.wrappedContentKey)
        } catch {
            throw PairingError.malformedWrappedKey
        }
        do {
            return SymmetricKey(data: try AES.GCM.open(
                sealedBox,
                using: wrappingKey
            ))
        } catch {
            throw PairingError.keyAgreementFailed
        }
    }
}

private struct UnsignedPairingInvitation: Codable {
    let id: String
    let endpointID: EndpointID
    let macPublicKeys: DevicePublicKeys
    let oneTimeSecret: Data
    let createdAt: Date
    let expiresAt: Date
}

private struct PairingProofPayload: Codable {
    let invitationID: String
    let deviceID: CompanionDeviceID
    let displayName: String
    let publicKeys: DevicePublicKeys
    let createdAt: Date
}

private func deriveWrappingKey(
    privateKey: Curve25519.KeyAgreement.PrivateKey,
    publicKey: Curve25519.KeyAgreement.PublicKey,
    invitationSecret: Data
) throws -> SymmetricKey {
    do {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
            with: publicKey
        )
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: invitationSecret,
            sharedInfo: Data("Chessanto companion content key v1".utf8),
            outputByteCount: 32
        )
    } catch {
        throw PairingError.keyAgreementFailed
    }
}

private func randomData(count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
}
