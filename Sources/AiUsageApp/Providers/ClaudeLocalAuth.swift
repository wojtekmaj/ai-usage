import Foundation
import LocalAuthentication
import Security

struct ClaudeOAuthCredentials: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let scopes: [String]
    let rateLimitTier: String?
}

enum ClaudeOAuthCredentialsError: LocalizedError {
    case notFound
    case decodeFailed(String)
    case missingOAuth
    case missingAccessToken
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude needs you to sign in."
        case let .decodeFailed(message):
            return "Claude Code auth could not be read: \(message)"
        case .missingOAuth:
            return "Claude needs you to sign in again."
        case .missingAccessToken:
            return "Claude needs you to sign in again."
        case let .keychainError(status):
            return "Claude Code auth could not be read from Keychain (\(status))."
        }
    }
}

final class ClaudeOAuthCredentialsStore {
    private static let keychainService = "Claude Code-credentials"
    private let rawDataLoader: () throws -> Data
    private let interactiveDataLoader: () throws -> Data
    private var rawDataState = RawDataState.notLoaded

    init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        rawDataLoader = {
            try Self.loadRawData(env: env, fileManager: fileManager, allowInteraction: false)
        }
        interactiveDataLoader = {
            try Self.loadRawData(env: env, fileManager: fileManager, allowInteraction: true)
        }
    }

    init(
        rawDataLoader: @escaping () throws -> Data,
        interactiveDataLoader: (() throws -> Data)? = nil
    ) {
        self.rawDataLoader = rawDataLoader
        self.interactiveDataLoader = interactiveDataLoader ?? rawDataLoader
    }

    func load() throws -> ClaudeOAuthCredentials {
        try Self.parse(data: rawData())
    }

    func rawJSONString() throws -> String {
        let data = try rawData()
        guard let value = String(data: data, encoding: .utf8) else {
            throw ClaudeOAuthCredentialsError.decodeFailed("Credentials are not valid UTF-8.")
        }
        return value
    }

    func reload(allowInteraction: Bool = false) throws -> String {
        let data = try (allowInteraction ? interactiveDataLoader() : rawDataLoader())
        rawDataState = .loaded(data)

        return try rawJSONString()
    }

    @discardableResult
    func reloadWithoutInteraction() -> Bool {
        guard let data = try? rawDataLoader() else {
            return false
        }

        if case let .loaded(previous) = rawDataState, previous == data {
            return false
        }

        rawDataState = .loaded(data)

        return true
    }

    static func parse(data: Data) throws -> ClaudeOAuthCredentials {
        let decoder = JSONDecoder()

        do {
            let root = try decoder.decode(Root.self, from: data)
            guard let oauth = root.claudeAiOauth else {
                throw ClaudeOAuthCredentialsError.missingOAuth
            }

            let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard accessToken.isEmpty == false else {
                throw ClaudeOAuthCredentialsError.missingAccessToken
            }

            return ClaudeOAuthCredentials(
                accessToken: accessToken,
                expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                scopes: oauth.scopes ?? [],
                rateLimitTier: oauth.rateLimitTier
            )
        } catch let error as ClaudeOAuthCredentialsError {
            throw error
        } catch {
            throw ClaudeOAuthCredentialsError.decodeFailed(error.localizedDescription)
        }
    }

    static func authFileURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let configDirectory = env["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (configDirectory?.isEmpty == false)
            ? URL(fileURLWithPath: configDirectory!, isDirectory: true)
            : fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        return root.appendingPathComponent(".credentials.json", isDirectory: false)
    }

    private static func loadFromKeychain(allowInteraction: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if allowInteraction == false {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw ClaudeOAuthCredentialsError.keychainError(status)
        }
    }

    private func rawData() throws -> Data {
        switch rawDataState {
        case .notLoaded:
            do {
                let data = try rawDataLoader()
                rawDataState = .loaded(data)
                return data
            } catch let error as ClaudeOAuthCredentialsError {
                if case .keychainError = error {
                    rawDataState = .failed(error)
                }
                throw error
            } catch {
                throw error
            }
        case let .loaded(data):
            return data
        case let .failed(error):
            throw error
        }
    }

    private static func loadRawData(
        env: [String: String],
        fileManager: FileManager,
        allowInteraction: Bool
    ) throws -> Data {
        if let keychainData = try loadFromKeychain(allowInteraction: allowInteraction) {
            return keychainData
        }
        let url = authFileURL(env: env, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ClaudeOAuthCredentialsError.notFound
        }
        return try Data(contentsOf: url)
    }

    private enum RawDataState {
        case notLoaded
        case loaded(Data)
        case failed(any Error)
    }

    private struct Root: Decodable {
        let claudeAiOauth: OAuth?
    }

    private struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let scopes: [String]?
        let rateLimitTier: String?
    }
}
