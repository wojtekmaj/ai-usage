import Combine
import Foundation
import AppKit
import SwiftUI

enum MenuBarSummaryEvaluator {
    static func remainingFraction(for provider: ProviderID, snapshot: ProviderSnapshot, preferences: DisplayPreferences) -> Double? {
        switch provider {
        case .codex:
            return snapshot.metric(preferences.codexMenuBarMetric.usageMetricKind)?.remainingFraction
        case .claude:
            return snapshot.metric(preferences.claudeMenuBarMetric.usageMetricKind)?.remainingFraction
        case .copilot:
            return snapshot.metric(.copilotMonthly)?.remainingFraction
        }
    }
}

private enum AppBootstrapMode {
    case live
    case screenshotMock

    init(env: [String: String]) {
        if env["AI_USAGE_SCREENSHOT_MODE"] == "1" {
            self = .screenshotMock
        } else {
            self = .live
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var lastRefreshAtUTC: Date?
    @Published private(set) var isRefreshing = false
    @Published var lastRefreshError: String?

    var settings: SettingsStore
    let keychain: KeychainStore
    let usageStore: UsageStore
    let notificationService: NotificationService
    let logStore: LogStore

    private let codexProvider: CodexProvider
    private let claudeProvider: ClaudeProvider
    private let copilotProvider: CopilotProvider
    private let bootstrapMode: AppBootstrapMode
    private let nowProvider: () -> Date
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var refreshLoopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: SettingsStore = SettingsStore(),
        keychain: KeychainStore = KeychainStore(),
        usageStore: UsageStore = UsageStore(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.keychain = keychain
        self.usageStore = usageStore
        self.logStore = LogStore()
        self.notificationService = NotificationService(usageStore: usageStore)
        self.codexProvider = CodexProvider(keychain: keychain, logStore: logStore)
        self.claudeProvider = ClaudeProvider(logStore: logStore)
        self.copilotProvider = CopilotProvider(keychain: keychain, logStore: logStore)
        self.bootstrapMode = AppBootstrapMode(env: env)
        self.nowProvider = nowProvider
        let persistedSnapshots = usageStore.loadSnapshots()
        self.snapshots = persistedSnapshots.isEmpty ? [:] : persistedSnapshots
        self.lastRefreshAtUTC = persistedSnapshots.values.compactMap(\.fetchedAtUTC).max()

        if bootstrapMode == .screenshotMock {
            bootstrapScreenshotMockState()
        } else if self.snapshots.isEmpty {
            bootstrapPlaceholderState()
        }

        observeSettings()
    }

    var localizer: Localizer {
        settings.localizer
    }

    var visibleMenuBarItems: [MenuBarSummaryItem] {
        settings.preferences.visibleProviders.compactMap { provider in
            let fraction = menuBarFraction(for: provider)
            return MenuBarSummaryItem(provider: provider, remainingFraction: fraction)
        }
        .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    func start() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(environment: self)
        }

        if statusItemController == nil {
            statusItemController = StatusItemController(environment: self)
        }

        if bootstrapMode == .screenshotMock {
            logStore.append(category: "app", message: "Application started in screenshot mock mode.")
            return
        }

        logStore.append(category: "app", message: "Application started.")
        if notificationService.notificationsAreAvailable {
            notificationService.requestAuthorizationIfNeeded()
        } else {
            logStore.append(
                level: .warning,
                category: "app",
                message: "Skipping notification authorization because the process is not running from an .app bundle."
            )
        }
        scheduleRefreshLoop()
    }

    func showSettings() {
        closePanel()
        settingsWindowController?.show()
    }

    func closePanel() {
        statusItemController?.closePopover()
    }

    func quitApplication() {
        logStore.append(category: "app", message: "Application terminated by user.")
        NSApp.terminate(nil)
    }

    func refreshNow() async {
        if bootstrapMode == .screenshotMock {
            lastRefreshAtUTC = nowProvider().addingTimeInterval(-8)
            return
        }

        guard isRefreshing == false else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        logStore.append(category: "refresh", message: "Refresh started for \(providers.count) providers.")
        let previousSnapshots = snapshots
        var updatedSnapshots: [ProviderID: ProviderSnapshot] = [:]
        var errors: [String] = []

        for provider in providers {
            let snapshot = await provider.refresh(now: now)
            updatedSnapshots[snapshot.provider] = snapshot
            logStore.append(
                level: snapshot.fetchState == .failed ? .error : .info,
                category: "refresh",
                message: "\(snapshot.provider.rawValue) -> \(snapshot.fetchState.rawValue), auth=\(snapshot.authState.rawValue), metrics=\(snapshot.metrics.count)"
            )

            if let errorDescription = snapshot.errorDescription, snapshot.fetchState == .failed {
                errors.append("\(snapshot.provider.rawValue.capitalized): \(errorDescription)")
            }
        }

        snapshots = updatedSnapshots
        lastRefreshAtUTC = now
        lastRefreshError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if let lastRefreshError {
            logStore.append(level: .error, category: "refresh", message: "Refresh completed with errors: \(lastRefreshError)")
        } else {
            logStore.append(category: "refresh", message: "Refresh completed successfully.")
        }

        usageStore.saveSnapshots(updatedSnapshots)
        notificationService.processRefresh(previousSnapshots: previousSnapshots, newSnapshots: updatedSnapshots, preferences: settings.preferences, now: now)
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot? {
        snapshots[provider]
    }

    func currentAuthState(for provider: ProviderID) -> ProviderAuthState {
        if bootstrapMode == .screenshotMock {
            return snapshots[provider]?.authState ?? .authenticated
        }

        switch provider {
        case .codex:
            return codexProvider.currentAuthState()
        case .claude:
            return claudeProvider.currentAuthState()
        case .copilot:
            return copilotProvider.currentAuthState()
        }
    }

    func saveCopilotToken(_ token: String) throws {
        try copilotProvider.saveToken(token)
        logStore.append(category: "copilot", message: "Copilot token saved to Keychain.")
        bootstrapMissingSnapshot(for: .copilot)
    }

    func signInToCopilot(onVerificationCode: @escaping @MainActor (String) -> Void) async throws {
        let deviceCode = try await CopilotDeviceFlow.requestDeviceCode()
        guard let verificationURL = URL(string: deviceCode.verificationURI) else {
            throw CopilotDeviceFlowError.invalidResponse
        }

        NSWorkspace.shared.open(verificationURL)
        logStore.append(category: "copilot", message: "Opened GitHub device flow verification page.")
        onVerificationCode(deviceCode.userCode)

        let token = try await CopilotDeviceFlow.pollForToken(
            deviceCode: deviceCode.deviceCode,
            interval: deviceCode.interval
        )

        try saveCopilotToken(token)
    }

    func clearAuth(for provider: ProviderID) throws {
        switch provider {
        case .codex:
            try codexProvider.clearAuth()
            logStore.append(category: "codex", message: "Codex auth is managed by the local Codex CLI.")
        case .claude:
            try claudeProvider.clearAuth()
            logStore.append(category: "claude", message: "Claude auth is managed by the local Claude Code login.")
        case .copilot:
            try copilotProvider.clearAuth()
            logStore.append(category: "copilot", message: "Copilot credentials removed from Keychain.")
        }

        bootstrapMissingSnapshot(for: provider)
        usageStore.saveSnapshots(snapshots)
    }

    func isStale(referenceDate: Date = Date()) -> Bool {
        guard let lastRefreshAtUTC else {
            return false
        }

        return referenceDate.timeIntervalSince(lastRefreshAtUTC) >= settings.stalenessThreshold
    }

    private func observeSettings() {
        settings.$preferences
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.$preferences
            .removeDuplicates(by: { previous, current in
                current.shouldRescheduleRefresh(comparedTo: previous) == false
            })
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefreshLoop()
            }
            .store(in: &cancellables)
    }

    private func scheduleRefreshLoop() {
        refreshLoopTask?.cancel()

        let interval = settings.preferences.refreshIntervalMinutes

        refreshLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshNow()

            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: .seconds(interval * 60))
                } catch {
                    return
                }

                await self.refreshNow()
            }
        }
    }

    private var providers: [UsageProvider] {
        [codexProvider, claudeProvider, copilotProvider]
    }

    private func menuBarFraction(for provider: ProviderID) -> Double? {
        guard let snapshot = snapshots[provider] else {
            return nil
        }

        return MenuBarSummaryEvaluator.remainingFraction(for: provider, snapshot: snapshot, preferences: settings.preferences)
    }

    private func bootstrapPlaceholderState() {
        let now = nowProvider()

        snapshots[.codex] = ProviderSnapshot(
            provider: .codex,
            authState: .signedOut,
            fetchState: .missingAuth,
            fetchedAtUTC: nil,
            metrics: [
                UsageMetric(kind: .codexFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
                UsageMetric(kind: .codexWeekly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
                UsageMetric(kind: .codexCredits, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .credits, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )

        snapshots[.copilot] = ProviderSnapshot(
            provider: .copilot,
            authState: .signedOut,
            fetchState: .missingAuth,
            fetchedAtUTC: nil,
            metrics: [
                UsageMetric(kind: .copilotMonthly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )

        snapshots[.claude] = ProviderSnapshot(
            provider: .claude,
            authState: .signedOut,
            fetchState: .missingAuth,
            fetchedAtUTC: nil,
            metrics: [
                UsageMetric(kind: .claudeFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
                UsageMetric(kind: .claudeWeekly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )
    }

    private func bootstrapMissingSnapshot(for provider: ProviderID) {
        let now = nowProvider()

        switch provider {
        case .codex:
            snapshots[.codex] = ProviderSnapshot(
                provider: .codex,
                authState: currentAuthState(for: .codex),
                fetchState: currentAuthState(for: .codex) == .signedOut ? .missingAuth : .failed,
                fetchedAtUTC: snapshots[.codex]?.fetchedAtUTC,
                metrics: [
                    UsageMetric(kind: .codexFiveHour, remainingFraction: snapshots[.codex]?.metric(.codexFiveHour)?.remainingFraction, remainingValue: snapshots[.codex]?.metric(.codexFiveHour)?.remainingValue, totalValue: snapshots[.codex]?.metric(.codexFiveHour)?.totalValue, unit: .percentage, resetAtUTC: snapshots[.codex]?.metric(.codexFiveHour)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.codex]?.metric(.codexFiveHour)?.detailText),
                    UsageMetric(kind: .codexWeekly, remainingFraction: snapshots[.codex]?.metric(.codexWeekly)?.remainingFraction, remainingValue: snapshots[.codex]?.metric(.codexWeekly)?.remainingValue, totalValue: snapshots[.codex]?.metric(.codexWeekly)?.totalValue, unit: .percentage, resetAtUTC: snapshots[.codex]?.metric(.codexWeekly)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.codex]?.metric(.codexWeekly)?.detailText),
                    UsageMetric(kind: .codexCredits, remainingFraction: nil, remainingValue: snapshots[.codex]?.metric(.codexCredits)?.remainingValue, totalValue: nil, unit: .credits, resetAtUTC: snapshots[.codex]?.metric(.codexCredits)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.codex]?.metric(.codexCredits)?.detailText),
                ],
                errorDescription: nil,
                sourceDescription: codexProvider.sourceDescription
            )
        case .claude:
            snapshots[.claude] = ProviderSnapshot(
                provider: .claude,
                authState: currentAuthState(for: .claude),
                fetchState: currentAuthState(for: .claude) == .signedOut ? .missingAuth : .failed,
                fetchedAtUTC: snapshots[.claude]?.fetchedAtUTC,
                metrics: [
                    UsageMetric(kind: .claudeFiveHour, remainingFraction: snapshots[.claude]?.metric(.claudeFiveHour)?.remainingFraction, remainingValue: snapshots[.claude]?.metric(.claudeFiveHour)?.remainingValue, totalValue: snapshots[.claude]?.metric(.claudeFiveHour)?.totalValue, unit: .percentage, resetAtUTC: snapshots[.claude]?.metric(.claudeFiveHour)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.claude]?.metric(.claudeFiveHour)?.detailText),
                    UsageMetric(kind: .claudeWeekly, remainingFraction: snapshots[.claude]?.metric(.claudeWeekly)?.remainingFraction, remainingValue: snapshots[.claude]?.metric(.claudeWeekly)?.remainingValue, totalValue: snapshots[.claude]?.metric(.claudeWeekly)?.totalValue, unit: .percentage, resetAtUTC: snapshots[.claude]?.metric(.claudeWeekly)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.claude]?.metric(.claudeWeekly)?.detailText),
                ],
                errorDescription: nil,
                sourceDescription: claudeProvider.sourceDescription
            )
        case .copilot:
            snapshots[.copilot] = ProviderSnapshot(
                provider: .copilot,
                authState: currentAuthState(for: .copilot),
                fetchState: currentAuthState(for: .copilot) == .signedOut ? .missingAuth : .failed,
                fetchedAtUTC: snapshots[.copilot]?.fetchedAtUTC,
                metrics: [
                    UsageMetric(kind: .copilotMonthly, remainingFraction: snapshots[.copilot]?.metric(.copilotMonthly)?.remainingFraction, remainingValue: snapshots[.copilot]?.metric(.copilotMonthly)?.remainingValue, totalValue: snapshots[.copilot]?.metric(.copilotMonthly)?.totalValue, unit: .requests, resetAtUTC: snapshots[.copilot]?.metric(.copilotMonthly)?.resetAtUTC, lastUpdatedAtUTC: now, detailText: snapshots[.copilot]?.metric(.copilotMonthly)?.detailText),
                ],
                errorDescription: nil,
                sourceDescription: copilotProvider.sourceDescription
            )
        }
    }

    private func bootstrapScreenshotMockState() {
        let now = nowProvider()

        snapshots = [
            .claude: ProviderSnapshot(
                provider: .claude,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now.addingTimeInterval(-8),
                metrics: [
                    UsageMetric(
                        kind: .claudeFiveHour,
                        remainingFraction: 0.23,
                        remainingValue: nil,
                        totalValue: nil,
                        unit: .percentage,
                        resetAtUTC: screenshotDate(year: 2026, month: 4, day: 10, hour: 23, minute: 59),
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                    UsageMetric(
                        kind: .claudeWeekly,
                        remainingFraction: 0.62,
                        remainingValue: nil,
                        totalValue: nil,
                        unit: .percentage,
                        resetAtUTC: screenshotDate(year: 2026, month: 4, day: 15, hour: 0, minute: 52),
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                ],
                errorDescription: nil,
                sourceDescription: "Screenshot mock data"
            ),
            .codex: ProviderSnapshot(
                provider: .codex,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now.addingTimeInterval(-8),
                metrics: [
                    UsageMetric(
                        kind: .codexFiveHour,
                        remainingFraction: 0.36,
                        remainingValue: nil,
                        totalValue: nil,
                        unit: .percentage,
                        resetAtUTC: screenshotDate(year: 2026, month: 4, day: 10, hour: 23, minute: 31),
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                    UsageMetric(
                        kind: .codexWeekly,
                        remainingFraction: 0.76,
                        remainingValue: nil,
                        totalValue: nil,
                        unit: .percentage,
                        resetAtUTC: screenshotDate(year: 2026, month: 4, day: 15, hour: 10, minute: 51),
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                    UsageMetric(
                        kind: .codexCredits,
                        remainingFraction: nil,
                        remainingValue: 336,
                        totalValue: nil,
                        unit: .credits,
                        resetAtUTC: nil,
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                ],
                errorDescription: nil,
                sourceDescription: "Screenshot mock data"
            ),
            .copilot: ProviderSnapshot(
                provider: .copilot,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now.addingTimeInterval(-8),
                metrics: [
                    UsageMetric(
                        kind: .copilotMonthly,
                        remainingFraction: 0.78,
                        remainingValue: nil,
                        totalValue: nil,
                        unit: .percentage,
                        resetAtUTC: screenshotDate(year: 2026, month: 5, day: 1, hour: 2, minute: 0),
                        lastUpdatedAtUTC: now,
                        detailText: nil
                    ),
                ],
                errorDescription: nil,
                sourceDescription: "Screenshot mock data"
            ),
        ]
        lastRefreshAtUTC = now.addingTimeInterval(-8)
        lastRefreshError = nil
    }

    private func screenshotDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = screenshotCalendar
        components.timeZone = screenshotCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        return components.date ?? nowProvider()
    }

    private var screenshotCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .autoupdatingCurrent
        return calendar
    }
}
