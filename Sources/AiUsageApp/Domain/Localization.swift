import Foundation

enum L10nKey: String, CaseIterable {
    case menuBarAppName
    case notConfigured
    case unavailable
    case usagePanelTitle
    case settingsTitle
    case lastUpdate
    case refreshNow
    case openSettings
    case staleData
    case authenticationRequired
    case authenticateInSettings
    case generalSection
    case appearanceSection
    case menuBarSection
    case mainPanelSection
    case notificationsSection
    case usageNotificationsSection
    case earlyResetNotificationsSection
    case scheduledResetNotificationsSection
    case language
    case refreshInterval
    case usagePanelBackground
    case usagePanelBackgroundRegularMaterial
    case usagePanelBackgroundSolidAdaptive
    case usageBarColors
    case usageBarColorsDefault
    case usageBarColorsSystemAccent
    case codexMenuBarMetric
    case claudeMenuBarMetric
    case showCodexCredits
    case showCodexLimitResets
    case hideUnavailableCodexUsageLimits
    case showCodexSparkUsage
    case optionalMetricAlways
    case optionalMetricOnlyWhenAboveZero
    case optionalMetricNever
    case menuBarMetricWeekly
    case menuBarMetricFiveHour
    case menuBarIcons
    case usagePanelProviders
    case notificationsAhead
    case notificationsBehind
    case notificationsCodexReset
    case notificationsClaudeReset
    case notificationsCodexScheduledReset
    case notificationsClaudeScheduledReset
    case providerCodex
    case providerClaude
    case providerCopilot
    case enabled
    case percentageShown
    case usageLimitFiveHourCodexSpark
    case usageLimitWeeklyCodexSpark
    case usageLimitFiveHour
    case usageLimitWeekly
    case usageLimitMonthly
    case usageMetricCredits
    case usageMetricLimitResets
    case resetAt
    case save
    case cancel
    case signInToCodex
    case signInToGitHubCopilot
    case copilotToken
    case fetchFailed
    case signedOut
    case connected
    case accountsSection
    case codexSessionHelp
    case codexCliConnected
    case claudeSessionHelp
    case claudeCliConnected
    case copilotPatHelp
    case copilotDeviceFlowWaiting
    case copilotDeviceFlowConnected
    case saveAndRefresh
    case reload
    case tokenSaved
    case openCodexAndSignIn
    case openGitHubCopilotAndSignIn
    case settingsTabAccounts
    case settingsTabDisplay
    case settingsTabNotifications
    case settingsTabLogs
    case settingsTabAbout
    case providerStatusOk
    case providerStatusNeedsAttention
    case saveSession
    case copilotPlanHelp
    case copilotConnectedHelp
    case notificationsAheadDescription
    case notificationsBehindDescription
    case notificationsCodexResetDescription
    case notificationsClaudeResetDescription
    case notificationsCodexScheduledResetDescription
    case notificationsClaudeScheduledResetDescription
    case notificationTitleAheadFormat
    case notificationTitleBehindFormat
    case notificationBodyScheduleFormat
    case notificationTitleCodexReset
    case notificationTitleClaudeReset
    case notificationTitleCodexScheduledReset
    case notificationTitleClaudeScheduledReset
    case notificationBodyResetFormat
    case notificationBodyScheduledResetFormat
    case notificationActionPreheat
    case notificationMetricFiveHourFormat
    case notificationMetricWeeklyFormat
    case notificationMetricMonthlyFormat
    case notificationMetricCreditsFormat
    case copyLogs
    case clearLogs
    case noLogs
    case logsCopied
    case appVersion
    case checkForUpdates
    case checkingForUpdates
    case updateUpToDate
    case updateAvailableFormat
    case viewRelease
    case updateCheckFailed
    case automaticallyCheckForUpdates
    case automaticallyCheckForUpdatesDescription
    case updateNotificationTitleFormat
    case updateNotificationBody
    case projectSection
    case projectRepository
    case sponsor
    case reportIssue
    case legalSection
    case logoDisclaimer
    case quitApp
    case menuActionRefresh
    case menuActionSettings
    case signOut
    case noGitHubCopilotSessionFound
    case noCodexSessionFound
    case internetConnectionOffline
}

struct Localizer {
    private let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    func text(_ key: L10nKey) -> String {
        let translations = TranslationCatalog.translations(for: language)

        if let text = translations[key] {
            return text
        }

        return TranslationCatalog.english[key] ?? key.rawValue
    }

    func formatted(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.locale, arguments: arguments)
    }

    func errorDescription(_ description: String) -> String {
        switch description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "the internet connection appears to be offline.":
            return text(.internetConnectionOffline)
        default:
            return description
        }
    }

    func codexMenuBarMetricLabel(_ metric: CodexMenuBarMetric) -> String {
        switch metric {
        case .weekly:
            return text(.menuBarMetricWeekly)
        case .fiveHour:
            return text(.menuBarMetricFiveHour)
        }
    }

    func claudeMenuBarMetricLabel(_ metric: ClaudeMenuBarMetric) -> String {
        switch metric {
        case .weekly:
            return text(.menuBarMetricWeekly)
        case .fiveHour:
            return text(.menuBarMetricFiveHour)
        }
    }

    func optionalMetricVisibilityLabel(_ visibility: OptionalMetricVisibility) -> String {
        switch visibility {
        case .always:
            return text(.optionalMetricAlways)
        case .onlyWhenAboveZero:
            return text(.optionalMetricOnlyWhenAboveZero)
        case .never:
            return text(.optionalMetricNever)
        }
    }

    func metricTitle(for kind: UsageMetricKind) -> String {
        switch kind {
        case .codexFiveHour, .claudeFiveHour:
            return text(.usageLimitFiveHour)
        case .codexWeekly, .claudeWeekly:
            return text(.usageLimitWeekly)
        case .codexSparkFiveHour:
            return text(.usageLimitFiveHourCodexSpark)
        case .codexSparkWeekly:
            return text(.usageLimitWeeklyCodexSpark)
        case .codexCredits:
            return text(.usageMetricCredits)
        case .codexLimitResets:
            return text(.usageMetricLimitResets)
        case .copilotMonthly:
            return text(.usageLimitMonthly)
        }
    }

    func notificationMetricName(for kind: UsageMetricKind) -> String {
        let providerName = notificationProviderName(for: kind.provider)

        switch kind {
        case .codexFiveHour, .claudeFiveHour:
            return formatted(.notificationMetricFiveHourFormat, providerName)
        case .codexWeekly:
            return formatted(.notificationMetricWeeklyFormat, providerName)
        case .codexSparkFiveHour:
            return text(.usageLimitFiveHourCodexSpark)
        case .codexSparkWeekly:
            return text(.usageLimitWeeklyCodexSpark)
        case .codexCredits:
            return formatted(.notificationMetricCreditsFormat, providerName)
        case .codexLimitResets:
            return text(.usageMetricLimitResets)
        case .claudeWeekly:
            return formatted(.notificationMetricWeeklyFormat, providerName)
        case .copilotMonthly:
            return formatted(.notificationMetricMonthlyFormat, providerName)
        }
    }

    private func notificationProviderName(for provider: ProviderID) -> String {
        switch provider {
        case .codex:
            return text(.providerCodex)
        case .claude:
            return text(.providerClaude)
        case .copilot:
            return text(.providerCopilot)
        }
    }
}

enum TranslationCatalog {
    static let all: [AppLanguage: [L10nKey: String]] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { language in
            (language, load(language: language))
        }
    )

    static let english = all[.englishUS] ?? [:]

    static func translations(for language: AppLanguage) -> [L10nKey: String] {
        all[language] ?? [:]
    }

    private static func load(language: AppLanguage) -> [L10nKey: String] {
        let fileName = language.localizationFileName
        let bundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("Localization", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../shared/localization", isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent(fileName, isDirectory: false)

        for url in [bundleURL, sourceURL].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let rawCatalog = try? JSONDecoder().decode([String: String].self, from: data) else {
                continue
            }

            return Dictionary(uniqueKeysWithValues: rawCatalog.compactMap { rawKey, value in
                L10nKey(rawValue: rawKey).map { ($0, value) }
            })
        }

        return [:]
    }
}

private extension AppLanguage {
    var localizationFileName: String {
        switch self {
        case .englishUS:
            return "en-US.json"
        case .polish:
            return "pl-PL.json"
        case .spanish:
            return "es-ES.json"
        case .german:
            return "de-DE.json"
        case .french:
            return "fr-FR.json"
        case .japanese:
            return "ja-JP.json"
        case .portugueseBrazil:
            return "pt-BR.json"
        }
    }
}
