import Foundation

final class UsageStore {
    private let defaults: UserDefaults
    private let snapshotsKey = "providerSnapshots"
    private let alertsKey = "usageAlertStates"
    private let resetMarkersKey = "resetMarkers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshots() -> [ProviderID: ProviderSnapshot] {
        guard let data = defaults.data(forKey: snapshotsKey),
              let snapshots = try? decoder.decode([ProviderSnapshot].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
    }

    func saveSnapshots(_ snapshots: [ProviderID: ProviderSnapshot]) {
        let values = snapshots.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
        guard let data = try? encoder.encode(values) else {
            return
        }

        defaults.set(data, forKey: snapshotsKey)
    }

    func loadAlertStates() -> [String: UsageAlertState] {
        guard let data = defaults.data(forKey: alertsKey),
              let states = try? decoder.decode([String: UsageAlertState].self, from: data) else {
            return [:]
        }

        return states
    }

    func saveAlertStates(_ states: [String: UsageAlertState]) {
        guard let data = try? encoder.encode(states) else {
            return
        }

        defaults.set(data, forKey: alertsKey)
    }

    func loadResetMarkers() -> Set<String> {
        let stored = defaults.stringArray(forKey: resetMarkersKey) ?? []
        return Set(stored)
    }

    func saveResetMarkers(_ markers: Set<String>) {
        defaults.set(Array(markers).sorted(), forKey: resetMarkersKey)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
