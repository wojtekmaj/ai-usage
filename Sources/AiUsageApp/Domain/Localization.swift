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
    case language
    case refreshInterval
    case usagePanelBackground
    case usagePanelBackgroundRegularMaterial
    case usagePanelBackgroundSolidAdaptive
    case codexMenuBarMetric
    case claudeMenuBarMetric
    case showCodexSparkUsage
    case menuBarMetricWeekly
    case menuBarMetricFiveHour
    case menuBarIcons
    case usagePanelProviders
    case notificationsAhead
    case notificationsBehind
    case notificationsCodexReset
    case notificationsClaudeReset
    case providerCodex
    case providerClaude
    case providerCopilot
    case enabled
    case percentageShown
    case usageLimitFiveHourCodexSpark
    case usageLimitWeeklyCodexSpark
    case usageLimitFiveHour
    case usageLimitWeekly
    case usageLimitSevenDay
    case usageLimitMonthly
    case usageMetricCredits
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
    case notificationTitleAheadFormat
    case notificationTitleBehindFormat
    case notificationBodyScheduleFormat
    case notificationTitleCodexReset
    case notificationTitleClaudeReset
    case notificationBodyResetFormat
    case notificationMetricFiveHourFormat
    case notificationMetricWeeklyFormat
    case notificationMetricMonthlyFormat
    case notificationMetricCreditsFormat
    case copyLogs
    case clearLogs
    case noLogs
    case logsCopied
    case appVersion
    case projectSection
    case projectRepository
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

    func metricTitle(for kind: UsageMetricKind) -> String {
        switch kind {
        case .codexFiveHour, .claudeFiveHour:
            return text(.usageLimitFiveHour)
        case .codexWeekly:
            return text(.usageLimitWeekly)
        case .codexSparkFiveHour:
            return text(.usageLimitFiveHourCodexSpark)
        case .codexSparkWeekly:
            return text(.usageLimitWeeklyCodexSpark)
        case .codexCredits:
            return text(.usageMetricCredits)
        case .claudeWeekly:
            return text(.usageLimitSevenDay)
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
    static let all: [AppLanguage: [L10nKey: String]] = [
        .englishUS: english,
        .polish: polish,
        .spanish: spanish,
        .german: german,
        .french: french,
        .japanese: japanese,
        .portugueseBrazil: portugueseBrazil,
    ]

    static func translations(for language: AppLanguage) -> [L10nKey: String] {
        all[language] ?? [:]
    }
}
