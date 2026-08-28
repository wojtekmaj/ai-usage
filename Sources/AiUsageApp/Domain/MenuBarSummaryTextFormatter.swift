import Foundation

enum MenuBarSummaryTextFormatter {
    static func string(for value: MenuBarSummaryValue) -> String {
        switch value {
        case let .percentage(fraction):
            guard let fraction else {
                return "-%"
            }

            return "\(Int((fraction * 100).rounded()))%"
        case let .count(count):
            guard let count else {
                return "-"
            }

            return compactCount(count)
        }
    }

    private static func compactCount(_ count: Double) -> String {
        let magnitude = abs(count)
        let divisor: Double
        let suffix: String

        switch magnitude {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "k"
        default:
            return "\(Int(count.rounded()))"
        }

        let scaled = count / divisor
        let format = abs(scaled) < 10 ? "%.1f" : "%.0f"
        var text = String(format: format, locale: Locale(identifier: "en_US_POSIX"), scaled)

        if text.hasSuffix(".0") {
            text.removeLast(2)
        }

        return text + suffix
    }
}
