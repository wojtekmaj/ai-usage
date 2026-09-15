import Foundation
import Testing
@testable import AiUsageApp

struct DollarTextFormatterTests {
    @Test
    func formatsDollarsWithCents() {
        let formatter = DollarTextFormatter(locale: Locale(identifier: "en_US"))

        #expect(formatter.string(for: 23.4) == "$23.40")
        #expect(formatter.string(for: 0) == "$0.00")
        #expect(formatter.string(for: 0.01) == "$0.01")
        #expect(formatter.string(for: 1_234.567) == "$1,234.57")
        #expect(formatter.string(remaining: 23.4, total: 30) == "$23.40/$30.00")
    }

    @Test
    func localizesNumbersWhileKeepingTheDollarSymbol() {
        let german = DollarTextFormatter(locale: Locale(identifier: "de_DE"))
        let polish = DollarTextFormatter(locale: Locale(identifier: "pl_PL"))

        #expect(german.string(remaining: 1_234.5, total: 3_000) == "$1.234,50/$3.000,00")
        #expect(polish.string(for: 12_345.5) == "$12\u{00a0}345,50")
    }

    @Test
    func marksUnknownAmountsIndividually() {
        let formatter = DollarTextFormatter(locale: Locale(identifier: "en_US"))

        #expect(formatter.string(for: nil) == "—")
        #expect(formatter.string(remaining: 23.4, total: nil) == "$23.40/—")
        #expect(formatter.string(remaining: nil, total: 30) == "—/$30.00")
        #expect(formatter.string(remaining: nil, total: nil) == "—/—")
    }
}
