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
}
