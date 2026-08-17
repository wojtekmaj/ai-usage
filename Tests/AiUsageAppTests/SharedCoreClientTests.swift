import Foundation
import Testing
@testable import AiUsageApp

@Suite("SharedCoreClientTests", .serialized)
struct SharedCoreClientTests {
    private struct LargeResponse: Decodable {
        let value: String
    }

    @Test
    func decodesRustUtcKeysIntoSwiftUTCProperties() throws {
        let response = Data(
            #"""
            {
              "protocolVersion": 1,
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
    func rejectsAnIncompatibleProtocolVersion() throws {
        let response = Data(
            #"{"protocolVersion":2,"ok":true,"data":{"value":"ignored"}}"#.utf8
        )

        #expect(throws: SharedCoreError.self) {
            try SharedCoreClient.decodeResponse(response, as: LargeResponse.self)
        }
    }

    @Test
    func rejectsAnUnversionedLegacyResponse() throws {
        let response = Data(#"{"ok":true,"data":{"value":"ignored"}}"#.utf8)

        #expect(throws: SharedCoreError.self) {
            try SharedCoreClient.decodeResponse(response, as: LargeResponse.self)
        }
    }

    @Test
    func evaluatesBatchedSchedulesThroughSharedCore() async throws {
        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let metric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.3,
            remainingValue: 300,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: Date(timeIntervalSince1970: 1_777_420_800), // 2026-05-01 00:00:00 UTC
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let results = try await SharedCoreClient().evaluateSchedules(
            [
                ScheduleEvaluationRequest(metric: metric, direction: .ahead, previousState: nil),
                ScheduleEvaluationRequest(metric: metric, direction: .behind, previousState: nil),
            ],
            now: now
        )

        #expect(results.count == 2)
        let ahead = try #require(results[0])
        let behind = try #require(results[1])
        #expect(ahead.direction == .ahead)
        #expect(ahead.shouldNotify)
        #expect(abs(ahead.expectedRemaining - 0.51) < 0.01)
        #expect(ahead.actualRemaining == 0.3)
        #expect(behind.direction == .behind)
        #expect(behind.shouldNotify == false)
    }

    @Test
    func drainsStandardOutputAndErrorWhileProcessRuns() throws {
        let outputLength = 32 * 1_024
        let script = """
        printf '%*s' \(outputLength) '' >&2
        printf '{"protocolVersion":1,"ok":true,"data":{"value":"'
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
