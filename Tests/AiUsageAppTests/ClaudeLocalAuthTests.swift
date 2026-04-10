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
        #expect(credentials.hasUsageScope)
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
}
