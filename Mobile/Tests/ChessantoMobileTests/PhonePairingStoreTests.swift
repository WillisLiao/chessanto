import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Testing
@testable import ChessantoMobile

@Suite("Phone pairing store")
struct PhonePairingStoreTests {
    @Test("identity generates new keys on first launch and persists them")
    func identityGeneratesAndPersists() async throws {
        let mockSecrets = MockSecretStore()
        let store = PhonePairingStore(secrets: mockSecrets)

        let firstIdentity = try await store.identity()
        #expect(!firstIdentity.deviceID.rawValue.isEmpty)

        let secondIdentity = try await store.identity()
        #expect(secondIdentity.deviceID == firstIdentity.deviceID)
        #expect(
            secondIdentity.keys.signing.publicKey.rawRepresentation
                == firstIdentity.keys.signing.publicKey.rawRepresentation
        )
        #expect(
            secondIdentity.keys.agreement.publicKey.rawRepresentation
                == firstIdentity.keys.agreement.publicKey.rawRepresentation
        )
    }

    @Test("pairing lifecycle saves invitation, completes approval, and resets cleanly")
    func pairingLifecycle() async throws {
        let mockSecrets = MockSecretStore()
        let store = PhonePairingStore(secrets: mockSecrets)

        #expect(try await store.invitation() == nil)
        #expect(try await store.pairing() == nil)

        let invitation = PairingInvitation(
            id: "invitation-1",
            endpointID: EndpointID("mac-1"),
            macPublicKeys: DevicePublicKeys(
                signing: Data(repeating: 1, count: 32),
                agreement: Data(repeating: 2, count: 32)
            ),
            oneTimeSecret: Data(repeating: 3, count: 32),
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 400),
            signature: Data(repeating: 4, count: 64)
        )
        try await store.saveInvitation(invitation)
        #expect(try await store.invitation() == invitation)

        let contentKey = SymmetricKey(size: .bits256)
        let approval = DeviceApproval(
            invitationID: "invitation-1",
            deviceID: CompanionDeviceID("phone-1"),
            verificationPhrase: "amber bishop cedar delta",
            wrappedContentKey: Data(repeating: 5, count: 48),
            macAgreementPublicKey: Data(repeating: 6, count: 32)
        )
        try await store.complete(approval: approval, contentKey: contentKey)

        let stored = try await #require(try await store.pairing())
        #expect(stored.invitation == invitation)
        #expect(stored.approval == approval)
        let originalKeyData = contentKey.withUnsafeBytes { Data($0) }
        let storedKeyData = stored.contentKey.withUnsafeBytes { Data($0) }
        #expect(storedKeyData == originalKeyData)

        try await store.resetPairing()
        #expect(try await store.invitation() == nil)
        #expect(try await store.pairing() == nil)
    }
}

private final class MockSecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        storage[account] = data
    }

    func load(account: String) throws -> Data? {
        storage[account]
    }

    func remove(account: String) throws {
        storage.removeValue(forKey: account)
    }
}
