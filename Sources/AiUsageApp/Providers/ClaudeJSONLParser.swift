import Foundation

enum ClaudeJSONLParser {
    private struct Entry: Decodable {
        let costUSD: Double?
        let model: String?
        let timestamp: Date?
        let message: MessageWrapper?

        enum CodingKeys: String, CodingKey {
            case costUSD
            case model
            case timestamp
            case message
        }

        // Some entries nest the model inside a "message" object
        struct MessageWrapper: Decodable {
            let model: String?
        }

        var resolvedModel: String? {
            model ?? message?.model
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            message = try container.decodeIfPresent(MessageWrapper.self, forKey: .message)

            // timestamp may be ISO8601 string or unix epoch number
            if let raw = try? container.decodeIfPresent(String.self, forKey: .timestamp) {
                timestamp = parseISO(raw)
            } else if let epoch = try? container.decodeIfPresent(Double.self, forKey: .timestamp) {
                timestamp = Date(timeIntervalSince1970: epoch)
            } else {
                timestamp = nil
            }
        }
    }

    // MARK: - Public API

    /// Returns the fraction of requests in the past 7 days that used a claude-sonnet model.
    static func sonnetFraction(referenceDate: Date) -> Double? {
        let entries = loadEntries(since: referenceDate.addingTimeInterval(-7 * 24 * 3600))
        guard entries.isEmpty == false else { return nil }

        let withModel = entries.filter { $0.resolvedModel != nil }
        guard withModel.isEmpty == false else { return nil }

        let sonnetCount = withModel.filter { isSonnet($0.resolvedModel!) }.count
        return Double(sonnetCount) / Double(withModel.count)
    }

    // MARK: - Internals

    private static func loadEntries(since cutoff: Date) -> [Entry] {
        guard let projectsDir = claudeProjectsDirectory() else { return [] }

        var entries: [Entry] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.isEmpty == false,
                      let data = trimmed.data(using: .utf8),
                      let entry = try? decoder.decode(Entry.self, from: data) else { continue }

                if let ts = entry.timestamp, ts < cutoff { continue }
                entries.append(entry)
            }
        }

        return entries
    }

    private static func claudeProjectsDirectory() -> URL? {
        let base: URL
        if let customDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            base = URL(fileURLWithPath: customDir)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        }
        let dir = base.appendingPathComponent("projects")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return dir
    }

    private static func isSonnet(_ model: String) -> Bool {
        model.lowercased().contains("sonnet")
    }

    private static func parseISO(_ string: String) -> Date? {
        let withMillis = ISO8601DateFormatter()
        withMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withMillis.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
