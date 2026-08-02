import Foundation

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
    let lastRefresh: Date?
}

enum CodexOAuthCredentialsError: LocalizedError {
    case notFound
    case decodeFailed(String)
    case missingTokens

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Codex auth was not found. Sign in to the Codex desktop app, or run `codex login` for Codex CLI, then refresh."
        case let .decodeFailed(message):
            return "Codex auth could not be read: \(message)"
        case .missingTokens:
            return "Codex auth exists but contains no usable tokens. Sign in to Codex again."
        }
    }
}

enum CodexOAuthCredentialsStore {
    static func load(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> CodexOAuthCredentials {
        let url = authFileURL(env: env, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CodexOAuthCredentialsError.notFound
        }

        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> CodexOAuthCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexOAuthCredentialsError.decodeFailed("Invalid JSON")
        }

        if let apiKey = cleaned(json["OPENAI_API_KEY"]),
           apiKey.isEmpty == false {
            return CodexOAuthCredentials(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountId: nil,
                lastRefresh: nil
            )
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            throw CodexOAuthCredentialsError.missingTokens
        }

        guard let accessToken = cleaned(tokens["access_token"]) ?? cleaned(tokens["accessToken"]),
              accessToken.isEmpty == false else {
            throw CodexOAuthCredentialsError.missingTokens
        }

        let refreshToken = cleaned(tokens["refresh_token"]) ?? cleaned(tokens["refreshToken"]) ?? ""
        let idToken = cleaned(tokens["id_token"]) ?? cleaned(tokens["idToken"])
        let accountId = cleaned(tokens["account_id"]) ?? cleaned(tokens["accountId"])

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountId: accountId,
            lastRefresh: parseLastRefresh(from: json["last_refresh"])
        )
    }

    static func authFileURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (codexHome?.isEmpty == false)
            ? URL(fileURLWithPath: codexHome!, isDirectory: true)
            : fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return root.appendingPathComponent("auth.json", isDirectory: false)
    }

    private static func cleaned(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private static func parseLastRefresh(from value: Any?) -> Date? {
        guard let string = value as? String, string.isEmpty == false else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
