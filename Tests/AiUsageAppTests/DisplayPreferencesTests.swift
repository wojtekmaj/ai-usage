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
        #expect(preferences.visiblePanelProviders == Set(ProviderID.allCases))
        #expect(preferences.claudeMenuBarMetric == .weeklyQuota)
        #expect(preferences.usagePanelBackgroundStyle == .regularMaterial)
    }

    @Test
    func explicitHiddenProvidersStayHiddenWhilePanelDefaultsStayVisible() throws {
        let data = Data(
            """
            {
              "hiddenProviders": ["copilot"],
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly",
              "claudeMenuBarMetric": "dailyCost"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.visibleProviders.contains(.copilot) == false)
        #expect(preferences.visibleProviders.contains(.codex))
        #expect(preferences.visibleProviders.contains(.claude))
        #expect(preferences.visiblePanelProviders == Set(ProviderID.allCases))
        #expect(preferences.claudeMenuBarMetric == .dailyCost)
        #expect(preferences.usagePanelBackgroundStyle == .regularMaterial)
    }

    @Test
    func explicitHiddenPanelProvidersStayHidden() throws {
        let data = Data(
            """
            {
              "hiddenPanelProviders": ["copilot"],
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly",
              "claudeMenuBarMetric": "weeklyQuota"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.visibleProviders == Set(ProviderID.allCases))
        #expect(preferences.visiblePanelProviders.contains(.claude))
        #expect(preferences.visiblePanelProviders.contains(.codex))
        #expect(preferences.visiblePanelProviders.contains(.copilot) == false)
    }

    @Test
    func explicitBackgroundStyleIsDecoded() throws {
        let data = Data(
            """
            {
              "showAheadNotifications": true,
              "showBehindNotifications": false,
              "showCodexResetNotifications": true,
              "refreshIntervalMinutes": 5,
              "language": "englishUS",
              "codexMenuBarMetric": "weekly",
              "claudeMenuBarMetric": "weeklyQuota",
              "usagePanelBackgroundStyle": "solidAdaptive"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(DisplayPreferences.self, from: data)

        #expect(preferences.usagePanelBackgroundStyle == .solidAdaptive)
    }
}
