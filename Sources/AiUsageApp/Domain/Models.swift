import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case codex
    case claude
    case copilot

    var id: String { rawValue }

    var usageSettingsURL: URL {
        switch self {
        case .codex:
            URL(string: "https://chatgpt.com/codex/cloud/settings/usage")!
        case .claude:
            URL(string: "https://claude.ai/settings/usage")!
        case .copilot:
            URL(string: "https://github.com/settings/copilot/features")!
        }
    }

    var iconResourceName: String {
        switch self {
        case .codex:
            return "openai-icon"
        case .claude:
            return "claude-icon"
        case .copilot:
            return "copilot-icon"
        }
    }

    func displayName(localizer: Localizer) -> String {
        switch self {
        case .codex:
            return localizer.text(.providerCodex)
        case .claude:
            return localizer.text(.providerClaude)
        case .copilot:
            return localizer.text(.providerCopilot)
        }
    }
}

enum UsageMetricKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case codexFiveHour
    case codexWeekly
    case codexCredits
    case claudeFiveHour
    case claudeWeekly
    case copilotMonthly

    var id: String { rawValue }

    var provider: ProviderID {
        switch self {
        case .codexFiveHour, .codexWeekly, .codexCredits:
            return .codex
        case .claudeFiveHour, .claudeWeekly:
            return .claude
        case .copilotMonthly:
            return .copilot
        }
    }

    var participatesInMenuBarSummary: Bool {
        switch self {
        case .codexFiveHour, .codexWeekly, .claudeFiveHour, .claudeWeekly, .copilotMonthly:
            return true
        case .codexCredits:
            return false
        }
    }

    var supportsAheadNotifications: Bool {
        switch self {
        case .codexFiveHour, .codexWeekly, .claudeFiveHour, .claudeWeekly, .copilotMonthly:
            return true
        case .codexCredits:
            return false
        }
    }

    var supportsBehindNotifications: Bool {
        switch self {
        case .codexWeekly, .claudeWeekly, .copilotMonthly:
            return true
        case .codexFiveHour, .claudeFiveHour, .codexCredits:
            return false
        }
    }
}

enum MetricUnit: String, Codable, Hashable, Sendable {
    case percentage
    case requests
    case credits
}

enum ProviderAuthState: String, Codable, Hashable, Sendable {
    case signedOut
    case configured
    case authenticated
}

enum ProviderFetchState: String, Codable, Hashable, Sendable {
    case ok
    case missingAuth
    case failed
}

enum UsageAlertDirection: String, Codable, Hashable, Sendable {
    case ahead
    case behind
}

struct UsageMetric: Codable, Identifiable, Hashable, Sendable {
    let kind: UsageMetricKind
    var remainingFraction: Double?
    var remainingValue: Double?
    var totalValue: Double?
    var unit: MetricUnit
    var resetAtUTC: Date?
    var lastUpdatedAtUTC: Date
    var detailText: String?

    var id: String { kind.rawValue }
}

struct ProviderSnapshot: Codable, Identifiable, Hashable, Sendable {
    let provider: ProviderID
    var authState: ProviderAuthState
    var fetchState: ProviderFetchState
    var fetchedAtUTC: Date?
    var metrics: [UsageMetric]
    var errorDescription: String?
    var sourceDescription: String?

    var id: String { provider.rawValue }

    func metric(_ kind: UsageMetricKind) -> UsageMetric? {
        metrics.first { $0.kind == kind }
    }
}

struct UsageAlertState: Codable, Hashable, Sendable {
    var direction: UsageAlertDirection
    var metricKind: UsageMetricKind
    var lastTriggeredAtUTC: Date
    var lastExtremeDelta: Double
    var lastResetAtUTC: Date?
    var isArmed: Bool
}

struct MenuBarSummaryItem: Identifiable, Hashable, Sendable {
    let provider: ProviderID
    let remainingFraction: Double?

    var id: String { provider.rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case englishUS
    case polish

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .englishUS:
            return Locale(identifier: "en_US")
        case .polish:
            return Locale(identifier: "pl_PL")
        }
    }
}

enum CodexMenuBarMetric: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case weekly
    case fiveHour

    var id: String { rawValue }

    var usageMetricKind: UsageMetricKind {
        switch self {
        case .weekly:
            return .codexWeekly
        case .fiveHour:
            return .codexFiveHour
        }
    }
}

enum ClaudeMenuBarMetric: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case weekly
    case fiveHour

    var id: String { rawValue }

    var usageMetricKind: UsageMetricKind {
        switch self {
        case .weekly:
            return .claudeWeekly
        case .fiveHour:
            return .claudeFiveHour
        }
    }
}

enum UsagePanelBackgroundStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case regularMaterial
    case solidAdaptive

    var id: String { rawValue }
}

struct DisplayPreferences: Codable, Hashable, Sendable {
    private var hiddenProviders: Set<ProviderID>
    var visibleProviders: Set<ProviderID> {
        get {
            Set(ProviderID.allCases.filter { hiddenProviders.contains($0) == false })
        }
        set {
            hiddenProviders = Set(ProviderID.allCases.filter { newValue.contains($0) == false })
        }
    }
    private var hiddenPanelProviders: Set<ProviderID>
    var visiblePanelProviders: Set<ProviderID> {
        get {
            Set(ProviderID.allCases.filter { hiddenPanelProviders.contains($0) == false })
        }
        set {
            hiddenPanelProviders = Set(ProviderID.allCases.filter { newValue.contains($0) == false })
        }
    }
    var showAheadNotifications: Bool
    var showBehindNotifications: Bool
    var showCodexResetNotifications: Bool
    var showClaudeResetNotifications: Bool
    var refreshIntervalMinutes: Int
    var language: AppLanguage
    var codexMenuBarMetric: CodexMenuBarMetric
    var claudeMenuBarMetric: ClaudeMenuBarMetric
    var usagePanelBackgroundStyle: UsagePanelBackgroundStyle

    enum CodingKeys: String, CodingKey {
        case hiddenProviders
        case hiddenPanelProviders
        case showAheadNotifications
        case showBehindNotifications
        case showCodexResetNotifications
        case showClaudeResetNotifications
        case refreshIntervalMinutes
        case language
        case codexMenuBarMetric
        case claudeMenuBarMetric
        case usagePanelBackgroundStyle
    }

    init(
        visibleProviders: Set<ProviderID>,
        visiblePanelProviders: Set<ProviderID>,
        showAheadNotifications: Bool,
        showBehindNotifications: Bool,
        showCodexResetNotifications: Bool,
        showClaudeResetNotifications: Bool,
        refreshIntervalMinutes: Int,
        language: AppLanguage,
        codexMenuBarMetric: CodexMenuBarMetric,
        claudeMenuBarMetric: ClaudeMenuBarMetric,
        usagePanelBackgroundStyle: UsagePanelBackgroundStyle
    ) {
        self.hiddenProviders = Set(ProviderID.allCases.filter { visibleProviders.contains($0) == false })
        self.hiddenPanelProviders = Set(ProviderID.allCases.filter { visiblePanelProviders.contains($0) == false })
        self.showAheadNotifications = showAheadNotifications
        self.showBehindNotifications = showBehindNotifications
        self.showCodexResetNotifications = showCodexResetNotifications
        self.showClaudeResetNotifications = showClaudeResetNotifications
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.language = language
        self.codexMenuBarMetric = codexMenuBarMetric
        self.claudeMenuBarMetric = claudeMenuBarMetric
        self.usagePanelBackgroundStyle = usagePanelBackgroundStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenProviders = try container.decodeIfPresent(Set<ProviderID>.self, forKey: .hiddenProviders) ?? []
        hiddenPanelProviders = try container.decodeIfPresent(Set<ProviderID>.self, forKey: .hiddenPanelProviders) ?? []
        showAheadNotifications = try container.decode(Bool.self, forKey: .showAheadNotifications)
        showBehindNotifications = try container.decode(Bool.self, forKey: .showBehindNotifications)
        showCodexResetNotifications = try container.decode(Bool.self, forKey: .showCodexResetNotifications)
        showClaudeResetNotifications = try container.decodeIfPresent(Bool.self, forKey: .showClaudeResetNotifications) ?? true
        refreshIntervalMinutes = try container.decode(Int.self, forKey: .refreshIntervalMinutes)
        language = try container.decode(AppLanguage.self, forKey: .language)
        codexMenuBarMetric = try container.decodeIfPresent(CodexMenuBarMetric.self, forKey: .codexMenuBarMetric) ?? .weekly
        claudeMenuBarMetric = try container.decodeIfPresent(ClaudeMenuBarMetric.self, forKey: .claudeMenuBarMetric) ?? .weekly
        usagePanelBackgroundStyle = try container.decodeIfPresent(UsagePanelBackgroundStyle.self, forKey: .usagePanelBackgroundStyle) ?? .regularMaterial
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hiddenProviders, forKey: .hiddenProviders)
        try container.encode(hiddenPanelProviders, forKey: .hiddenPanelProviders)
        try container.encode(showAheadNotifications, forKey: .showAheadNotifications)
        try container.encode(showBehindNotifications, forKey: .showBehindNotifications)
        try container.encode(showCodexResetNotifications, forKey: .showCodexResetNotifications)
        try container.encode(showClaudeResetNotifications, forKey: .showClaudeResetNotifications)
        try container.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
        try container.encode(language, forKey: .language)
        try container.encode(codexMenuBarMetric, forKey: .codexMenuBarMetric)
        try container.encode(claudeMenuBarMetric, forKey: .claudeMenuBarMetric)
        try container.encode(usagePanelBackgroundStyle, forKey: .usagePanelBackgroundStyle)
    }

    func shouldRescheduleRefresh(comparedTo previous: Self) -> Bool {
        refreshIntervalMinutes != previous.refreshIntervalMinutes
    }

    static let `default` = DisplayPreferences(
        visibleProviders: Set(ProviderID.allCases),
        visiblePanelProviders: Set(ProviderID.allCases),
        showAheadNotifications: true,
        showBehindNotifications: true,
        showCodexResetNotifications: true,
        showClaudeResetNotifications: true,
        refreshIntervalMinutes: 5,
        language: .englishUS,
        codexMenuBarMetric: .weekly,
        claudeMenuBarMetric: .weekly,
        usagePanelBackgroundStyle: .regularMaterial
    )
}
