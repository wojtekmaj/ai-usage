import Foundation

@MainActor
final class ClaudeSessionStore {
    private let loadCredentials: () throws -> String?
    private let saveCredentials: (String, Bool) throws -> Void
    private var cached: String?
    private var persisted: String?

    init(keychain: KeychainStore) {
        loadCredentials = { try keychain.loadString(account: "claude.oauth-session", allowInteraction: false) }
        saveCredentials = { try keychain.save(string: $0, account: "claude.oauth-session", allowInteraction: $1) }
    }

    init(load: @escaping () throws -> String?, save: @escaping (String) throws -> Void) {
        loadCredentials = load
        saveCredentials = { credentials, _ in try save(credentials) }
    }

    func load() throws -> String? {
        if let cached {
            return cached
        }

        let credentials = try loadCredentials()
        cached = credentials
        persisted = credentials

        return credentials
    }

    func save(_ credentials: String, allowInteraction: Bool = false) throws {
        // Keep rotated tokens in memory if the vault is temporarily unavailable
        cached = credentials
        guard persisted != credentials else {
            return
        }

        try saveCredentials(credentials, allowInteraction)
        persisted = credentials
    }
}
