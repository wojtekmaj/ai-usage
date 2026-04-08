import Foundation

struct ResetDateTextFormatter {
    let locale: Locale
    let timeZone: TimeZone
    let calendar: Calendar

    init(
        locale: Locale,
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.locale = locale
        self.timeZone = timeZone

        var adjustedCalendar = calendar
        adjustedCalendar.locale = locale
        adjustedCalendar.timeZone = timeZone
        self.calendar = adjustedCalendar
    }

    func string(from resetAtUTC: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone

        if resetAtUTC > now, calendar.isDate(resetAtUTC, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }

        return formatter.string(from: resetAtUTC)
    }
}
