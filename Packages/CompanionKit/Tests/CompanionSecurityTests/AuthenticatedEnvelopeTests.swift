import CompanionDomain
import CryptoKit
import Foundation
import Testing
@testable import CompanionSecurity

@Suite("Authenticated companion envelopes")
struct AuthenticatedEnvelopeTests {
    @Test("signed encrypted payload opens for the intended recipient")
    func signedEncryptedPayloadOpensForTheIntendedRecipient() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let header = AuthenticatedEnvelopeHeader(
            recordID: "AnalysisRequest-request-1",
            protocolVersion: .v1,
            messageID: "request-1",
            sender: CompanionDeviceID("phone-1"),
            recipient: EndpointID("mac-1")
        )
        let payload = Data("bounded request".utf8)

        let envelope = try CompanionEnvelopeCrypto.seal(
            payload,
            header: header,
            contentKey: contentKey,
            signingKey: senderSigningKey
        )
        let opened = try CompanionEnvelopeCrypto.open(
            envelope,
            expectedRecipient: EndpointID("mac-1"),
            contentKey: contentKey,
            senderSigningKey: senderSigningKey.publicKey
        )

        #expect(opened == payload)
    }

    @Test("wrong recipient is rejected")
    func wrongRecipientIsRejected() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )

        #expect(throws: CompanionEnvelopeError.wrongRecipient) {
            try CompanionEnvelopeCrypto.open(
                envelope,
                expectedRecipient: EndpointID("other-mac"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("ciphertext tampering is rejected")
    func ciphertextTamperingIsRejected() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )
        var tamperedPayload = envelope.sealedPayload
        tamperedPayload[tamperedPayload.startIndex] ^= 0x01
        let tampered = AuthenticatedEnvelope(
            header: envelope.header,
            sealedPayload: tamperedPayload,
            signature: envelope.signature
        )

        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                tampered,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("opened message cannot be replayed")
    func openedMessageCannotBeReplayed() async throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )
        let inbox = SecureEnvelopeInbox()

        _ = try await inbox.open(
            envelope,
            expectedRecipient: EndpointID("mac-1"),
            contentKey: contentKey,
            senderSigningKey: senderSigningKey.publicKey
        )

        await #expect(throws: CompanionEnvelopeError.replayedMessage) {
            try await inbox.open(
                envelope,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("tampered header fields are rejected by signature verification")
    func tamperedHeaderFieldsAreRejected() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )

        let modifiedRecordID = AuthenticatedEnvelope(
            header: AuthenticatedEnvelopeHeader(
                recordID: "different-record",
                protocolVersion: envelope.header.protocolVersion,
                messageID: envelope.header.messageID,
                sender: envelope.header.sender,
                recipient: envelope.header.recipient
            ),
            sealedPayload: envelope.sealedPayload,
            signature: envelope.signature
        )
        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                modifiedRecordID,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }

        let modifiedSender = AuthenticatedEnvelope(
            header: AuthenticatedEnvelopeHeader(
                recordID: envelope.header.recordID,
                protocolVersion: envelope.header.protocolVersion,
                messageID: envelope.header.messageID,
                sender: CompanionDeviceID("attacker-phone"),
                recipient: envelope.header.recipient
            ),
            sealedPayload: envelope.sealedPayload,
            signature: envelope.signature
        )
        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                modifiedSender,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("truncated and malformed ciphertexts are rejected")
    func truncatedAndMalformedCiphertextsAreRejected() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )

        let truncatedPayload = AuthenticatedEnvelope(
            header: envelope.header,
            sealedPayload: Data([1, 2, 3]),
            signature: envelope.signature
        )
        #expect(throws: CompanionEnvelopeError.self) {
            try CompanionEnvelopeCrypto.open(
                truncatedPayload,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }

        let emptyPayload = AuthenticatedEnvelope(
            header: envelope.header,
            sealedPayload: Data(),
            signature: envelope.signature
        )
        #expect(throws: CompanionEnvelopeError.self) {
            try CompanionEnvelopeCrypto.open(
                emptyPayload,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("forged and truncated signatures are rejected")
    func forgedAndTruncatedSignaturesAreRejected() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("bounded request".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderSigningKey
        )

        let shortSignature = AuthenticatedEnvelope(
            header: envelope.header,
            sealedPayload: envelope.sealedPayload,
            signature: Data(repeating: 0, count: 16)
        )
        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                shortSignature,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }

        let forgedSignature = AuthenticatedEnvelope(
            header: envelope.header,
            sealedPayload: envelope.sealedPayload,
            signature: Data(repeating: 0xcc, count: 64)
        )
        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                forgedSignature,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("mismatched content key fails authentication after signature verification")
    func mismatchedContentKeyFailsAuthentication() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey1 = SymmetricKey(size: .bits256)
        let contentKey2 = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("secret command".utf8),
            header: makeHeader(),
            contentKey: contentKey1,
            signingKey: senderSigningKey
        )

        #expect(throws: CompanionEnvelopeError.authenticationFailed) {
            try CompanionEnvelopeCrypto.open(
                envelope,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey2,
                senderSigningKey: senderSigningKey.publicKey
            )
        }
    }

    @Test("sender signing key mismatch is rejected")
    func senderSigningKeyMismatchIsRejected() throws {
        let senderKey1 = Curve25519.Signing.PrivateKey()
        let senderKey2 = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let envelope = try CompanionEnvelopeCrypto.seal(
            Data("secret command".utf8),
            header: makeHeader(),
            contentKey: contentKey,
            signingKey: senderKey1
        )

        #expect(throws: CompanionEnvelopeError.invalidSignature) {
            try CompanionEnvelopeCrypto.open(
                envelope,
                expectedRecipient: EndpointID("mac-1"),
                contentKey: contentKey,
                senderSigningKey: senderKey2.publicKey
            )
        }
    }

    @Test("empty header fields fail closed on seal and open")
    func emptyHeaderFieldsFailClosed() throws {
        let senderSigningKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let emptyHeader = AuthenticatedEnvelopeHeader(
            recordID: "",
            protocolVersion: .v1,
            messageID: "",
            sender: CompanionDeviceID("phone-1"),
            recipient: EndpointID("mac-1")
        )

        #expect(throws: CompanionEnvelopeError.malformedCiphertext) {
            try CompanionEnvelopeCrypto.seal(
                Data("payload".utf8),
                header: emptyHeader,
                contentKey: contentKey,
                signingKey: senderSigningKey
            )
        }
    }

    private func makeHeader() -> AuthenticatedEnvelopeHeader {
        AuthenticatedEnvelopeHeader(
            recordID: "AnalysisRequest-request-1",
            protocolVersion: .v1,
            messageID: "request-1",
            sender: CompanionDeviceID("phone-1"),
            recipient: EndpointID("mac-1")
        )
    }
}
