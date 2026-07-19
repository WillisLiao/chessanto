import CompanionDomain
import CryptoKit
import Foundation

public struct AuthenticatedEnvelopeHeader: Codable, Equatable, Sendable {
    public let recordID: String
    public let protocolVersion: CompanionProtocolVersion
    public let messageID: String
    public let sender: CompanionDeviceID
    public let recipient: EndpointID

    public init(
        recordID: String,
        protocolVersion: CompanionProtocolVersion,
        messageID: String,
        sender: CompanionDeviceID,
        recipient: EndpointID
    ) {
        self.recordID = recordID
        self.protocolVersion = protocolVersion
        self.messageID = messageID
        self.sender = sender
        self.recipient = recipient
    }
}

public struct AuthenticatedEnvelope: Codable, Equatable, Sendable {
    public let header: AuthenticatedEnvelopeHeader
    public let sealedPayload: Data
    public let signature: Data

    public init(
        header: AuthenticatedEnvelopeHeader,
        sealedPayload: Data,
        signature: Data
    ) {
        self.header = header
        self.sealedPayload = sealedPayload
        self.signature = signature
    }
}

public enum CompanionEnvelopeError: Error, Equatable {
    case wrongRecipient
    case invalidSignature
    case malformedCiphertext
    case authenticationFailed
    case replayedMessage
}

public enum CompanionEnvelopeCrypto {
    public static func seal(
        _ payload: Data,
        header: AuthenticatedEnvelopeHeader,
        contentKey: SymmetricKey,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> AuthenticatedEnvelope {
        let authenticatedData = try CanonicalCoding.encode(header)
        let sealedBox = try AES.GCM.seal(
            payload,
            using: contentKey,
            authenticating: authenticatedData
        )
        guard let combined = sealedBox.combined else {
            throw CompanionEnvelopeError.malformedCiphertext
        }
        let signature = try signingKey.signature(
            for: signaturePayload(
                authenticatedData: authenticatedData,
                sealedPayload: combined
            )
        )
        return AuthenticatedEnvelope(
            header: header,
            sealedPayload: combined,
            signature: signature
        )
    }

    public static func open(
        _ envelope: AuthenticatedEnvelope,
        expectedRecipient: EndpointID,
        contentKey: SymmetricKey,
        senderSigningKey: Curve25519.Signing.PublicKey
    ) throws -> Data {
        guard envelope.header.recipient == expectedRecipient else {
            throw CompanionEnvelopeError.wrongRecipient
        }
        let authenticatedData = try CanonicalCoding.encode(envelope.header)
        guard senderSigningKey.isValidSignature(
            envelope.signature,
            for: signaturePayload(
                authenticatedData: authenticatedData,
                sealedPayload: envelope.sealedPayload
            )
        ) else {
            throw CompanionEnvelopeError.invalidSignature
        }
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
        } catch {
            throw CompanionEnvelopeError.malformedCiphertext
        }
        do {
            return try AES.GCM.open(
                sealedBox,
                using: contentKey,
                authenticating: authenticatedData
            )
        } catch {
            throw CompanionEnvelopeError.authenticationFailed
        }
    }

    private static func signaturePayload(
        authenticatedData: Data,
        sealedPayload: Data
    ) -> Data {
        var result = Data()
        result.append(authenticatedData)
        result.append(0)
        result.append(sealedPayload)
        return result
    }
}

public actor SecureEnvelopeInbox {
    private var openedMessageIDs: Set<String> = []

    public init() {}

    public func open(
        _ envelope: AuthenticatedEnvelope,
        expectedRecipient: EndpointID,
        contentKey: SymmetricKey,
        senderSigningKey: Curve25519.Signing.PublicKey
    ) throws -> Data {
        guard !openedMessageIDs.contains(envelope.header.messageID) else {
            throw CompanionEnvelopeError.replayedMessage
        }
        let payload = try CompanionEnvelopeCrypto.open(
            envelope,
            expectedRecipient: expectedRecipient,
            contentKey: contentKey,
            senderSigningKey: senderSigningKey
        )
        openedMessageIDs.insert(envelope.header.messageID)
        return payload
    }
}
