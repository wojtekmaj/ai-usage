import Foundation

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let withoutBuild = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.parseCoreIdentifier(core[0]),
              let minor = Self.parseCoreIdentifier(core[1]),
              let patch = Self.parseCoreIdentifier(core[2]) else {
            return nil
        }

        let prerelease = parts.count == 2
            ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            : []
        guard prerelease.allSatisfy(Self.isValidPrereleaseIdentifier) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return lhs.prerelease.isEmpty == false && rhs.prerelease.isEmpty
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            if let leftNumber = Int(left), let rightNumber = Int(right) {
                return leftNumber < rightNumber
            }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func parseCoreIdentifier(_ value: Substring) -> Int? {
        guard value.isEmpty == false,
              value.allSatisfy(\.isNumber),
              (value.count == 1 || value.first != "0") else {
            return nil
        }
        return Int(value)
    }

    private static func isValidPrereleaseIdentifier(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            return false
        }
        return value.allSatisfy(\.isNumber) == false || value.count == 1 || value.first != "0"
    }
}

struct AppRelease: Codable, Equatable {
    let version: String
    let pageURL: URL
}

enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case failed
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var status: UpdateCheckStatus = .idle

    let currentVersion: String

    private let endpoint = URL(string: "https://api.github.com/repos/wojtekmaj/ai-usage/releases?per_page=20")!
    private let session: URLSession
    private let defaults: UserDefaults
    private let notificationService: NotificationService
    private let now: () -> Date
    private let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Key {
        static let lastCheck = "updates.lastCheck"
        static let etag = "updates.etag"
        static let cachedRelease = "updates.cachedRelease"
        static let lastNotifiedVersion = "updates.lastNotifiedVersion"
    }

    init(
        currentVersion: String,
        notificationService: NotificationService,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.notificationService = notificationService
        self.session = session
        self.defaults = defaults
        self.now = now

        if let cachedData = defaults.data(forKey: Key.cachedRelease),
           let cached = try? JSONDecoder().decode(AppRelease.self, from: cachedData),
           cached.pageURL.scheme == "https",
           cached.pageURL.host == "github.com",
           let installed = SemanticVersion(currentVersion),
           let latest = SemanticVersion(cached.version),
           installed < latest {
            status = .available(cached)
        }
    }

    func checkIfDue(localizer: Localizer) async {
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        guard lastCheck.map({ now().timeIntervalSince($0) >= checkInterval }) ?? true else {
            return
        }
        await check(manual: false, localizer: localizer)
    }

    func checkManually(localizer: Localizer) async {
        await check(manual: true, localizer: localizer)
    }

    private func check(manual: Bool, localizer: Localizer) async {
        guard status != .checking else { return }
        status = .checking

        do {
            let release = try await fetchLatestApplicableRelease()
            defaults.set(now(), forKey: Key.lastCheck)

            guard let installed = SemanticVersion(currentVersion),
                  let latest = SemanticVersion(release.version) else {
                throw UpdateCheckError.invalidVersion
            }

            if installed < latest {
                status = .available(release)
                if manual == false,
                   defaults.string(forKey: Key.lastNotifiedVersion) != release.version {
                    notificationService.showUpdateAvailable(release: release, localizer: localizer)
                    defaults.set(release.version, forKey: Key.lastNotifiedVersion)
                }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed
        }
    }

    private func fetchLatestApplicableRelease() async throws -> AppRelease {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AI-Usage/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag = defaults.string(forKey: Key.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        if response.statusCode == 304,
           let cachedData = defaults.data(forKey: Key.cachedRelease),
           let cached = try? JSONDecoder().decode(AppRelease.self, from: cachedData),
           cached.pageURL.scheme == "https",
           cached.pageURL.host == "github.com" {
            return cached
        }
        guard response.statusCode == 200 else {
            throw UpdateCheckError.invalidResponse
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard let installed = SemanticVersion(currentVersion) else {
            throw UpdateCheckError.invalidVersion
        }
        let acceptsPrereleases = installed.prerelease.isEmpty == false
        let applicable = releases.compactMap { release -> (AppRelease, SemanticVersion)? in
            guard release.draft == false,
                  acceptsPrereleases || release.prerelease == false,
                  let version = SemanticVersion(release.tagName),
                  release.pageURL.scheme == "https",
                  release.pageURL.host == "github.com" else {
                return nil
            }
            return (AppRelease(version: String(release.tagName.dropPrefix("v")), pageURL: release.pageURL), version)
        }
        guard let latest = applicable.max(by: { $0.1 < $1.1 })?.0 else {
            throw UpdateCheckError.noRelease
        }

        if let etag = response.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: Key.etag)
        }
        defaults.set(try JSONEncoder().encode(latest), forKey: Key.cachedRelease)
        return latest
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let pageURL: URL
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case prerelease
        case draft
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
    case invalidVersion
    case noRelease
}

private extension String {
    func dropPrefix(_ prefix: Character) -> Substring {
        first == prefix ? dropFirst() : self[...]
    }
}
