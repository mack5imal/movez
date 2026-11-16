import XCTest
@testable import movez

/// A pause, a Focus one above all, can outlast the working day. Its end must land in the day it
/// ends in: off hours if the day is closed, and a fresh session if a working day opened during
/// it, never yesterday's countdown with yesterday's bout.
final class PauseAcrossWorkingHoursTests: XCTestCase {
    private let minute: TimeInterval = 60

    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? SchedulerHarness.mondayMorning
    }

    func testAFocusOnOvernightEndsInAFreshWorkingDay() {
        let harness = SchedulerHarness(workingHours: .standard, startAt: Self.date(day: 7, hour: 22))
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")
        harness.send(.focusFilter(paused: true))
        XCTAssertEqual(harness.state.name, "paused")

        harness.clock.set(Self.date(day: 8, hour: 9, minute: 30))
        harness.send(.tick)
        harness.send(.focusFilter(paused: false))

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.boutStartedAt, harness.now, "the bout is today's")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute),
                      "a full interval, not yesterday's leftover")
        harness.run(seconds: 10)
        XCTAssertTrue(harness.state.isSitting, "no heads-up the moment the Focus ends, got \(harness.state)")
    }

    func testAPauseThatEndsAfterTheWorkingDayClosesGoesToOffHours() {
        let harness = SchedulerHarness(workingHours: .standard, startAt: Self.date(day: 7, hour: 17, minute: 30))
        harness.send(.tick)
        harness.send(.focusFilter(paused: true))

        harness.clock.set(Self.date(day: 7, hour: 20))
        harness.send(.focusFilter(paused: false))

        XCTAssertEqual(harness.state.name, "off_hours")
        XCTAssertFalse(harness.scheduler.pollingRequired)
    }

    func testAPauseThroughTheNightEndsInAFreshWorkingDay() {
        let harness = SchedulerHarness(workingHours: .standard, startAt: Self.date(day: 7, hour: 17, minute: 30))
        harness.send(.tick)
        harness.scheduler.snapshot.skipsToday = 2
        harness.send(.focusFilter(paused: true))

        harness.clock.set(Self.date(day: 8, hour: 9, minute: 30))
        harness.send(.focusFilter(paused: false))

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.skipsToday, 0, "Tuesday starts with clean counters")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
    }

    func testAPauseWithinTheDayHandsBackItsCountdownAndMovesTheBout() {
        let harness = SchedulerHarness(workingHours: .standard)
        harness.send(.tick)
        harness.run(seconds: 10 * minute)
        let bout = harness.snapshot.boutStartedAt
        harness.send(.userPause(seconds: 3600))
        harness.clock.advance(3600)
        harness.send(.tick)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(45 * minute), accuracy: 4)
        XCTAssertDate(harness.snapshot.boutStartedAt, bout.addingTimeInterval(3600), accuracy: 4,
                      "the hour paused is not counted as an hour sat")
    }
}
