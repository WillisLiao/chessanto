import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Testing
@testable import CompanionCloudKit

@Suite("Secure companion CloudKit mailbox")
struct SecureCompanionCloudMailboxTests {
    @Test("signed envelope header must match the outer CloudKit record")
    func signedHeaderMustMatchOuterRecord() async throws {
        let transport = RecordingCloudTransport()
        let signingKey = Curve25519.Signing.PrivateKey()
        let contentKey = SymmetricKey(size: .bits256)
        let sender = SecureCompanionCloudMailbox(
            senderDeviceID: CompanionDeviceID("phone-1"),
            signingKey: signingKey,
            contentKey: contentKey,
            transport: transport
        ) { _ in nil }
        try await sender.send(
            .gameCatalog(
                GameCatalogSnapshot(
                    protocolVersion: .v1,
                    endpointID: EndpointID("mac-1"),
                    version: 1,
                    generatedAt: Date(timeIntervalSince1970: 100),
                    games: []
                )
            ),
            to: EndpointID("mac-1")
        )
        let original = try #require(await transport.lastRecord)
        let tampered = CompanionCloudRecord(
            recordName: "attacker-controlled-record-name",
            type: original.type,
            queryableFields: original.queryableFields,
            encryptedFields: original.encryptedFields,
            encryptedAsset: original.encryptedAsset
        )
        let receiver = SecureCompanionCloudMailbox(
            senderDeviceID: CompanionDeviceID("mac-1"),
            signingKey: Curve25519.Signing.PrivateKey(),
            contentKey: contentKey,
            transport: RecordingCloudTransport()
        ) { candidate in
            candidate == CompanionDeviceID("phone-1")
                ? signingKey.publicKey
                : nil
        }

        await #expect(
            throws: SecureCompanionCloudMailboxError
                .mismatchedAuthenticatedHeader
        ) {
            try await receiver.receive(
                tampered,
                expectedRecipient: EndpointID("mac-1")
            )
        }
    }
}

private actor RecordingCloudTransport: CompanionCloudRecordTransport {
    private(set) var lastRecord: CompanionCloudRecord?

    func enqueue(_ record: CompanionCloudRecord) {
        lastRecord = record
    }
}
