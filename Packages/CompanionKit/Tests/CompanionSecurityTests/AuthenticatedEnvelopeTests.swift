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
