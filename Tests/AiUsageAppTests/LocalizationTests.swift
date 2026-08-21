import Testing
@testable import AiUsageApp

struct LocalizationTests {
    @Test
    func allSupportedLanguagesHaveTheSameKeys() {
        let expectedKeys = Set(TranslationCatalog.english.keys)

        for language in AppLanguage.allCases {
            let translationKeys = Set(TranslationCatalog.translations(for: language).keys)

            #expect(missingKeys(in: translationKeys, expectedKeys: expectedKeys).isEmpty)
            #expect(extraKeys(in: translationKeys, expectedKeys: expectedKeys).isEmpty)
        }
    }

    @Test
    func allLocalizationKeysHaveCopy() {
        let expectedKeys = Set(L10nKey.allCases)

        for language in AppLanguage.allCases {
            let translationKeys = Set(TranslationCatalog.translations(for: language).keys)

            #expect(missingKeys(in: translationKeys, expectedKeys: expectedKeys).isEmpty)
            #expect(extraKeys(in: translationKeys, expectedKeys: expectedKeys).isEmpty)
        }
    }

    @Test
    func allSupportedLanguagesHaveNonEmptyCopy() {
        for language in AppLanguage.allCases {
            let localizer = Localizer(language: language)

            for key in L10nKey.allCases {
                let text = localizer.text(key)

                #expect(!text.isEmpty)
                #expect(text != key.rawValue)
            }
        }
    }

    private func missingKeys(in actualKeys: Set<L10nKey>, expectedKeys: Set<L10nKey>) -> [String] {
        expectedKeys
            .subtracting(actualKeys)
            .map(\.rawValue)
            .sorted()
    }

    private func extraKeys(in actualKeys: Set<L10nKey>, expectedKeys: Set<L10nKey>) -> [String] {
        actualKeys
            .subtracting(expectedKeys)
            .map(\.rawValue)
            .sorted()
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
        #expect(english.metricTitle(for: .codexWeekly) == "Weekly usage limit")
        #expect(english.metricTitle(for: .claudeWeekly) == "Weekly usage limit")
        #expect(english.metricTitle(for: .codexSparkFiveHour) == "GPT-5.3-Codex-Spark 5-hour usage limit")
        #expect(polish.metricTitle(for: .codexFiveHour) == "5-godzinny limit wykorzystania")
        #expect(polish.metricTitle(for: .claudeFiveHour) == "5-godzinny limit wykorzystania")
        #expect(polish.metricTitle(for: .codexWeekly) == "Tygodniowy limit wykorzystania")
        #expect(polish.metricTitle(for: .claudeWeekly) == "Tygodniowy limit wykorzystania")
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
