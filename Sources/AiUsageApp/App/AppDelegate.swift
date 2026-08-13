import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var codexPreheatHandler: (() -> Void)?
    nonisolated static let updateURLUserInfoKey = "updateURL"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "preheat-codex" {
            Task { @MainActor in
                Self.codexPreheatHandler?()
            }
        } else if let urlString = response.notification.request.content.userInfo[Self.updateURLUserInfoKey] as? String,
                  let url = URL(string: urlString),
                  url.scheme == "https",
                  url.host == "github.com" {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
