import Foundation

struct CopilotDeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct CopilotAccessTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

enum CopilotDeviceFlowError: LocalizedError {
    case invalidResponse
    case authorizationPending
    case expiredToken
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub sign-in returned an unexpected response."
        case .authorizationPending:
            return "GitHub sign-in is still waiting for approval."
        case .expiredToken:
            return "GitHub sign-in expired before it was completed."
        case let .authorizationFailed(error):
            return "GitHub sign-in failed: \(error)"
        }
    }
}

enum CopilotDeviceFlow {
    private static let clientID = "Iv1.b507a08c87ecfe98"
    private static let scopes = "read:user"

    static func requestDeviceCode() async throws -> CopilotDeviceCodeResponse {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody([
            "client_id": clientID,
            "scope": scopes,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CopilotDeviceFlowError.invalidResponse
        }

        return try JSONDecoder().decode(CopilotDeviceCodeResponse.self, from: data)
    }

    static func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        while true {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()

            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                case "expired_token":
                    throw CopilotDeviceFlowError.expiredToken
                default:
                    throw CopilotDeviceFlowError.authorizationFailed(error)
                }
            }

            if let tokenResponse = try? JSONDecoder().decode(CopilotAccessTokenResponse.self, from: data) {
                return tokenResponse.accessToken
            }

            throw CopilotDeviceFlowError.invalidResponse
        }
    }

    private static func formURLEncodedBody(_ parameters: [String: String]) -> Data {
        let pairs = parameters
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }
            .joined(separator: "&")

        return Data(pairs.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
