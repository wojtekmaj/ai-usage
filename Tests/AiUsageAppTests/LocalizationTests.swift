import Testing
@testable import AiUsageApp

struct LocalizationTests {
    @Test
    func allSupportedLanguagesHaveCopyForEveryKey() {
        let expectedKeys = Set(L10nKey.allCases)

        for language in AppLanguage.allCases {
            let translationKeys = Set(TranslationCatalog.translations(for: language).keys)
            let localizer = Localizer(language: language)

            #expect(translationKeys == expectedKeys)

            for key in L10nKey.allCases {
                let text = localizer.text(key)

                #expect(!text.isEmpty)
                #expect(text != key.rawValue)
            }
        }
    }

    @Test
    func supportedLanguagesExposeNativePickerNames() {
        #expect(AppLanguage.allCases.map(\.displayName) == [
            "English (US)",
            "Polski",
            "Español",
            "Deutsch",
            "Français",
            "日本語",
            "Português (Brasil)",
        ])
    }

    @Test
    func sharedUsageLimitTitlesStayConsistentAcrossProviders() {
        let english = Localizer(language: .englishUS)
        let polish = Localizer(language: .polish)

        #expect(english.metricTitle(for: .codexFiveHour) == "5-hour usage limit")
        #expect(english.metricTitle(for: .claudeFiveHour) == "5-hour usage limit")
        #expect(english.metricTitle(for: .codexSparkFiveHour) == "GPT-5.3-Codex-Spark 5-hour usage limit")
        #expect(polish.metricTitle(for: .codexFiveHour) == "5-godzinny limit wykorzystania")
        #expect(polish.metricTitle(for: .claudeFiveHour) == "5-godzinny limit wykorzystania")
        #expect(polish.metricTitle(for: .codexSparkWeekly) == "Tygodniowy limit wykorzystania GPT-5.3-Codex-Spark")
    }

    @Test
    func notificationMetricNamesInjectProviderSpecificLabels() {
        let english = Localizer(language: .englishUS)
        let polish = Localizer(language: .polish)

        #expect(english.notificationMetricName(for: .claudeFiveHour) == "Claude Code 5-hour window")
        #expect(english.notificationMetricName(for: .claudeWeekly) == "Claude Code weekly window")
        #expect(english.notificationMetricName(for: .copilotMonthly) == "GitHub Copilot monthly quota")
        #expect(polish.notificationMetricName(for: .claudeFiveHour) == "5-godzinne okno Claude Code")
        #expect(polish.notificationMetricName(for: .claudeWeekly) == "Tygodniowe okno Claude Code")
        #expect(polish.notificationMetricName(for: .copilotMonthly) == "Miesięczny limit GitHub Copilot")
    }

    @Test
    func menuBarMetricLabelsReuseSharedWindowCopy() {
        let english = Localizer(language: .englishUS)
        let polish = Localizer(language: .polish)

        #expect(english.codexMenuBarMetricLabel(.fiveHour) == "5-hour usage")
        #expect(english.claudeMenuBarMetricLabel(.weekly) == "Weekly usage")
        #expect(polish.codexMenuBarMetricLabel(.weekly) == "Użycie tygodniowe")
        #expect(polish.claudeMenuBarMetricLabel(.weekly) == "Użycie tygodniowe")
        #expect(polish.claudeMenuBarMetricLabel(.fiveHour) == "Użycie 5-godzinne")
    }

    @Test
    func knownSystemErrorsUseSelectedLanguage() {
        let english = Localizer(language: .englishUS)
        let polish = Localizer(language: .polish)

        #expect(english.errorDescription("The Internet connection appears to be offline.") == "The internet connection appears to be offline.")
        #expect(polish.errorDescription("The Internet connection appears to be offline.") == "Wygląda na to, że połączenie z internetem jest offline.")
    }
}
