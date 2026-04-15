import Foundation

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
    let lastRefresh: Date?

    var needsRefresh: Bool {
        guard let lastRefresh else {
            return refreshToken.isEmpty == false
        }

        let refreshInterval: TimeInterval = 8 * 24 * 60 * 60
        return refreshToken.isEmpty == false && Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
}

enum CodexOAuthCredentialsError: LocalizedError {
    case notFound
    case decodeFailed(String)
    case missingTokens

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Codex CLI auth was not found. Run `codex login` and refresh."
        case let .decodeFailed(message):
            return "Codex CLI auth could not be read: \(message)"
        case .missingTokens:
            return "Codex CLI auth exists but contains no usable tokens. Run `codex login` again."
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

    static func save(
        _ credentials: CodexOAuthCredentials,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let url = authFileURL(env: env, fileManager: fileManager)

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId {
            tokens["account_id"] = accountId
        }

        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
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

    static func chatGPTBaseURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (codexHome?.isEmpty == false)
            ? URL(fileURLWithPath: codexHome!, isDirectory: true)
            : fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let configURL = root.appendingPathComponent("config.toml", isDirectory: false)
        let defaultURL = URL(string: "https://chatgpt.com/backend-api/")!

        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return defaultURL
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty == false else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "chatgpt_base_url" else {
                continue
            }

            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }

            let normalized = normalizeBaseURL(value)
            if let url = URL(string: normalized) {
                return url
            }
        }

        return defaultURL
    }

    private static func normalizeBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "https://chatgpt.com/backend-api"
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if (trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com"))
            && trimmed.contains("/backend-api") == false {
            trimmed += "/backend-api"
        }

        return trimmed + "/"
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

enum CodexTokenRefresher {
    private static let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    enum RefreshError: LocalizedError {
        case expired
        case revoked
        case reused
        case networkError(Error)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .expired:
                return "Codex CLI refresh token expired. Run `codex login` again."
            case .revoked:
                return "Codex CLI refresh token was revoked. Run `codex login` again."
            case .reused:
                return "Codex CLI refresh token was already used. Run `codex login` again."
            case let .networkError(error):
                return "Refreshing Codex CLI auth failed: \(error.localizedDescription)"
            case let .invalidResponse(message):
                return "Codex auth refresh failed: \(message)"
            }
        }
    }

    static func refresh(_ credentials: CodexOAuthCredentials) async throws -> CodexOAuthCredentials {
        guard credentials.refreshToken.isEmpty == false else {
            return credentials
        }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RefreshError.invalidResponse("No HTTP response")
            }

            if httpResponse.statusCode == 401 {
                switch extractErrorCode(from: data)?.lowercased() {
                case "refresh_token_reused":
                    throw RefreshError.reused
                case "refresh_token_invalidated":
                    throw RefreshError.revoked
                default:
                    throw RefreshError.expired
                }
            }

            guard httpResponse.statusCode == 200 else {
                throw RefreshError.invalidResponse("Status \(httpResponse.statusCode)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RefreshError.invalidResponse("Invalid JSON")
            }

            return CodexOAuthCredentials(
                accessToken: (json["access_token"] as? String) ?? credentials.accessToken,
                refreshToken: (json["refresh_token"] as? String) ?? credentials.refreshToken,
                idToken: (json["id_token"] as? String) ?? credentials.idToken,
                accountId: credentials.accountId,
                lastRefresh: Date()
            )
        } catch let error as RefreshError {
            throw error
        } catch {
            throw RefreshError.networkError(error)
        }
    }

    private static func extractErrorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? String {
            return code
        }

        if let error = json["error"] as? String {
            return error
        }

        return json["code"] as? String
    }
}
