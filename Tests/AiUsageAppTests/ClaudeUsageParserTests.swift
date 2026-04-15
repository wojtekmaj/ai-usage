import Foundation
import Testing
@testable import AiUsageApp

struct ClaudeUsageParserTests {
    @Test
    func parsesClaudeOAuthUsageResponse() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 0.25,
                "resets_at": "2026-04-10T18:00:00Z"
              },
              "seven_day": {
                "utilization": 0.6,
                "resets_at": "2026-04-14T00:00:00Z"
              }
            }
            """.utf8
        )

        let metrics = try ClaudeUsageParser.parseMetrics(from: data, now: now)

        #expect(metrics.count == 2)
        #expect(metrics.first { $0.kind == .claudeFiveHour }?.remainingFraction == 0.75)
        #expect(metrics.first { $0.kind == .claudeWeekly }?.remainingFraction == 0.4)
        #expect(metrics.first { $0.kind == .claudeWeekly }?.resetAtUTC == Date(timeIntervalSince1970: 1_776_124_800))
    }

    @Test
    func fallsBackToOAuthAppsWeeklyWindow() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let response = ClaudeOAuthUsageResponse(
            fiveHour: nil,
            sevenDay: nil,
            sevenDayOAuthApps: ClaudeUsageWindow(
                utilization: 0.1,
                resetsAt: "2026-04-14T00:00:00.000Z"
            )
        )

        let metrics = ClaudeUsageParser.parseMetrics(from: response, now: now)

        #expect(metrics.first { $0.kind == .claudeWeekly }?.remainingFraction == 0.9)
        #expect(metrics.first { $0.kind == .claudeFiveHour }?.remainingFraction == nil)
    }
}
