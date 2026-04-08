import AppKit
import SwiftUI

@main
struct AiUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        _environment = StateObject(wrappedValue: environment)
        environment.start()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
