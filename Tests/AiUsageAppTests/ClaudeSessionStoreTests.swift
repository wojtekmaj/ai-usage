import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeSessionStoreTests {
    @Test
    func restoresTheSavedSessionAndPersistsRenewedCredentials() throws {
        var saved = "original-session"
        var writes = 0
        let store = ClaudeSessionStore(load: { saved }, save: {
            saved = $0
            writes += 1
        })

        #expect(try store.load() == "original-session")

        try store.save("renewed-session")
        try store.save("renewed-session")

        #expect(saved == "renewed-session")
        #expect(writes == 1)
        #expect(try store.load() == "renewed-session")
    }

    @Test
    func retainsRotatedCredentialsAndRetriesAFailedSave() throws {
        var writable = false
        var saved = "old-session"
        let store = ClaudeSessionStore(load: { saved }, save: {
            guard writable else {
                throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed)
            }

            saved = $0
        })
        #expect(try store.load() == "old-session")

        #expect(throws: KeychainError.self) { try store.save("rotated-session") }
        #expect(try store.load() == "rotated-session")

        writable = true
        try store.save("rotated-session")

        #expect(saved == "rotated-session")
    }
}
