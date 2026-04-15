import Foundation
import Testing
@testable import AiUsageApp

struct CodexLocalAuthTests {
    @Test
    func parsesCodexOAuthAuthFile() throws {
        let data = Data(
            """
            {
              "last_refresh": "2026-04-01T12:00:00Z",
              "tokens": {
                "access_token": "access-token",
                "refresh_token": "refresh-token",
                "id_token": "id-token",
                "account_id": "account-123"
              }
            }
            """.utf8
        )

        let credentials = try CodexOAuthCredentialsStore.parse(data: data)

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.idToken == "id-token")
        #expect(credentials.accountId == "account-123")
        #expect(credentials.lastRefresh != nil)
    }

    @Test
    func parsesOpenAIAPIKeyFallback() throws {
        let data = Data(
            """
            {
              "OPENAI_API_KEY": "sk-test-123"
            }
            """.utf8
        )

        let credentials = try CodexOAuthCredentialsStore.parse(data: data)

        #expect(credentials.accessToken == "sk-test-123")
        #expect(credentials.refreshToken.isEmpty)
        #expect(credentials.accountId == nil)
    }
}
