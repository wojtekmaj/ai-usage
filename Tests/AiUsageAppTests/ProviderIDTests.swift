import Foundation
import Testing
@testable import AiUsageApp

struct ProviderIDTests {
    @Test
    func usageSettingsURLsMatchExpectedDestinations() {
        #expect(ProviderID.codex.usageSettingsURL == URL(string: "https://chatgpt.com/codex/cloud/settings/usage"))
        #expect(ProviderID.copilot.usageSettingsURL == URL(string: "https://github.com/settings/billing"))
    }
}
