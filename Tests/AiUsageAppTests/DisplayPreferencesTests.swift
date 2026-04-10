import Foundation
import Testing
@testable import AiUsageApp

struct DisplayPreferencesTests {
    @Test
    func providersAreVisibleByDefaultWhenNoHiddenOverridesExist() throws {
        let data = Data(
            """
            {
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.visibleProviders == Set(ProviderID.allCases))
    }

    @Test
    func explicitHiddenProvidersStayHidden() throws {
        let data = Data(
            """
            {
              "hiddenProviders": ["codex"],
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.visibleProviders.contains(.codex) == false)
        #expect(preferences.visibleProviders.contains(.copilot))
    }
}
