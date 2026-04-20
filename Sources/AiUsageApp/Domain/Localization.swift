import Foundation

enum L10nKey: String {
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
}

struct Localizer {
    private let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    func text(_ key: L10nKey) -> String {
        switch language {
        case .englishUS:
            return english[key] ?? key.rawValue
        case .polish:
            return polish[key] ?? english[key] ?? key.rawValue
        }
    }

    func formatted(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.locale, arguments: arguments)
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

    private var english: [L10nKey: String] {
        [
            .menuBarAppName: "AI Usage",
            .notConfigured: "Not configured",
            .unavailable: "Unavailable",
            .usagePanelTitle: "AI Usage",
            .settingsTitle: "Settings",
            .lastUpdate: "Last update",
            .refreshNow: "Refresh now",
            .openSettings: "Settings",
            .staleData: "Stale data",
            .authenticationRequired: "Authentication required",
            .authenticateInSettings: "Open Settings to authenticate providers.",
            .generalSection: "General",
            .appearanceSection: "Appearance",
            .menuBarSection: "Menu bar",
            .mainPanelSection: "Main panel",
            .notificationsSection: "Notifications",
            .usageNotificationsSection: "Usage notifications",
            .earlyResetNotificationsSection: "Early reset notifications",
            .language: "Language",
            .refreshInterval: "Refresh interval",
            .usagePanelBackground: "Panel background",
            .usagePanelBackgroundRegularMaterial: "Material",
            .usagePanelBackgroundSolidAdaptive: "Solid color",
            .codexMenuBarMetric: "Codex menu bar percentage",
            .claudeMenuBarMetric: "Claude Code menu bar percentage",
            .showCodexSparkUsage: "Show GPT-5.3-Codex-Spark usage",
            .menuBarMetricWeekly: "Weekly usage",
            .menuBarMetricFiveHour: "5-hour usage",
            .menuBarIcons: "Menu bar icons",
            .usagePanelProviders: "Usage panel providers",
            .notificationsAhead: "Ahead-of-schedule alerts",
            .notificationsBehind: "Behind-schedule alerts",
            .notificationsCodexReset: "Codex early reset alerts",
            .notificationsClaudeReset: "Claude Code early reset alerts",
            .providerCodex: "Codex",
            .providerClaude: "Claude Code",
            .providerCopilot: "GitHub Copilot",
            .enabled: "Enabled",
            .percentageShown: "Percentage shown",
            .usageLimitFiveHourCodexSpark: "GPT-5.3-Codex-Spark 5-hour usage limit",
            .usageLimitWeeklyCodexSpark: "GPT-5.3-Codex-Spark weekly usage limit",
            .usageLimitFiveHour: "5-hour usage limit",
            .usageLimitWeekly: "Weekly usage limit",
            .usageLimitSevenDay: "7-day usage limit",
            .usageLimitMonthly: "Monthly usage limit",
            .usageMetricCredits: "Credits",
            .resetAt: "Reset",
            .save: "Save",
            .cancel: "Cancel",
            .signInToCodex: "Sign in to Codex",
            .signInToGitHubCopilot: "Sign in to GitHub",
            .copilotToken: "GitHub Copilot token",
            .fetchFailed: "Unable to fetch",
            .signedOut: "Signed out",
            .connected: "Connected",
            .accountsSection: "Accounts",
            .codexSessionHelp: "Codex uses the local Codex CLI login from `~/.codex/auth.json`. Run `codex login` in Terminal, then refresh.",
            .codexCliConnected: "Detected local Codex CLI auth. Sign out through the Codex CLI if you want to disconnect it.",
            .claudeSessionHelp: "Claude Code uses the local Claude Code login from Keychain or `~/.claude/.credentials.json`. Run `claude` in Terminal, then refresh.",
            .claudeCliConnected: "Detected local Claude Code auth. Sign out through Claude Code if you want to disconnect it.",
            .copilotPatHelp: "GitHub Copilot signs in with GitHub device flow and loads usage from GitHub's Copilot API.",
            .copilotDeviceFlowWaiting: "Continue in your browser and enter this GitHub code: %@",
            .copilotDeviceFlowConnected: "GitHub Copilot is connected.",
            .saveAndRefresh: "Save and refresh",
            .reload: "Reload",
            .tokenSaved: "Token saved to Keychain.",
            .openCodexAndSignIn: "Open Codex and sign in, then click Save session.",
            .openGitHubCopilotAndSignIn: "Open GitHub, sign in if needed, then click Save session.",
            .settingsTabAccounts: "Accounts",
            .settingsTabDisplay: "Appearance",
            .settingsTabNotifications: "Notifications",
            .settingsTabLogs: "Logs",
            .settingsTabAbout: "About",
            .providerStatusOk: "Connected",
            .providerStatusNeedsAttention: "Needs attention",
            .saveSession: "Save session",
            .copilotPlanHelp: "Sign in with GitHub to load your GitHub Copilot usage.",
            .copilotConnectedHelp: "GitHub Copilot is connected. Sign out to remove the saved GitHub token.",
            .notificationsAheadDescription: "Warn when a quota is being consumed faster than the time window suggests.",
            .notificationsBehindDescription: "Warn when remaining quota is materially higher than expected for the current point in the window.",
            .notificationsCodexResetDescription: "Warn when the Codex 5-hour or weekly window appears to reset earlier than previously observed.",
            .notificationsClaudeResetDescription: "Warn when the Claude Code 5-hour or weekly window appears to reset earlier than previously observed.",
            .notificationTitleAheadFormat: "Ahead of schedule: %@",
            .notificationTitleBehindFormat: "Behind schedule: %@",
            .notificationBodyScheduleFormat: "Remaining usage is %d%% while the schedule suggests about %d%% should remain.",
            .notificationTitleCodexReset: "Codex reset detected early",
            .notificationTitleClaudeReset: "Claude Code reset detected early",
            .notificationBodyResetFormat: "%@ appears to have reset earlier than expected.",
            .notificationMetricFiveHourFormat: "%@ 5-hour window",
            .notificationMetricWeeklyFormat: "%@ weekly window",
            .notificationMetricMonthlyFormat: "%@ monthly quota",
            .notificationMetricCreditsFormat: "%@ credits",
            .copyLogs: "Copy logs",
            .clearLogs: "Clear logs",
            .noLogs: "No logs yet",
            .logsCopied: "Logs copied to the clipboard.",
            .appVersion: "Version",
            .projectSection: "Project",
            .projectRepository: "GitHub repository",
            .reportIssue: "Report an issue",
            .legalSection: "Legal",
            .logoDisclaimer: "The OpenAI logo, Claude logo, and GitHub Copilot logo are used only to identify their respective services. All trademarks, service marks, and logos are the property of their respective owners. This app is independent and is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, or GitHub.",
            .quitApp: "Quit",
            .menuActionRefresh: "Refresh",
            .menuActionSettings: "Settings",
            .signOut: "Sign out",
            .noGitHubCopilotSessionFound: "No GitHub session cookies were found yet.",
            .noCodexSessionFound: "No ChatGPT session cookies were found yet.",
        ]
    }

    private var polish: [L10nKey: String] {
        [
            .menuBarAppName: "Użycie AI",
            .notConfigured: "Nie skonfigurowano",
            .unavailable: "Niedostępne",
            .usagePanelTitle: "Użycie AI",
            .settingsTitle: "Ustawienia",
            .lastUpdate: "Ostatnia aktualizacja",
            .refreshNow: "Odśwież teraz",
            .openSettings: "Ustawienia",
            .staleData: "Nieaktualne dane",
            .authenticationRequired: "Wymagana autoryzacja",
            .authenticateInSettings: "Otwórz Ustawienia, aby skonfigurować dostęp do usług.",
            .generalSection: "Ogólne",
            .appearanceSection: "Wygląd",
            .menuBarSection: "Pasek menu",
            .mainPanelSection: "Panel główny",
            .notificationsSection: "Powiadomienia",
            .usageNotificationsSection: "Powiadomienia o użyciu",
            .earlyResetNotificationsSection: "Powiadomienia o wczesnym resecie",
            .language: "Język",
            .refreshInterval: "Częstotliwość odświeżania",
            .usagePanelBackground: "Tło panelu",
            .usagePanelBackgroundRegularMaterial: "Materiał",
            .usagePanelBackgroundSolidAdaptive: "Jednolity kolor",
            .codexMenuBarMetric: "Procent Codex na pasku menu",
            .claudeMenuBarMetric: "Procent Claude Code na pasku menu",
            .showCodexSparkUsage: "Pokaż użycie GPT-5.3-Codex-Spark",
            .menuBarMetricWeekly: "Użycie tygodniowe",
            .menuBarMetricFiveHour: "Użycie 5-godzinne",
            .menuBarIcons: "Ikony na pasku menu",
            .usagePanelProviders: "Usługi w panelu",
            .notificationsAhead: "Alerty: za szybkie zużycie",
            .notificationsBehind: "Alerty: zbyt wolne zużycie",
            .notificationsCodexReset: "Alerty o wczesnym resecie Codex",
            .notificationsClaudeReset: "Alerty o wczesnym resecie Claude Code",
            .providerCodex: "Codex",
            .providerClaude: "Claude Code",
            .providerCopilot: "GitHub Copilot",
            .enabled: "Włączone",
            .percentageShown: "Pokazywany procent",
            .usageLimitFiveHourCodexSpark: "5-godzinny limit wykorzystania GPT-5.3-Codex-Spark",
            .usageLimitWeeklyCodexSpark: "Tygodniowy limit wykorzystania GPT-5.3-Codex-Spark",
            .usageLimitFiveHour: "5-godzinny limit wykorzystania",
            .usageLimitWeekly: "Tygodniowy limit wykorzystania",
            .usageLimitSevenDay: "7-dniowy limit wykorzystania",
            .usageLimitMonthly: "Miesięczny limit wykorzystania",
            .usageMetricCredits: "Kredyty",
            .resetAt: "Reset",
            .save: "Zapisz",
            .cancel: "Anuluj",
            .signInToCodex: "Zaloguj do Codex",
            .signInToGitHubCopilot: "Zaloguj do GitHub",
            .copilotToken: "Token GitHub Copilot",
            .fetchFailed: "Nie udało się pobrać danych",
            .signedOut: "Wylogowano",
            .connected: "Połączono",
            .accountsSection: "Konta",
            .codexSessionHelp: "Codex korzysta z lokalnego logowania Codex CLI z `~/.codex/auth.json`. Uruchom `codex login` w Terminalu, a potem odśwież.",
            .codexCliConnected: "Wykryto lokalne uwierzytelnienie Codex CLI. Wyloguj się z poziomu Codex CLI, jeśli chcesz je odłączyć.",
            .claudeSessionHelp: "Claude Code korzysta z lokalnego logowania Claude Code z Keychain lub `~/.claude/.credentials.json`. Uruchom `claude` w Terminalu, a potem odśwież.",
            .claudeCliConnected: "Wykryto lokalne uwierzytelnienie Claude Code. Wyloguj się z poziomu Claude Code, jeśli chcesz je odłączyć.",
            .copilotPatHelp: "GitHub Copilot loguje się przez GitHub device flow i pobiera użycie z API Copilot w GitHub.",
            .copilotDeviceFlowWaiting: "Kontynuuj w przeglądarce i wpisz ten kod GitHub: %@",
            .copilotDeviceFlowConnected: "GitHub Copilot jest połączony.",
            .saveAndRefresh: "Zapisz i odśwież",
            .reload: "Przeładuj",
            .tokenSaved: "Token zapisany w Keychain.",
            .openCodexAndSignIn: "Otwórz Codex i zaloguj się, a potem kliknij Zapisz sesję.",
            .openGitHubCopilotAndSignIn: "Otwórz GitHub, zaloguj się w razie potrzeby, a potem kliknij Zapisz sesję.",
            .settingsTabAccounts: "Konta",
            .settingsTabDisplay: "Wygląd",
            .settingsTabNotifications: "Powiadomienia",
            .settingsTabLogs: "Logi",
            .settingsTabAbout: "Informacje",
            .providerStatusOk: "Połączono",
            .providerStatusNeedsAttention: "Wymaga uwagi",
            .saveSession: "Zapisz sesję",
            .copilotPlanHelp: "Zaloguj się do GitHub, aby wczytać użycie GitHub Copilot.",
            .copilotConnectedHelp: "GitHub Copilot jest połączony. Wyloguj się, aby usunąć zapisany token GitHub.",
            .notificationsAheadDescription: "Ostrzegaj, gdy limit jest zużywany szybciej, niż wynikałoby z upływu okna czasowego.",
            .notificationsBehindDescription: "Ostrzegaj, gdy pozostały limit jest wyraźnie wyższy niż oczekiwany w bieżącym momencie okna czasowego.",
            .notificationsCodexResetDescription: "Ostrzegaj, gdy okno 5-godzinne lub tygodniowe Codex wygląda na zresetowane wcześniej niż poprzednio.",
            .notificationsClaudeResetDescription: "Ostrzegaj, gdy okno 5-godzinne lub tygodniowe Claude Code wygląda na zresetowane wcześniej niż poprzednio.",
            .notificationTitleAheadFormat: "Zużycie powyżej tempa: %@",
            .notificationTitleBehindFormat: "Zużycie poniżej tempa: %@",
            .notificationBodyScheduleFormat: "Pozostałe użycie to %d%%, a harmonogram sugeruje około %d%%.",
            .notificationTitleCodexReset: "Wykryto wcześniejszy reset Codex",
            .notificationTitleClaudeReset: "Wykryto wcześniejszy reset Claude Code",
            .notificationBodyResetFormat: "%@ wygląda na zresetowane wcześniej niż oczekiwano.",
            .notificationMetricFiveHourFormat: "5-godzinne okno %@",
            .notificationMetricWeeklyFormat: "Tygodniowe okno %@",
            .notificationMetricMonthlyFormat: "Miesięczny limit %@",
            .notificationMetricCreditsFormat: "Kredyty %@",
            .copyLogs: "Kopiuj logi",
            .clearLogs: "Wyczyść logi",
            .noLogs: "Brak logów",
            .logsCopied: "Logi skopiowano do schowka.",
            .appVersion: "Wersja",
            .projectSection: "Projekt",
            .projectRepository: "Repozytorium GitHub",
            .reportIssue: "Zgłoś problem",
            .legalSection: "Informacje prawne",
            .logoDisclaimer: "Logo OpenAI, logo Claude i logo GitHub Copilot są używane wyłącznie w celu identyfikacji odpowiednich usług. Wszystkie znaki towarowe, znaki usługowe i logo należą do ich właścicieli. Ta aplikacja jest niezależna i nie jest powiązana z OpenAI, Anthropic ani GitHub, ani przez nie sponsorowana lub rekomendowana.",
            .quitApp: "Zakończ",
            .menuActionRefresh: "Odśwież",
            .menuActionSettings: "Ustawienia",
            .signOut: "Wyloguj się",
            .noGitHubCopilotSessionFound: "Nie znaleziono jeszcze ciasteczek sesji GitHub.",
            .noCodexSessionFound: "Nie znaleziono jeszcze ciasteczek sesji ChatGPT.",
        ]
    }
}
