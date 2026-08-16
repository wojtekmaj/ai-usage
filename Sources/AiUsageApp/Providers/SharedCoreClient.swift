import Darwin
import Foundation

struct SharedCoreClient: Sendable {
    static let protocolVersion = 1
    private static let refreshTimeout: TimeInterval = 40
    private static let requestTimeout: TimeInterval = 40
    private static let preheatTimeout: TimeInterval = 100

    func refresh(
        copilotToken: String?,
        claudeCredentialsJSON: String?,
        now: Date
    ) async throws -> [ProviderSnapshot] {
        let input = try Self.encode(
            RefreshRequest(
                protocolVersion: Self.protocolVersion,
                command: "refresh",
                copilotToken: copilotToken,
                claudeCredentialsJson: claudeCredentialsJSON,
                now: now
            )
        )
        let snapshots = try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.refreshTimeout, as: [ProviderSnapshot].self)
        }.value
        let providers = snapshots.map(\.provider)
        guard snapshots.count == ProviderID.allCases.count,
              Set(providers) == Set(ProviderID.allCases) else {
            throw SharedCoreError.invalidResponse("A refresh must return exactly one snapshot for every provider.")
        }
        return snapshots
    }

    func evaluateSchedules(
        _ evaluations: [ScheduleEvaluationRequest],
        now: Date
    ) async throws -> [ScheduleEvaluationResult?] {
        guard evaluations.isEmpty == false else {
            return []
        }
        let input = try Self.encode(
            EvaluateSchedulesRequest(
                protocolVersion: Self.protocolVersion,
                command: "evaluateSchedules",
                evaluations: evaluations,
                now: now
            )
        )
        let results = try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.requestTimeout, as: [ScheduleEvaluationResult?].self)
        }.value
        guard results.count == evaluations.count else {
            throw SharedCoreError.invalidResponse("Schedule evaluation returned an unexpected number of results.")
        }
        return results
    }

    func requestCopilotDeviceCode() async throws -> CopilotDeviceCode {
        let input = try Self.encode(
            CommandRequest(protocolVersion: Self.protocolVersion, command: "requestCopilotDeviceCode")
        )
        return try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.requestTimeout, as: CopilotDeviceCode.self)
        }.value
    }

    func pollCopilotToken(deviceCode: String, defaultInterval: Int) async throws -> CopilotPollResult {
        let input = try Self.encode(
            PollCopilotTokenRequest(
                protocolVersion: Self.protocolVersion,
                command: "pollCopilotToken",
                deviceCode: deviceCode,
                defaultInterval: defaultInterval
            )
        )
        return try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.requestTimeout, as: CopilotPollResult.self)
        }.value
    }

    func preheatCodex() async throws {
        let input = try Self.encode(
            CommandRequest(protocolVersion: Self.protocolVersion, command: "preheatCodex")
        )
        let _: Bool = try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.preheatTimeout, as: Bool.self)
        }.value
    }

    static func execute<T: Decodable>(
        input: Data,
        executableURL: URL? = nil,
        arguments: [String] = [],
        timeout: TimeInterval,
        as type: T.Type
    ) throws -> T {
        let process = Process()
        process.executableURL = try executableURL ?? self.executableURL()
        process.arguments = arguments

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()

        let output = DataBox()
        let errorOutput = DataBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.value = standardOutput.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorOutput.value = standardError.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        standardInput.fileHandleForWriting.write(input)
        try standardInput.fileHandleForWriting.close()

        guard terminationSemaphore.wait(timeout: .now() + timeout) == .success else {
            terminate(process, terminationSemaphore: terminationSemaphore)
            readers.wait()
            throw SharedCoreError.timedOut(timeout)
        }

        readers.wait()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput.value, encoding: .utf8) ?? ""
            throw SharedCoreError.processFailed(process.terminationStatus, message)
        }

        return try decodeResponse(output.value, as: type)
    }

    private static func terminate(
        _ process: Process,
        terminationSemaphore: DispatchSemaphore
    ) {
        if process.isRunning {
            process.terminate()
        }
        if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    static func decodeResponse<T: Decodable>(_ output: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            let key = codingPath.last?.stringValue ?? ""
            let normalizedKey = key.hasSuffix("Utc")
                ? String(key.dropLast(3)) + "UTC"
                : key
            return CoreCodingKey(stringValue: normalizedKey)
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date: \(value)"
                )
            }
            return date
        }
        let response = try decoder.decode(CoreResponse<T>.self, from: output)
        guard response.protocolVersion == protocolVersion else {
            throw SharedCoreError.incompatibleProtocol(
                expected: protocolVersion,
                actual: response.protocolVersion
            )
        }
        guard response.ok, let data = response.data else {
            throw SharedCoreError.requestFailed(
                code: response.error?.code ?? "unknown",
                message: response.error?.message ?? "The shared core failed."
            )
        }
        return data
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .custom { codingPath in
            let key = codingPath.last?.stringValue ?? ""
            let normalizedKey = key.hasSuffix("UTC")
                ? String(key.dropLast(3)) + "Utc"
                : key
            return CoreCodingKey(stringValue: normalizedKey)
        }
        return try encoder.encode(value)
    }

    private struct CoreCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private static func executableURL() throws -> URL {
        if let appExecutable = Bundle.main.executableURL {
            let bundled = appExecutable.deletingLastPathComponent().appendingPathComponent("ai-usage-core")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for relativePath in ["target/debug/ai-usage-core", "target/release/ai-usage-core"] {
            let candidate = root.appendingPathComponent(relativePath)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw SharedCoreError.executableNotFound
    }

    private struct CoreResponse<T: Decodable>: Decodable {
        let protocolVersion: Int?
        let ok: Bool
        let data: T?
        let error: CoreError?
    }

    private struct CoreError: Decodable {
        let code: String?
        let message: String
    }

    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }
}

enum SharedCoreError: LocalizedError {
    case executableNotFound
    case incompatibleProtocol(expected: Int, actual: Int?)
    case invalidResponse(String)
    case processFailed(Int32, String)
    case requestFailed(code: String, message: String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The AI Usage shared core executable was not found."
        case let .incompatibleProtocol(expected, actual):
            let actualDescription = actual.map { "protocol version \($0)" } ?? "an unversioned protocol"
            return "The AI Usage shared core uses \(actualDescription), but the app requires protocol version \(expected)."
        case let .invalidResponse(message):
            return "The AI Usage shared core returned an invalid response: \(message)"
        case let .processFailed(status, message):
            return "The AI Usage shared core exited with status \(status): \(message)"
        case let .requestFailed(code, message):
            return "\(message) (\(code))"
        case let .timedOut(timeout):
            return "The AI Usage shared core timed out after \(Int(timeout)) seconds."
        }
    }
}

struct ScheduleEvaluationRequest: Encodable, Sendable {
    let metric: UsageMetric
    let direction: UsageAlertDirection
    let previousState: UsageAlertState?
}

struct CopilotDeviceCode: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
}

struct CopilotPollResult: Decodable, Sendable {
    let status: String
    let retryAfterSeconds: Int?
    let accessToken: String?
}

private struct RefreshRequest: Encodable {
    let protocolVersion: Int
    let command: String
    let copilotToken: String?
    let claudeCredentialsJson: String?
    let now: Date
}

private struct EvaluateSchedulesRequest: Encodable {
    let protocolVersion: Int
    let command: String
    let evaluations: [ScheduleEvaluationRequest]
    let now: Date
}

private struct CommandRequest: Encodable {
    let protocolVersion: Int
    let command: String
}

private struct PollCopilotTokenRequest: Encodable {
    let protocolVersion: Int
    let command: String
    let deviceCode: String
    let defaultInterval: Int
}
