import Foundation
import Testing
@testable import AiUsageApp

struct UsageStoreTests {
    @Test
    func loadResetMarkersReadsProviderAgnosticStore() {
        let defaultsSuiteName = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let codexMarker = "codexFiveHour-2026-04-15T12:00:00Z"
        let claudeMarker = "claudeWeekly-2026-04-16T12:00:00Z"
        let copilotMarker = "copilotMonthly-2026-05-01T00:00:00Z"
        defaults.set([codexMarker, claudeMarker, copilotMarker], forKey: "resetMarkers")

        let store = UsageStore(defaults: defaults)

        #expect(store.loadResetMarkers() == Set([codexMarker, claudeMarker, copilotMarker]))
    }

    @Test
    func saveResetMarkersPreservesAllProviderMarkersTogether() {
        let defaultsSuiteName = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let codexMarker = "codexWeekly-2026-04-20T00:00:00Z"
        let claudeMarker = "claudeFiveHour-2026-04-15T16:30:00Z"
        let store = UsageStore(defaults: defaults)

        store.saveResetMarkers([codexMarker, claudeMarker])

        #expect(store.loadResetMarkers() == Set([codexMarker, claudeMarker]))
    }
}
