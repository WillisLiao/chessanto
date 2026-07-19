import Testing
@testable import CompanionCloudKit

@Suite("Companion CloudKit provisioning")
struct CompanionCloudKitProvisioningTests {
    @Test("missing configuration blocks CloudKit before container creation")
    func missingConfiguration() {
        #expect(
            CompanionCloudKitProvisioning.containerIdentifier(
                infoDictionary: [:]
            ) == nil
        )
    }

    @Test("only an explicit iCloud container identifier is accepted")
    func explicitConfiguration() {
        #expect(
            CompanionCloudKitProvisioning.containerIdentifier(
                infoDictionary: [
                    CompanionCloudKitProvisioning.infoDictionaryKey:
                        "iCloud.com.example.chessanto"
                ]
            ) == "iCloud.com.example.chessanto"
        )
        #expect(
            CompanionCloudKitProvisioning.containerIdentifier(
                infoDictionary: [
                    CompanionCloudKitProvisioning.infoDictionaryKey:
                        "com.example.not-a-container"
                ]
            ) == nil
        )
    }
}
