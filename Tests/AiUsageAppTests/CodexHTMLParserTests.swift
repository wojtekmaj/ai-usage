import Foundation
import Testing
@testable import AiUsageApp

struct CodexHTMLParserTests {
    @Test
    func parsesWhamUsageResponse() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 0,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_775_675_446,
                ],
                "secondary_window": [
                    "used_percent": 5,
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_776_243_072,
                ],
            ],
            "additional_rate_limits": [
                [
                    "limit_name": "GPT-5.3-Codex-Spark",
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 40,
                            "limit_window_seconds": 18_000,
                            "reset_at": 1_775_680_000,
                        ],
                        "secondary_window": [
                            "used_percent": 25,
                            "limit_window_seconds": 604_800,
                            "reset_at": 1_776_250_000,
                        ],
                    ],
                ],
            ],
            "credits": [
                "balance": "335.9650000000",
            ],
        ]

        let metrics = try CodexHTMLParser.parse(apiPayload: payload, now: now)

        #expect(metrics.first(where: { $0.kind == .codexFiveHour })?.remainingFraction == 1)
        #expect(metrics.first(where: { $0.kind == .codexWeekly })?.remainingFraction == 0.95)
        #expect(metrics.first(where: { $0.kind == .codexSparkFiveHour })?.remainingFraction == 0.6)
        #expect(metrics.first(where: { $0.kind == .codexSparkWeekly })?.remainingFraction == 0.75)
        #expect(metrics.first(where: { $0.kind == .codexCredits })?.remainingValue == 335.965)
    }

    @Test
    func fillsMissingCodexMetricsWithEmptyPlaceholders() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 20,
                    "reset_at": 1_775_675_446,
                ],
            ],
        ]

        let metrics = try CodexHTMLParser.parse(apiPayload: payload, now: now)

        #expect(metrics.count == 5)
        #expect(metrics.first(where: { $0.kind == .codexFiveHour })?.remainingFraction == 0.8)
        #expect(metrics.first(where: { $0.kind == .codexWeekly })?.remainingFraction == nil)
        #expect(metrics.first(where: { $0.kind == .codexSparkFiveHour })?.remainingFraction == nil)
        #expect(metrics.first(where: { $0.kind == .codexSparkWeekly })?.remainingFraction == nil)
        #expect(metrics.first(where: { $0.kind == .codexCredits })?.remainingValue == nil)
    }
}
