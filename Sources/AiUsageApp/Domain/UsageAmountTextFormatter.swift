import Foundation

struct UsageAmountTextFormatter {
    var locale: Locale

    func string(remaining: Double?, total: Double?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp

        func format(_ value: Double?) -> String {
            guard let value else {
                return "—"
            }

            return formatter.string(from: NSNumber(value: value)) ?? "—"
        }

        return "\(format(remaining))/\(format(total))"
    }
}
