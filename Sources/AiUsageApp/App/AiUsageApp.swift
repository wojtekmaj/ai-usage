import AppKit
import SwiftUI

@main
struct AiUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment

    init() {
        let environment: AppEnvironment

        if ProcessInfo.processInfo.environment["AI_USAGE_SCREENSHOT_MODE"] == "1" {
            let suiteName = "com.wojciechmaj.ai-usage.screenshot"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            NSApplication.shared.appearance = NSAppearance(named: .aqua)

            let settings = SettingsStore(defaults: defaults)
            settings.preferences.usagePanelBackgroundStyle = .solidAdaptive
            environment = AppEnvironment(
                settings: settings,
                keychain: KeychainStore(service: suiteName),
                usageStore: UsageStore(defaults: defaults),
                logStore: LogStore(defaults: defaults)
            )
        } else {
            environment = AppEnvironment()
        }

        _environment = StateObject(wrappedValue: environment)
        environment.start()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
