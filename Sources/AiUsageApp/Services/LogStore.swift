import Combine
import Foundation

enum AppLogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
}

struct AppLogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let timestampUTC: Date
    let level: AppLogLevel
    let category: String
    let message: String

    init(id: UUID = UUID(), timestampUTC: Date = Date(), level: AppLogLevel, category: String, message: String) {
        self.id = id
        self.timestampUTC = timestampUTC
        self.level = level
        self.category = category
        self.message = message
    }
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [AppLogEntry]

    private let defaults: UserDefaults
    private let key = "applicationLogs"
    private let maximumEntries = 300

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode([AppLogEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    func append(level: AppLogLevel = .info, category: String, message: String) {
        entries.append(AppLogEntry(level: level, category: category, message: message))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    var exportText: String {
        entries.map { entry in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return "[\(formatter.string(from: entry.timestampUTC))] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else {
            return
        }

        defaults.set(data, forKey: key)
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