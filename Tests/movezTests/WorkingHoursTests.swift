import XCTest
@testable import movez

final class WorkingHoursTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    func testDefaultSummary() {
        XCTAssertEqual(WorkingHours.standard.summary(), "Mon–Fri · 9:00–18:00")
    }

    func testMixedSummaryKeepsTheOddDayOut() {
        var hours = WorkingHours.standard
        for weekday in [2, 3, 4, 5] {
            hours.days[weekday - 1] = DayHours(enabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60 + 30)
        }
        hours.days[5] = DayHours(enabled: true, startMinutes: 9 * 60, endMinutes: 13 * 60)
        XCTAssertEqual(hours.summary(), "Mon–Thu · 9:00–17:30, Fri · 9:00–13:00")
    }

    func testSingleDayAndAllOffSummaries() {
        var hours = WorkingHours(days: Array(repeating: .off, count: 7))
        XCTAssertEqual(hours.summary(), "Off")

        hours.days[3] = DayHours(enabled: true, startMinutes: 10 * 60, endMinutes: 16 * 60)
        XCTAssertEqual(hours.summary(), "Wed · 10:00–16:00")

        XCTAssertEqual(WorkingHours.alwaysOn.summary(), "Mon–Sun · 0:00–24:00")
    }

    func testValidationRejectsAnEndBeforeItsStart() {
        XCTAssertEqual(WorkingHours.standard.validate(), [])

        var hours = WorkingHours.standard
        hours.days[2] = DayHours(enabled: true, startMinutes: 18 * 60, endMinutes: 9 * 60)
        XCTAssertEqual(hours.validate(), [.endNotAfterStart(weekdayLabel: "Tue")])
        XCTAssertEqual(
            hours.validate().first?.errorDescription,
            "Tue ends before it starts. Working hours cannot cross midnight."
        )

        hours.days[2] = DayHours(enabled: false, startMinutes: 18 * 60, endMinutes: 9 * 60)
        XCTAssertEqual(hours.validate(), [], "a day that is off cannot be invalid")
    }

    func testIsWithinCoversTheEdges() {
        let hours = WorkingHours.standard
        XCTAssertFalse(hours.isWithin(date(2026, 9, 7, 8, 59), calendar: calendar))
        XCTAssertTrue(hours.isWithin(date(2026, 9, 7, 9, 0), calendar: calendar))
        XCTAssertTrue(hours.isWithin(date(2026, 9, 7, 17, 59), calendar: calendar))
        XCTAssertFalse(hours.isWithin(date(2026, 9, 7, 18, 0), calendar: calendar), "the window is half open")
        XCTAssertFalse(hours.isWithin(date(2026, 9, 12, 10, 0), calendar: calendar), "Saturday is off")
    }

    func testNextStartAndEndCrossTheWeekend() {
        let hours = WorkingHours.standard
        let saturday = date(2026, 9, 12, 10, 41)
        let nextStart = hours.nextStart(after: saturday, calendar: calendar)
        XCTAssertEqual(nextStart, date(2026, 9, 14, 9, 0), "Monday morning")

        let mondayAfternoon = date(2026, 9, 7, 14, 0)
        XCTAssertEqual(hours.nextEnd(after: mondayAfternoon, calendar: calendar), date(2026, 9, 7, 18, 0))
        XCTAssertEqual(hours.nextStart(after: mondayAfternoon, calendar: calendar), date(2026, 9, 8, 9, 0))

        let fridayEvening = date(2026, 9, 11, 19, 0)
        XCTAssertEqual(hours.nextEnd(after: fridayEvening, calendar: calendar), date(2026, 9, 14, 18, 0))
    }

    func testEndOfTodayIsNilOnADayOff() {
        let hours = WorkingHours.standard
        XCTAssertEqual(hours.endOfToday(date(2026, 9, 7, 11, 0), calendar: calendar), date(2026, 9, 7, 18, 0))
        XCTAssertNil(hours.endOfToday(date(2026, 9, 12, 11, 0), calendar: calendar))
    }

    func testMinuteLabels() {
        XCTAssertEqual(DayHours.label(minutes: 9 * 60), "9:00")
        XCTAssertEqual(DayHours.label(minutes: 17 * 60 + 30), "17:30")
        XCTAssertEqual(DayHours.label(minutes: 0), "0:00")
        XCTAssertEqual(DayHours.nineToSix.label, "9:00–18:00")
    }

    func testNoWorkingDaysMeansNoNextStart() {
        let hours = WorkingHours(days: Array(repeating: .off, count: 7))
        XCTAssertNil(hours.nextStart(after: date(2026, 9, 7, 9, 0), calendar: calendar))
    }
}
