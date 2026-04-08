import Foundation
import Testing
@testable import AiUsageApp

struct ResetDateTextFormatterTests {
    @Test
    func laterTodayUsesOnlyTime() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = ResetDateTextFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: calendar
        )

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10))!
        let resetAtUTC = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 15))!

        let text = formatter.string(from: resetAtUTC, now: now)

        #expect(text.contains("3:00"))
        #expect(text.contains("PM"))
        #expect(text.contains("Apr") == false)
    }

    @Test
    func laterAnotherDayKeepsDateAndTime() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = ResetDateTextFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: calendar
        )

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10))!
        let resetAtUTC = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 15))!
        let text = formatter.string(from: resetAtUTC, now: now)

        #expect(text.contains("Apr 9, 2026"))
        #expect(text.contains("3:00"))
        #expect(text.contains("PM"))
    }
}
