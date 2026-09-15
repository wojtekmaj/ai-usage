import Foundation
import Testing
@testable import AiUsageApp

struct MenuBarSummaryTextFormatterTests {
    @Test
    func formatsRemainingDollars() {
        let locale = Locale(identifier: "en_US")

        #expect(MenuBarSummaryTextFormatter.string(for: .dollars(23.4), locale: locale) == "$23.40")
        #expect(MenuBarSummaryTextFormatter.string(for: .dollars(0), locale: locale) == "$0.00")
        #expect(MenuBarSummaryTextFormatter.string(for: .dollars(nil), locale: locale) == "-")
        #expect(MenuBarSummaryTextFormatter.string(for: .dollars(23.4), locale: Locale(identifier: "pl_PL")) == "$23,40")
    }

    @Test
    func formatsPercentages() {
        #expect(MenuBarSummaryTextFormatter.string(for: .percentage(0.275)) == "28%")
        #expect(MenuBarSummaryTextFormatter.string(for: .percentage(nil)) == "-%")
    }

    @Test
    func formatsCountsCompactly() {
        #expect(MenuBarSummaryTextFormatter.string(for: .count(9)) == "9")
        #expect(MenuBarSummaryTextFormatter.string(for: .count(1_250)) == "1.2k")
        #expect(MenuBarSummaryTextFormatter.string(for: .count(275_000)) == "275k")
        #expect(MenuBarSummaryTextFormatter.string(for: .count(nil)) == "-")
    }
}
