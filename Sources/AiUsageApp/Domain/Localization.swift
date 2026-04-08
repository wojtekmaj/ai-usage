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
    case codexMenuBarMetric
    case codexMenuBarMetricWeekly
    case codexMenuBarMetricFiveHour
    case menuBarIcons
    case notificationsAhead
    case notificationsBehind
    case notificationsCodexReset
    case providerCodex
    case providerCopilot
    case codexFiveHour
    case codexWeekly
    case codexCredits
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
    case copilotPatHelp
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
    case notificationsAheadDescription
    case notificationsBehindDescription
    case notificationsCodexResetDescription
    case copyLogs
    case clearLogs
    case noLogs
    case logsCopied
    case appVersion
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
            .codexMenuBarMetric: "Codex menu bar percentage",
            .codexMenuBarMetricWeekly: "Weekly usage",
            .codexMenuBarMetricFiveHour: "5-hour usage",
            .menuBarIcons: "Menu bar icons",
            .notificationsAhead: "Ahead-of-schedule alerts",
            .notificationsBehind: "Behind-schedule alerts",
            .notificationsCodexReset: "Codex early reset alerts",
            .providerCodex: "Codex",
            .providerCopilot: "GitHub Copilot",
            .codexFiveHour: "5-hour usage limit",
            .codexWeekly: "Weekly usage limit",
            .codexCredits: "Credits",
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
            .codexSessionHelp: "Codex uses your local ChatGPT web session because a stable personal usage API is not publicly documented.",
            .copilotPatHelp: "Optional: use a GitHub fine-grained personal access token if you want a token-based fallback.",
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
            .notificationsAheadDescription: "Warn when a quota is being consumed faster than the time window suggests.",
            .notificationsBehindDescription: "Warn when remaining quota is materially higher than expected for the current point in the window.",
            .notificationsCodexResetDescription: "Warn when the Codex 5-hour or weekly window appears to reset earlier than previously observed.",
            .copyLogs: "Copy logs",
            .clearLogs: "Clear logs",
            .noLogs: "No logs yet",
            .logsCopied: "Logs copied to the clipboard.",
            .appVersion: "Version",
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
            .codexMenuBarMetric: "Procent Codex na pasku menu",
            .codexMenuBarMetricWeekly: "Użycie tygodniowe",
            .codexMenuBarMetricFiveHour: "Użycie 5-godzinne",
            .menuBarIcons: "Ikony na pasku menu",
            .notificationsAhead: "Alerty: za szybkie zużycie",
            .notificationsBehind: "Alerty: zbyt wolne zużycie",
            .notificationsCodexReset: "Alerty o wczesnym resecie Codex",
            .providerCodex: "Codex",
            .providerCopilot: "GitHub Copilot",
            .codexFiveHour: "5-godzinny limit wykorzystania",
            .codexWeekly: "Tygodniowy limit wykorzystania",
            .codexCredits: "Kredyty",
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
            .codexSessionHelp: "Codex korzysta z lokalnej sesji webowej ChatGPT, ponieważ stabilne API do odczytu użycia nie jest publicznie udokumentowane.",
            .copilotPatHelp: "Opcjonalnie: użyj tokenu fine-grained personal access token z GitHub jako zapasowej metody uwierzytelniania.",
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
            .notificationsAheadDescription: "Ostrzegaj, gdy limit jest zużywany szybciej, niż wynikałoby z upływu okna czasowego.",
            .notificationsBehindDescription: "Ostrzegaj, gdy pozostały limit jest wyraźnie wyższy niż oczekiwany w bieżącym momencie okna czasowego.",
            .notificationsCodexResetDescription: "Ostrzegaj, gdy okno 5-godzinne lub tygodniowe Codex wygląda na zresetowane wcześniej niż poprzednio.",
            .copyLogs: "Kopiuj logi",
            .clearLogs: "Wyczyść logi",
            .noLogs: "Brak logów",
            .logsCopied: "Logi skopiowano do schowka.",
            .appVersion: "Wersja",
            .quitApp: "Zakończ",
            .menuActionRefresh: "Odśwież",
            .menuActionSettings: "Ustawienia",
            .signOut: "Wyloguj się",
            .noGitHubCopilotSessionFound: "Nie znaleziono jeszcze ciasteczek sesji GitHub.",
            .noCodexSessionFound: "Nie znaleziono jeszcze ciasteczek sesji ChatGPT.",
        ]
    }
}
