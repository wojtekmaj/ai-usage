import Foundation

struct DollarTextFormatter {
    var locale: Locale

    func string(for amount: Double?) -> String {
        guard let amount, amount.isFinite else {
            return "—"
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp

        guard let text = formatter.string(from: NSNumber(value: amount)) else {
            return "—"
        }

        return "$\(text)"
    }

    func string(remaining: Double?, total: Double?) -> String {
        "\(string(for: remaining))/\(string(for: total))"
    }
}
