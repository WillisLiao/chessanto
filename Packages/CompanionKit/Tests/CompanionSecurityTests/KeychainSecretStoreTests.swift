import Foundation
import Testing
@testable import CompanionSecurity

@Suite("Companion Keychain storage")
struct KeychainSecretStoreTests {
    @Test("private device material round trips through Keychain")
    func privateDeviceMaterialRoundTripsThroughKeychain() throws {
        let service = "com.chessanto.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let account = "phone-signing-private-key"
        let secret = Data("private-material".utf8)
        defer { try? store.remove(account: account) }

        try store.save(secret, account: account)

        #expect(try store.load(account: account) == secret)
        try store.remove(account: account)
        #expect(try store.load(account: account) == nil)
    }
}
