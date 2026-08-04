import Foundation
import Testing
@testable import AiUsageApp

@Suite("SharedCoreClientTests")
struct SharedCoreClientTests {
    private struct LargeResponse: Decodable {
        let value: String
    }

    @Test
    func decodesRustUtcKeysIntoSwiftUTCProperties() throws {
        let response = Data(
            #"""
            {
              "ok": true,
              "data": {
                "provider": "codex",
                "authState": "authenticated",
                "fetchState": "ok",
                "fetchedAtUtc": "2026-08-02T09:05:00Z",
                "metrics": [{
                  "kind": "codexWeekly",
                  "remainingFraction": 0.95,
                  "remainingValue": null,
                  "totalValue": null,
                  "unit": "percentage",
                  "resetAtUtc": "2026-08-08T03:50:00Z",
                  "lastUpdatedAtUtc": "2026-08-02T09:05:00Z",
                  "detailText": null
                }],
                "errorDescription": null,
                "sourceDescription": "Shared Rust core"
              }
            }
            """#.utf8
        )

        let snapshot = try SharedCoreClient.decodeResponse(response, as: ProviderSnapshot.self)

        #expect(snapshot.provider == .codex)
        #expect(snapshot.fetchedAtUTC != nil)
        #expect(snapshot.metrics.first?.resetAtUTC != nil)
        #expect(snapshot.metrics.first?.lastUpdatedAtUTC != nil)
    }

    @Test
    func drainsStandardOutputAndErrorWhileProcessRuns() throws {
        let outputLength = 32 * 1_024
        let script = """
        printf '%*s' \(outputLength) '' >&2
        printf '{"ok":true,"data":{"value":"'
        printf '%*s' \(outputLength) '' | tr ' ' x
        printf '"}}'
        """

        let response = try SharedCoreClient.execute(
            input: Data(),
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: 2,
            as: LargeResponse.self
        )

        #expect(response.value.count == outputLength)
    }

    @Test
    func terminatesProcessAfterTimeout() throws {
        let start = Date()

        do {
            _ = try SharedCoreClient.execute(
                input: Data(),
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.1,
                as: LargeResponse.self
            )
            Issue.record("Expected the shared core process to time out.")
        } catch let error as SharedCoreError {
            guard case .timedOut = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }

        #expect(Date().timeIntervalSince(start) < 2)
    }
}
