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
        #expect(preferences.claudeMenuBarMetric == .weekly)
    }

    @Test
    func explicitHiddenProvidersStayHidden() throws {
        let data = Data(
            """
            {
              "hiddenProviders": ["claude"],
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly",
              "claudeMenuBarMetric": "fiveHour"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.visibleProviders.contains(.claude) == false)
        #expect(preferences.visibleProviders.contains(.codex))
        #expect(preferences.visibleProviders.contains(.copilot))
        #expect(preferences.claudeMenuBarMetric == .fiveHour)
    }
}
