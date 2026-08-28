import Testing
@testable import AiUsageApp

struct MenuBarSummaryTextFormatterTests {
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
