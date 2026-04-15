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
    case notificationsSection
    case language
    case refreshInterval
    case usagePanelBackground
    case usagePanelBackgroundRegularMaterial
    case usagePanelBackgroundSolidAdaptive
    case codexMenuBarMetric
    case codexMenuBarMetricWeekly
    case codexMenuBarMetricFiveHour
    case claudeMenuBarMetric
    case claudeMenuBarMetricWeekly
    case claudeMenuBarMetricFiveHour
    case menuBarIcons
    case usagePanelProviders
    case notificationsAhead
    case notificationsBehind
    case notificationsCodexReset
    case notificationsClaudeReset
    case providerCodex
    case providerClaude
    case providerCopilot
    case codexFiveHour
    case codexWeekly
    case codexCredits
    case claudeFiveHour
    case claudeWeekly
    case copilotMonthly
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
    case copyLogs
    case clearLogs
    case noLogs
    case logsCopied
    case appVersion
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
            .notificationsSection: "Notifications",
            .language: "Language",
            .refreshInterval: "Refresh interval",
            .usagePanelBackground: "Panel background",
            .usagePanelBackgroundRegularMaterial: "Material",
            .usagePanelBackgroundSolidAdaptive: "Solid color",
            .codexMenuBarMetric: "Codex menu bar percentage",
            .codexMenuBarMetricWeekly: "Weekly usage",
            .codexMenuBarMetricFiveHour: "5-hour usage",
            .claudeMenuBarMetric: "Claude menu bar percentage",
            .claudeMenuBarMetricWeekly: "7-day usage",
            .claudeMenuBarMetricFiveHour: "5-hour usage",
            .menuBarIcons: "Menu bar icons",
            .usagePanelProviders: "Usage panel providers",
            .notificationsAhead: "Ahead-of-schedule alerts",
            .notificationsBehind: "Behind-schedule alerts",
            .notificationsCodexReset: "Codex early reset alerts",
            .notificationsClaudeReset: "Claude Code early reset alerts",
            .providerCodex: "Codex",
            .providerClaude: "Claude",
            .providerCopilot: "GitHub Copilot",
            .codexFiveHour: "5-hour usage limit",
            .codexWeekly: "Weekly usage limit",
            .codexCredits: "Credits",
            .claudeFiveHour: "5-hour usage limit",
            .claudeWeekly: "7-day usage limit",
            .copilotMonthly: "Monthly usage limit",
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
            .claudeSessionHelp: "Claude uses the local Claude Code login from Keychain or `~/.claude/.credentials.json`. Run `claude` in Terminal, then refresh.",
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
            .settingsTabDisplay: "Display",
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
            .copyLogs: "Copy logs",
            .clearLogs: "Clear logs",
            .noLogs: "No logs yet",
            .logsCopied: "Logs copied to the clipboard.",
            .appVersion: "Version",
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
            .notificationsSection: "Powiadomienia",
            .language: "Język",
            .refreshInterval: "Częstotliwość odświeżania",
            .usagePanelBackground: "Tło panelu",
            .usagePanelBackgroundRegularMaterial: "Materiał",
            .usagePanelBackgroundSolidAdaptive: "Jednolity kolor",
            .codexMenuBarMetric: "Procent Codex na pasku menu",
            .codexMenuBarMetricWeekly: "Użycie tygodniowe",
            .codexMenuBarMetricFiveHour: "Użycie 5-godzinne",
            .claudeMenuBarMetric: "Procent Claude na pasku menu",
            .claudeMenuBarMetricWeekly: "Użycie tygodniowe",
            .claudeMenuBarMetricFiveHour: "Użycie 5-godzinne",
            .menuBarIcons: "Ikony na pasku menu",
            .usagePanelProviders: "Usługi w panelu",
            .notificationsAhead: "Alerty: za szybkie zużycie",
            .notificationsBehind: "Alerty: zbyt wolne zużycie",
            .notificationsCodexReset: "Alerty o wczesnym resecie Codex",
            .notificationsClaudeReset: "Alerty o wczesnym resecie Claude Code",
            .providerCodex: "Codex",
            .providerClaude: "Claude",
            .providerCopilot: "GitHub Copilot",
            .codexFiveHour: "5-godzinny limit wykorzystania",
            .codexWeekly: "Tygodniowy limit wykorzystania",
            .codexCredits: "Kredyty",
            .claudeFiveHour: "5-godzinny limit wykorzystania",
            .claudeWeekly: "7-dniowy limit wykorzystania",
            .copilotMonthly: "Miesięczny limit wykorzystania",
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
            .claudeSessionHelp: "Claude korzysta z lokalnego logowania Claude Code z Keychain lub `~/.claude/.credentials.json`. Uruchom `claude` w Terminalu, a potem odśwież.",
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
            .copyLogs: "Kopiuj logi",
            .clearLogs: "Wyczyść logi",
            .noLogs: "Brak logów",
            .logsCopied: "Logi skopiowano do schowka.",
            .appVersion: "Wersja",
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
