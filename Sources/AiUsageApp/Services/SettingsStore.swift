import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: DisplayPreferences {
        didSet {
            persist()
        }
    }

    private let defaults: UserDefaults
    private let key = "displayPreferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DisplayPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .default
        }
    }

    var localizer: Localizer {
        Localizer(language: preferences.language)
    }

    var stalenessThreshold: TimeInterval {
        max(TimeInterval(preferences.refreshIntervalMinutes * 120), 15 * 60)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}