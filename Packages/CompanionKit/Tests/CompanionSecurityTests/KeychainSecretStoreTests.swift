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

    @Test("loading nonexistent account returns nil and removing it succeeds cleanly")
    func loadingNonexistentAccountReturnsNil() throws {
        let service = "com.chessanto.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let account = "nonexistent-account"

        #expect(try store.load(account: account) == nil)
        #expect(throws: Never.self) {
            try store.remove(account: account)
        }
    }

    @Test("updating account overwrites secret and preserves accessibility")
    func updatingAccountOverwritesSecret() throws {
        let service = "com.chessanto.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let account = "rotating-secret"
        let secret1 = Data("first-secret".utf8)
        let secret2 = Data("second-secret".utf8)
        defer { try? store.remove(account: account) }

        try store.save(secret1, account: account)
        #expect(try store.load(account: account) == secret1)

        try store.save(secret2, account: account)
        #expect(try store.load(account: account) == secret2)
    }

    @Test("distinct accounts are isolated within the same service")
    func distinctAccountsAreIsolated() throws {
        let service = "com.chessanto.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let accountA = "account-a"
        let accountB = "account-b"
        let secretA = Data("secret-a".utf8)
        let secretB = Data("secret-b".utf8)
        defer {
            try? store.remove(account: accountA)
            try? store.remove(account: accountB)
        }

        try store.save(secretA, account: accountA)
        try store.save(secretB, account: accountB)

        #expect(try store.load(account: accountA) == secretA)
        #expect(try store.load(account: accountB) == secretB)

        try store.remove(account: accountA)
        #expect(try store.load(account: accountA) == nil)
        #expect(try store.load(account: accountB) == secretB)
    }
}
