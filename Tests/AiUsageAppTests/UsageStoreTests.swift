import Foundation
import Testing
@testable import AiUsageApp

struct UsageStoreTests {
    @Test(arguments: [false, true])
    func loadSnapshotsPreservesSupportedMetrics(includesRetiredMetric: Bool) throws {
        let defaultsSuiteName = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_056_400)
        let metric = UsageMetric(
            kind: .codexWeekly,
            remainingFraction: 0.75,
            unit: .percentage,
            lastUpdatedAtUTC: now
        )
        let snapshot = ProviderSnapshot(
            provider: .codex,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: [metric]
        )
        let store = UsageStore(defaults: defaults)
        store.saveSnapshots([.codex: snapshot])

        if includesRetiredMetric {
            let data = try #require(defaults.data(forKey: "providerSnapshots"))
            var values = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            var metrics = try #require(values[0]["metrics"] as? [[String: Any]])
            var retiredMetric = metrics[0]
            retiredMetric["kind"] = "retiredMetric"
            metrics.append(retiredMetric)
            values[0]["metrics"] = metrics
            defaults.set(try JSONSerialization.data(withJSONObject: values), forKey: "providerSnapshots")
        }

        #expect(store.loadSnapshots() == [.codex: snapshot])
    }

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
