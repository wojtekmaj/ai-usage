import Darwin
import Foundation

struct SharedCoreClient: Sendable {
    private static let refreshTimeout: TimeInterval = 30

    func refresh(
        provider: ProviderID,
        copilotToken: String?,
        claudeCredentialsJSON: String?,
        now: Date
    ) async throws -> ProviderSnapshot {
        var request: [String: Any] = [
            "command": "refresh",
            "provider": provider.rawValue,
            "now": ISO8601DateFormatter().string(from: now),
        ]
        if let copilotToken {
            request["copilotToken"] = copilotToken
        }
        if let claudeCredentialsJSON {
            request["claudeCredentialsJson"] = claudeCredentialsJSON
        }
        let input = try JSONSerialization.data(withJSONObject: request)
        return try await Task.detached(priority: .utility) {
            try Self.execute(input: input, timeout: Self.refreshTimeout, as: ProviderSnapshot.self)
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
        guard response.ok, let data = response.data else {
            throw SharedCoreError.requestFailed(response.error?.message ?? "The shared core failed.")
        }
        return data
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
        let ok: Bool
        let data: T?
        let error: CoreError?
    }

    private struct CoreError: Decodable {
        let message: String
    }

    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }
}

enum SharedCoreError: LocalizedError {
    case executableNotFound
    case processFailed(Int32, String)
    case requestFailed(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The AI Usage shared core executable was not found."
        case let .processFailed(status, message):
            return "The AI Usage shared core exited with status \(status): \(message)"
        case let .requestFailed(message):
            return message
        case let .timedOut(timeout):
            return "The AI Usage shared core timed out after \(Int(timeout)) seconds."
        }
    }
}
