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
      "credits": [
        "balance": "335.9650000000",
      ],
    ]

    let metrics = try CodexHTMLParser.parse(apiPayload: payload, now: now)

    #expect(metrics.first(where: { $0.kind == .codexFiveHour })?.remainingFraction == 1)
    #expect(metrics.first(where: { $0.kind == .codexWeekly })?.remainingFraction == 0.95)
    #expect(metrics.first(where: { $0.kind == .codexCredits })?.remainingValue == 335.965)
  }

    @Test
    func parsesUsageWindowsAndCreditsFromMixedHtml() throws {
        let now = Date(timeIntervalSince1970: 1_744_128_000)
        let html = """
        <html>
          <body>
            <section>
              <h2>5-hour limit</h2>
              <div>62% remaining</div>
              <script>window.__usage={fiveHourResetAt:"2026-04-09T15:00:00Z"}</script>
            </section>
            <section>
              <h2>Weekly limit</h2>
              <div>71% remaining</div>
              <div data-reset="2026-04-13T00:00:00Z"></div>
            </section>
            <section>
              <h2>Credits balance</h2>
              <div>120</div>
            </section>
          </body>
        </html>
        """
        let text = """
        5-hour limit 62% remaining resets Apr 9, 2026, 3:00 PM
        Weekly limit 71% remaining resets Apr 13, 2026, 12:00 AM
        Credits balance 120
        """

        let metrics = try CodexHTMLParser.parse(text: text, html: html, now: now)

        #expect(metrics.count == 3)
        #expect(metrics.first(where: { $0.kind == .codexFiveHour })?.remainingFraction == 0.62)
        #expect(metrics.first(where: { $0.kind == .codexWeekly })?.remainingFraction == 0.71)
        #expect(metrics.first(where: { $0.kind == .codexCredits })?.remainingValue == 120)
    }
}
