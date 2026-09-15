import Foundation
import Testing
@testable import AiUsageApp

struct UsageAmountTextFormatterTests {
    @Test
    func formatsRemainingAndTotalAmounts() {
        let formatter = UsageAmountTextFormatter(locale: Locale(identifier: "en_US"))

        #expect(formatter.string(remaining: 275_000, total: 300_000) == "275,000/300,000")
        #expect(formatter.string(remaining: 275, total: 300) == "275/300")
        #expect(formatter.string(remaining: 0, total: 300) == "0/300")
        #expect(formatter.string(remaining: 0, total: 0) == "0/0")
    }

    @Test
    func roundsBothAmountsToWholeNumbers() {
        let formatter = UsageAmountTextFormatter(locale: Locale(identifier: "en_US"))

        #expect(formatter.string(remaining: 274.5, total: 300.4) == "275/300")
        #expect(formatter.string(remaining: 999.5, total: 1_200.5) == "1,000/1,201")
    }

    @Test
    func usesLocalizedGrouping() {
        let german = UsageAmountTextFormatter(locale: Locale(identifier: "de_DE"))
        let polish = UsageAmountTextFormatter(locale: Locale(identifier: "pl_PL"))

        #expect(german.string(remaining: 275_000, total: 300_000) == "275.000/300.000")
        #expect(polish.string(remaining: 275_000, total: 300_000) == "275\u{00a0}000/300\u{00a0}000")
    }

    @Test
    func marksUnknownAmountsIndividually() {
        let formatter = UsageAmountTextFormatter(locale: Locale(identifier: "en_US"))

        #expect(formatter.string(remaining: 275, total: nil) == "275/—")
        #expect(formatter.string(remaining: nil, total: 300) == "—/300")
        #expect(formatter.string(remaining: nil, total: nil) == "—/—")
    }
}
