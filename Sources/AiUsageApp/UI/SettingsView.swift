import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var logStore: LogStore
    @State private var isSigningInToCopilot = false
    @State private var statusMessage: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        self._logStore = ObservedObject(wrappedValue: environment.logStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                accountsTab
                    .tabItem {
                        Label(environment.localizer.text(.settingsTabAccounts), systemImage: "person.crop.circle")
                    }

                displayTab
                    .tabItem {
                        Label(environment.localizer.text(.settingsTabDisplay), systemImage: "rectangle.on.rectangle")
                    }

                notificationsTab
                    .tabItem {
                        Label(environment.localizer.text(.settingsTabNotifications), systemImage: "bell.badge")
                    }

                logsTab
                    .tabItem {
                        Label(environment.localizer.text(.settingsTabLogs), systemImage: "doc.text.magnifyingglass")
                    }

                aboutTab
                    .tabItem {
                        Label(environment.localizer.text(.settingsTabAbout), systemImage: "info.circle")
                    }
            }

            if let statusMessage, statusMessage.isEmpty == false {
                Divider()
                HStack {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 500)
    }

    private var accountsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                providerAccountGroup(provider: .claude) {
                    if environment.currentAuthState(for: .claude) == .signedOut {
                        Text(environment.localizer.text(.claudeSessionHelp))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(environment.localizer.text(.refreshNow)) {
                            Task {
                                await environment.refreshNow()
                            }
                        }
                    } else {
                        Text(environment.localizer.text(.claudeCliConnected))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                providerAccountGroup(provider: .codex) {
                    if environment.currentAuthState(for: .codex) == .signedOut {
                        Text(environment.localizer.text(.codexSessionHelp))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(environment.localizer.text(.refreshNow)) {
                            Task {
                                await environment.refreshNow()
                            }
                        }
                    } else {
                        Text(environment.localizer.text(.codexCliConnected))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                providerAccountGroup(provider: .copilot) {
                    let copilotIsSignedOut = environment.currentAuthState(for: .copilot) == .signedOut

                    Text(environment.localizer.text(.copilotPatHelp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(environment.localizer.text(copilotIsSignedOut ? .copilotPlanHelp : .copilotConnectedHelp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        if copilotIsSignedOut {
                            Button(environment.localizer.text(.signInToGitHubCopilot)) {
                                Task {
                                    isSigningInToCopilot = true
                                    defer { isSigningInToCopilot = false }

                                    do {
                                        try await environment.signInToCopilot { userCode in
                                            statusMessage = String(
                                                format: environment.localizer.text(.copilotDeviceFlowWaiting),
                                                userCode
                                            )
                                        }
                                        statusMessage = environment.localizer.text(.copilotDeviceFlowConnected)
                                        await environment.refreshNow()
                                    } catch {
                                        statusMessage = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(isSigningInToCopilot)
                        }

                        if copilotIsSignedOut == false {
                            Button(environment.localizer.text(.signOut)) {
                                do {
                                    try environment.clearAuth(for: .copilot)
                                    statusMessage = nil
                                } catch {
                                    statusMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                settingsSection(title: environment.localizer.text(.generalSection)) {
                    settingsCard {
                        settingsRow(title: environment.localizer.text(.language)) {
                            Picker(environment.localizer.text(.language), selection: $environment.settings.preferences.language) {
                                Text("English (US)").tag(AppLanguage.englishUS)
                                Text("Polski").tag(AppLanguage.polish)
                            }
                            .pickerStyle(.menu)
                            .controlSize(.regular)
                        }

                        settingsDivider()

                        settingsRow(title: environment.localizer.text(.refreshInterval)) {
                            Picker(environment.localizer.text(.refreshInterval), selection: $environment.settings.preferences.refreshIntervalMinutes) {
                                Text("1 min").tag(1)
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                                Text("15 min").tag(15)
                            }
                            .pickerStyle(.menu)
                            .controlSize(.regular)
                        }
                    }
                }

                settingsSection(title: environment.localizer.text(.appearanceSection)) {
                    settingsCard {
                        settingsRow(title: environment.localizer.text(.usagePanelBackground)) {
                            Picker(environment.localizer.text(.usagePanelBackground), selection: $environment.settings.preferences.usagePanelBackgroundStyle) {
                                Text(environment.localizer.text(.usagePanelBackgroundRegularMaterial)).tag(UsagePanelBackgroundStyle.regularMaterial)
                                Text(environment.localizer.text(.usagePanelBackgroundSolidAdaptive)).tag(UsagePanelBackgroundStyle.solidAdaptive)
                            }
                            .pickerStyle(.menu)
                            .controlSize(.regular)
                        }
                    }
                }

                settingsSection(title: environment.localizer.text(.menuBarSection)) {
                    VStack(alignment: .leading, spacing: 16) {
                        menuBarProviderCard(provider: .claude)
                        menuBarProviderCard(provider: .codex)
                        menuBarProviderCard(provider: .copilot)
                    }
                }

                settingsSection(title: environment.localizer.text(.mainPanelSection)) {
                    VStack(alignment: .leading, spacing: 16) {
                        mainPanelProviderCard(provider: .claude)
                        mainPanelProviderCard(provider: .codex)
                        mainPanelProviderCard(provider: .copilot)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notificationsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                settingsSection(title: environment.localizer.text(.usageNotificationsSection)) {
                    settingsCard {
                        settingsRow(
                            title: environment.localizer.text(.notificationsAhead),
                            description: environment.localizer.text(.notificationsAheadDescription)
                        ) {
                            Toggle(environment.localizer.text(.notificationsAhead), isOn: $environment.settings.preferences.showAheadNotifications)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }

                        settingsDivider()

                        settingsRow(
                            title: environment.localizer.text(.notificationsBehind),
                            description: environment.localizer.text(.notificationsBehindDescription)
                        ) {
                            Toggle(environment.localizer.text(.notificationsBehind), isOn: $environment.settings.preferences.showBehindNotifications)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                    }
                }

                settingsSection(title: environment.localizer.text(.earlyResetNotificationsSection)) {
                    settingsCard {
                        settingsRow(
                            title: environment.localizer.text(.notificationsCodexReset),
                            description: environment.localizer.text(.notificationsCodexResetDescription)
                        ) {
                            Toggle(environment.localizer.text(.notificationsCodexReset), isOn: $environment.settings.preferences.showCodexResetNotifications)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }

                        settingsDivider()

                        settingsRow(
                            title: environment.localizer.text(.notificationsClaudeReset),
                            description: environment.localizer.text(.notificationsClaudeResetDescription)
                        ) {
                            Toggle(environment.localizer.text(.notificationsClaudeReset), isOn: $environment.settings.preferences.showClaudeResetNotifications)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if logStore.entries.isEmpty {
                        Text(environment.localizer.text(.noLogs))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(logStore.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(logTimestamp(entry.timestampUTC)) • \(entry.level.rawValue.uppercased()) • \(entry.category)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button(environment.localizer.text(.copyLogs)) {
                    let exportedLogs = logStore.exportText
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.declareTypes([.string], owner: nil)

                    if exportedLogs.isEmpty == false, pasteboard.setString(exportedLogs, forType: .string) {
                        statusMessage = environment.localizer.text(.logsCopied)
                    } else {
                        statusMessage = environment.localizer.text(.noLogs)
                    }
                }

                Button(environment.localizer.text(.clearLogs)) {
                    logStore.clear()
                    statusMessage = nil
                }
            }
        }
        .padding(28)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(environment.localizer.text(.menuBarAppName))
                .font(.title2.weight(.semibold))

            Text("\(environment.localizer.text(.appVersion)) \(AppMetadata.version)")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 0)

            Text(environment.localizer.text(.legalSection))
                .font(.headline)

            Text(environment.localizer.text(.logoDisclaimer))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsRow<Control: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                if let description, description.isEmpty == false {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, description == nil ? 0 : 8)

            Spacer(minLength: 12)

            control()
                .labelsHidden()
                .frame(minWidth: 185, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 0)
        .frame(minHeight: description == nil ? 44 : 0)
    }

    private func settingsDivider() -> some View {
        Divider()
            .padding(.horizontal, 6)
    }

    private func providerSettingsCard<Content: View>(
        provider: ProviderID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsCard {
            VStack(spacing: 0) {
                ProviderHeaderView(
                    provider: provider,
                    title: provider.displayName(localizer: environment.localizer),
                    subtitle: nil
                )
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 8)

                settingsDivider()
                content()
            }
        }
    }

    private func menuBarProviderCard(provider: ProviderID) -> some View {
        providerSettingsCard(provider: provider) {
            settingsRow(title: environment.localizer.text(.enabled)) {
                Toggle(
                    environment.localizer.text(.enabled),
                    isOn: visibilityBinding(for: provider, keyPath: \.visibleProviders)
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if provider == .claude {
                settingsDivider()

                settingsRow(title: environment.localizer.text(.percentageShown)) {
                    Picker(environment.localizer.text(.claudeMenuBarMetric), selection: $environment.settings.preferences.claudeMenuBarMetric) {
                        Text(environment.localizer.claudeMenuBarMetricLabel(.weekly)).tag(ClaudeMenuBarMetric.weekly)
                        Text(environment.localizer.claudeMenuBarMetricLabel(.fiveHour)).tag(ClaudeMenuBarMetric.fiveHour)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .disabled(environment.settings.preferences.visibleProviders.contains(.claude) == false)
                }
            }

            if provider == .codex {
                settingsDivider()

                settingsRow(title: environment.localizer.text(.percentageShown)) {
                    Picker(environment.localizer.text(.codexMenuBarMetric), selection: $environment.settings.preferences.codexMenuBarMetric) {
                        Text(environment.localizer.codexMenuBarMetricLabel(.weekly)).tag(CodexMenuBarMetric.weekly)
                        Text(environment.localizer.codexMenuBarMetricLabel(.fiveHour)).tag(CodexMenuBarMetric.fiveHour)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .disabled(environment.settings.preferences.visibleProviders.contains(.codex) == false)
                }
            }
        }
    }

    private func mainPanelProviderCard(provider: ProviderID) -> some View {
        providerSettingsCard(provider: provider) {
            settingsRow(title: environment.localizer.text(.enabled)) {
                Toggle(
                    environment.localizer.text(.enabled),
                    isOn: visibilityBinding(for: provider, keyPath: \.visiblePanelProviders)
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if provider == .codex {
                settingsDivider()

                settingsRow(title: environment.localizer.text(.showCodexSparkUsage)) {
                    Toggle(
                        environment.localizer.text(.showCodexSparkUsage),
                        isOn: codexSparkUsageBinding
                    )
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(environment.settings.preferences.visiblePanelProviders.contains(.codex) == false)
                }
            }
        }
    }

    @ViewBuilder
    private func providerAccountGroup(provider: ProviderID, @ViewBuilder content: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                accountHeader(provider: provider)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
        }
    }

    private func visibilityBinding(
        for provider: ProviderID,
        keyPath: WritableKeyPath<DisplayPreferences, Set<ProviderID>>
    ) -> Binding<Bool> {
        Binding(
            get: {
                environment.settings.preferences[keyPath: keyPath].contains(provider)
            },
            set: { isVisible in
                var preferences = environment.settings.preferences
                var updated = preferences[keyPath: keyPath]

                if isVisible {
                    updated.insert(provider)
                } else if updated.count > 1 {
                    updated.remove(provider)
                }

                preferences[keyPath: keyPath] = updated
                environment.settings.preferences = preferences
            }
        )
    }

    private func accountHeader(provider: ProviderID) -> some View {
        ProviderHeaderView(provider: provider, title: provider.displayName(localizer: environment.localizer), subtitle: authStatusText(provider))
    }

    private var codexSparkUsageBinding: Binding<Bool> {
        Binding(
            get: {
                environment.settings.preferences.showCodexSparkUsage
            },
            set: { isEnabled in
                var preferences = environment.settings.preferences
                preferences.showCodexSparkUsage = isEnabled
                environment.settings.preferences = preferences
            }
        )
    }

    private func authStatusText(_ provider: ProviderID) -> String {
        switch environment.currentAuthState(for: provider) {
        case .signedOut:
            return environment.localizer.text(.signedOut)
        case .configured, .authenticated:
            return environment.localizer.text(.providerStatusOk)
        }
    }

    private func logTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = environment.settings.preferences.language.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: date)
    }
}
