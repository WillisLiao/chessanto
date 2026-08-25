import CompanionDomain
import CryptoKit
import Foundation
import Testing
@testable import CompanionSecurity

@Suite("Companion pairing security")
struct PairingSecurityTests {
    @Test("pairing invitation expires and can be approved only once")
    func pairingInvitationExpiresAndCanBeApprovedOnlyOnce() async throws {
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: SymmetricKey(size: .bits256)
        )
        let phoneKeys = DevicePrivateKeys()
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )
        let candidate = try PairingCandidate.make(
            invitation: invitation,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "Willis's iPhone",
            keys: phoneKeys,
            createdAt: Date(timeIntervalSince1970: 101)
        )

        _ = try await authority.approve(
            candidate,
            now: Date(timeIntervalSince1970: 102)
        )

        await #expect(throws: PairingError.invitationAlreadyUsed) {
            try await authority.approve(
                candidate,
                now: Date(timeIntervalSince1970: 103)
            )
        }

        let expiredInvitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 200)
        )
        let expiredCandidate = try PairingCandidate.make(
            invitation: expiredInvitation,
            deviceID: CompanionDeviceID("phone-2"),
            displayName: "Other iPhone",
            keys: DevicePrivateKeys(),
            createdAt: Date(timeIntervalSince1970: 201)
        )

        await #expect(throws: PairingError.invitationExpired) {
            try await authority.approve(
                expiredCandidate,
                now: Date(timeIntervalSince1970: 501)
            )
        }
    }

    @Test("approval wraps the content key and rotation replaces it")
    func approvalWrapsTheContentKeyAndRotationReplacesIt() async throws {
        let originalContentKey = SymmetricKey(size: .bits256)
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: originalContentKey
        )
        let phoneKeys = DevicePrivateKeys()
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )
        let candidate = try PairingCandidate.make(
            invitation: invitation,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "Willis's iPhone",
            keys: phoneKeys,
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let approval = try await authority.approve(
            candidate,
            now: Date(timeIntervalSince1970: 102)
        )

        let unwrapped = try ContentKeyWrapping.unwrap(
            approval,
            invitationSecret: invitation.oneTimeSecret,
            phoneAgreementKey: phoneKeys.agreement
        )
        let unwrappedData = unwrapped.withUnsafeBytes { Data($0) }
        let originalData = originalContentKey.withUnsafeBytes { Data($0) }

        #expect(unwrappedData == originalData)
        #expect(
            approval.verificationPhrase
                == PairingVerification.phrase(
                    invitation: invitation,
                    candidate: candidate
                )
        )

        await authority.rotateContentKey()
        #expect(await authority.contentKeyData() != originalData)
    }

    @Test("phone rejects an expired or forged QR invitation")
    func phoneRejectsExpiredOrForgedInvitation() async throws {
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: SymmetricKey(size: .bits256)
        )
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(
            try PairingInvitationVerification.verify(
                invitation,
                now: Date(timeIntervalSince1970: 101)
            )
        )
        #expect(throws: PairingError.invitationExpired) {
            try PairingInvitationVerification.verify(
                invitation,
                now: Date(timeIntervalSince1970: 401)
            )
        }

        let forged = PairingInvitation(
            id: invitation.id,
            endpointID: invitation.endpointID,
            macPublicKeys: invitation.macPublicKeys,
            oneTimeSecret: Data(repeating: 0, count: 32),
            createdAt: invitation.createdAt,
            expiresAt: invitation.expiresAt,
            signature: invitation.signature
        )
        #expect(throws: PairingError.invalidInvitationSignature) {
            try PairingInvitationVerification.verify(
                forged,
                now: Date(timeIntervalSince1970: 101)
            )
        }
    }

    @Test("pairing invitation codec tolerates leading and trailing whitespace and case-insensitive URL")
    func pairingInvitationCodecToleratesWhitespace() async throws {
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: SymmetricKey(size: .bits256)
        )
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )
        let encoded = try PairingInvitationQRCodec.encode(invitation)
        let withWhitespace = "  \n  \(encoded)  \r\n"
        let decoded = try PairingInvitationQRCodec.decode(withWhitespace)
        #expect(decoded == invitation)

        let upperScheme = encoded.replacingOccurrences(of: "chessanto://pair", with: "CHESSANTO://PAIR")
        let decodedUpper = try PairingInvitationQRCodec.decode(upperScheme)
        #expect(decodedUpper == invitation)
    }

    @Test("codec rejects malformed and adversarial URL inputs")
    func codecRejectsMalformedAndAdversarialURLInputs() throws {
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("not-a-valid-url")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("https://chessanto.app/pair?v=1&invitation=abc")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("chessanto://other-host?v=1&invitation=abc")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("chessanto://pair?invitation=abc")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("chessanto://pair?v=2&invitation=abc")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidURL) {
            try PairingInvitationQRCodec.decode("chessanto://pair?v=1")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidPayload) {
            try PairingInvitationQRCodec.decode("chessanto://pair?v=1&invitation=%%%corrupt-base64%%%")
        }
        #expect(throws: PairingInvitationQRCodecError.invalidPayload) {
            try PairingInvitationQRCodec.decode("chessanto://pair?v=1&invitation=bm90LWpzb24")
        }
    }

    @Test("phone rejects corrupted public keys and inverted timestamps")
    func phoneRejectsCorruptedPublicKeysAndInvertedTimestamps() async throws {
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: SymmetricKey(size: .bits256)
        )
        let validInvitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )

        let shortSigningKey = PairingInvitation(
            id: validInvitation.id,
            endpointID: validInvitation.endpointID,
            macPublicKeys: DevicePublicKeys(
                signing: Data([1, 2, 3]),
                agreement: validInvitation.macPublicKeys.agreement
            ),
            oneTimeSecret: validInvitation.oneTimeSecret,
            createdAt: validInvitation.createdAt,
            expiresAt: validInvitation.expiresAt,
            signature: validInvitation.signature
        )
        #expect(throws: PairingError.invalidPublicKey) {
            try PairingInvitationVerification.verify(shortSigningKey, now: Date(timeIntervalSince1970: 101))
        }

        let shortAgreementKey = PairingInvitation(
            id: validInvitation.id,
            endpointID: validInvitation.endpointID,
            macPublicKeys: DevicePublicKeys(
                signing: validInvitation.macPublicKeys.signing,
                agreement: Data([1, 2, 3])
            ),
            oneTimeSecret: validInvitation.oneTimeSecret,
            createdAt: validInvitation.createdAt,
            expiresAt: validInvitation.expiresAt,
            signature: validInvitation.signature
        )
        #expect(throws: PairingError.invalidPublicKey) {
            try PairingInvitationVerification.verify(shortAgreementKey, now: Date(timeIntervalSince1970: 101))
        }

        let shortSecret = PairingInvitation(
            id: validInvitation.id,
            endpointID: validInvitation.endpointID,
            macPublicKeys: validInvitation.macPublicKeys,
            oneTimeSecret: Data([1, 2, 3]),
            createdAt: validInvitation.createdAt,
            expiresAt: validInvitation.expiresAt,
            signature: validInvitation.signature
        )
        #expect(throws: PairingError.invalidInvitationProof) {
            try PairingInvitationVerification.verify(shortSecret, now: Date(timeIntervalSince1970: 101))
        }

        let invertedTimestamps = PairingInvitation(
            id: validInvitation.id,
            endpointID: validInvitation.endpointID,
            macPublicKeys: validInvitation.macPublicKeys,
            oneTimeSecret: validInvitation.oneTimeSecret,
            createdAt: Date(timeIntervalSince1970: 500),
            expiresAt: Date(timeIntervalSince1970: 200),
            signature: validInvitation.signature
        )
        #expect(throws: PairingError.invitationExpired) {
            try PairingInvitationVerification.verify(invertedTimestamps, now: Date(timeIntervalSince1970: 101))
        }

        let shortSignature = PairingInvitation(
            id: validInvitation.id,
            endpointID: validInvitation.endpointID,
            macPublicKeys: validInvitation.macPublicKeys,
            oneTimeSecret: validInvitation.oneTimeSecret,
            createdAt: validInvitation.createdAt,
            expiresAt: validInvitation.expiresAt,
            signature: Data([1, 2, 3])
        )
        #expect(throws: PairingError.invalidInvitationSignature) {
            try PairingInvitationVerification.verify(shortSignature, now: Date(timeIntervalSince1970: 101))
        }
    }

    @Test("authority rejects adversarial candidates")
    func authorityRejectsAdversarialCandidates() async throws {
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: SymmetricKey(size: .bits256)
        )
        let phoneKeys = DevicePrivateKeys()
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )

        let unknownCandidate = PairingCandidate(
            invitationID: "unknown-invitation-id",
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            publicKeys: phoneKeys.publicKeys,
            createdAt: Date(timeIntervalSince1970: 101),
            invitationProof: Data(repeating: 0, count: 32)
        )
        await #expect(throws: PairingError.unknownInvitation) {
            try await authority.approve(unknownCandidate, now: Date(timeIntervalSince1970: 102))
        }

        let forgedProofCandidate = PairingCandidate(
            invitationID: invitation.id,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            publicKeys: phoneKeys.publicKeys,
            createdAt: Date(timeIntervalSince1970: 101),
            invitationProof: Data(repeating: 0xaa, count: 32)
        )
        await #expect(throws: PairingError.invalidInvitationProof) {
            try await authority.approve(forgedProofCandidate, now: Date(timeIntervalSince1970: 102))
        }

        let badSigningKeyCandidate = PairingCandidate(
            invitationID: invitation.id,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            publicKeys: DevicePublicKeys(signing: Data([1, 2, 3]), agreement: phoneKeys.publicKeys.agreement),
            createdAt: Date(timeIntervalSince1970: 101),
            invitationProof: Data(repeating: 0, count: 32)
        )
        await #expect(throws: PairingError.invalidPublicKey) {
            try await authority.approve(badSigningKeyCandidate, now: Date(timeIntervalSince1970: 102))
        }

        let badAgreementKeyCandidate = PairingCandidate(
            invitationID: invitation.id,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            publicKeys: DevicePublicKeys(signing: phoneKeys.publicKeys.signing, agreement: Data([1, 2, 3])),
            createdAt: Date(timeIntervalSince1970: 101),
            invitationProof: Data(repeating: 0, count: 32)
        )
        await #expect(throws: PairingError.invalidPublicKey) {
            try await authority.approve(badAgreementKeyCandidate, now: Date(timeIntervalSince1970: 102))
        }

        let emptyDeviceIDCandidate = PairingCandidate(
            invitationID: invitation.id,
            deviceID: CompanionDeviceID(""),
            displayName: "iPhone",
            publicKeys: phoneKeys.publicKeys,
            createdAt: Date(timeIntervalSince1970: 101),
            invitationProof: Data(repeating: 0, count: 32)
        )
        await #expect(throws: PairingError.invalidPublicKey) {
            try await authority.approve(emptyDeviceIDCandidate, now: Date(timeIntervalSince1970: 102))
        }
    }

    @Test("key wrapping unwrap rejects invalid keys and tampered ciphertexts")
    func keyWrappingUnwrapRejectsInvalidKeysAndTamperedCiphertexts() async throws {
        let originalContentKey = SymmetricKey(size: .bits256)
        let authority = PairingAuthority(
            endpointID: EndpointID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            contentKey: originalContentKey
        )
        let phoneKeys = DevicePrivateKeys()
        let invitation = await authority.makeInvitation(
            now: Date(timeIntervalSince1970: 100)
        )
        let candidate = try PairingCandidate.make(
            invitation: invitation,
            deviceID: CompanionDeviceID("phone-1"),
            displayName: "iPhone",
            keys: phoneKeys,
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let approval = try await authority.approve(
            candidate,
            now: Date(timeIntervalSince1970: 102)
        )

        let badMacKeyApproval = DeviceApproval(
            invitationID: approval.invitationID,
            deviceID: approval.deviceID,
            verificationPhrase: approval.verificationPhrase,
            wrappedContentKey: approval.wrappedContentKey,
            macAgreementPublicKey: Data([1, 2, 3])
        )
        #expect(throws: PairingError.invalidPublicKey) {
            try ContentKeyWrapping.unwrap(
                badMacKeyApproval,
                invitationSecret: invitation.oneTimeSecret,
                phoneAgreementKey: phoneKeys.agreement
            )
        }

        var tamperedCiphertext = approval.wrappedContentKey
        tamperedCiphertext[tamperedCiphertext.count - 1] ^= 0xff
        let tamperedApproval = DeviceApproval(
            invitationID: approval.invitationID,
            deviceID: approval.deviceID,
            verificationPhrase: approval.verificationPhrase,
            wrappedContentKey: tamperedCiphertext,
            macAgreementPublicKey: approval.macAgreementPublicKey
        )
        #expect(throws: PairingError.keyAgreementFailed) {
            try ContentKeyWrapping.unwrap(
                tamperedApproval,
                invitationSecret: invitation.oneTimeSecret,
                phoneAgreementKey: phoneKeys.agreement
            )
        }

        let truncatedApproval = DeviceApproval(
            invitationID: approval.invitationID,
            deviceID: approval.deviceID,
            verificationPhrase: approval.verificationPhrase,
            wrappedContentKey: Data([1, 2, 3]),
            macAgreementPublicKey: approval.macAgreementPublicKey
        )
        #expect(throws: PairingError.malformedWrappedKey) {
            try ContentKeyWrapping.unwrap(
                truncatedApproval,
                invitationSecret: invitation.oneTimeSecret,
                phoneAgreementKey: phoneKeys.agreement
            )
        }

        #expect(throws: PairingError.keyAgreementFailed) {
            try ContentKeyWrapping.unwrap(
                approval,
                invitationSecret: Data(repeating: 0xff, count: 32),
                phoneAgreementKey: phoneKeys.agreement
            )
        }
    }
}
