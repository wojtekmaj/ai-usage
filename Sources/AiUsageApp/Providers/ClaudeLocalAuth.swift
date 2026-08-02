import Foundation
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
            return "Claude Code auth was not found. Run `claude` and refresh."
        case let .decodeFailed(message):
            return "Claude Code auth could not be read: \(message)"
        case .missingOAuth:
            return "Claude Code auth is missing OAuth data. Run `claude` again."
        case .missingAccessToken:
            return "Claude Code auth is missing an access token. Run `claude` again."
        case let .keychainError(status):
            return "Claude Code auth could not be read from Keychain (\(status))."
        }
    }
}

enum ClaudeOAuthCredentialsStore {
    private static let keychainService = "Claude Code-credentials"

    static func load(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> ClaudeOAuthCredentials {
        try parse(data: rawData(env: env, fileManager: fileManager))
    }

    static func rawJSONString(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        let data = try rawData(env: env, fileManager: fileManager)
        guard let value = String(data: data, encoding: .utf8) else {
            throw ClaudeOAuthCredentialsError.decodeFailed("Credentials are not valid UTF-8.")
        }
        return value
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

    private static func loadFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

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

    private static func rawData(
        env: [String: String],
        fileManager: FileManager
    ) throws -> Data {
        if let keychainData = try loadFromKeychain() {
            return keychainData
        }
        let url = authFileURL(env: env, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ClaudeOAuthCredentialsError.notFound
        }
        return try Data(contentsOf: url)
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
