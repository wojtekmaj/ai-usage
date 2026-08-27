import Foundation
import Testing
@testable import AiUsageApp

struct ClaudeLocalAuthTests {
    @Test
    func parsesClaudeOAuthCredentials() throws {
        let data = Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "sk-ant-oat-123",
                "expiresAt": 1770000000000,
                "scopes": ["user:profile", "user:inference"],
                "rateLimitTier": "claude_max"
              }
            }
            """.utf8
        )

        let credentials = try ClaudeOAuthCredentialsStore.parse(data: data)

        #expect(credentials.accessToken == "sk-ant-oat-123")
        #expect(credentials.scopes.contains("user:profile"))
        #expect(credentials.rateLimitTier == "claude_max")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_770_000_000))
    }

    @Test
    func resolvesClaudeConfigDirectoryFromEnvironment() {
        let url = ClaudeOAuthCredentialsStore.authFileURL(
            env: ["CLAUDE_CONFIG_DIR": "/tmp/custom-claude,/tmp/ignored"],
            fileManager: .default
        )

        #expect(url.path == "/tmp/custom-claude/.credentials.json")
    }

    @Test
    func cachesClaudeCredentialsAfterFirstLoad() throws {
        let data = Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "sk-ant-oat-123"
              }
            }
            """.utf8
        )
        var loadCount = 0
        let store = ClaudeOAuthCredentialsStore {
            loadCount += 1
            return data
        }

        #expect(try store.rawJSONString() == String(decoding: data, as: UTF8.self))
        #expect(try store.load().accessToken == "sk-ant-oat-123")
        #expect(loadCount == 1)
    }

    @Test
    func reloadsClaudeCredentialsAfterCacheInvalidation() throws {
        var accessToken = "old-token"
        let store = ClaudeOAuthCredentialsStore {
            Data(
                """
                {
                  "claudeAiOauth": {
                    "accessToken": "\(accessToken)"
                  }
                }
                """.utf8
            )
        }

        #expect(try store.load().accessToken == "old-token")

        accessToken = "new-token"
        store.invalidateCache()

        #expect(try store.load().accessToken == "new-token")
    }

    @Test
    func cachesClaudeCredentialLoadFailure() {
        var loadCount = 0
        let store = ClaudeOAuthCredentialsStore {
            loadCount += 1
            throw ClaudeOAuthCredentialsError.keychainError(errSecAuthFailed)
        }

        #expect(throws: ClaudeOAuthCredentialsError.self) {
            try store.rawJSONString()
        }
        #expect(throws: ClaudeOAuthCredentialsError.self) {
            try store.load()
        }
        #expect(loadCount == 1)
    }

    @Test
    func retriesWhenClaudeCredentialsAreNotAvailableYet() throws {
        let data = Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "sk-ant-oat-123"
              }
            }
            """.utf8
        )
        var loadCount = 0
        let store = ClaudeOAuthCredentialsStore {
            loadCount += 1
            if loadCount == 1 {
                throw ClaudeOAuthCredentialsError.notFound
            }
            return data
        }

        #expect(throws: ClaudeOAuthCredentialsError.self) {
            try store.load()
        }
        #expect(try store.load().accessToken == "sk-ant-oat-123")
        #expect(loadCount == 2)
    }
}
