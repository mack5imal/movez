import XCTest
@testable import movez

/// DECISIONS 16: a session started by hand off hours ends at "End session", at midnight, or at a
/// four-hour gap. A break already on screen at midnight is allowed to finish first.
final class AdHocSessionTests: XCTestCase {
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

    /// Saturday afternoon, off hours, with a session started by hand.
    private func saturdaySession(at hour: Int = 14, minute: Int = 0) -> SchedulerHarness {
        let harness = SchedulerHarness(workingHours: .standard, startAt: Self.date(day: 12, hour: hour, minute: minute))
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")
        harness.send(.userStartSession)
        XCTAssertTrue(harness.snapshot.adHocSession)
        return harness
    }

    func testABreakRunningAtMidnightIsAllowedToFinish() {
        let harness = saturdaySession(at: 23)
        XCTAssertTrue(harness.run(until: { $0.isPendingFull }, limit: 60 * minute))
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.clock.advance(4)
        harness.send(.userStartNow)
        XCTAssertTrue(harness.state.isFullBreak)

        harness.run(seconds: 6 * minute)           // 23:55 plus six minutes is past midnight
        XCTAssertTrue(harness.state.isFullBreak, "a break on screen at midnight runs on, got \(harness.state)")

        harness.send(.breakEnded(completedBlocks: 5, totalBlocks: 5, elapsed: 325))
        harness.run(seconds: 4)
        XCTAssertEqual(harness.state.name, "off_hours", "and the session ends once it is over")
        XCTAssertFalse(harness.snapshot.adHocSession)
    }

    func testAFourHourAbsenceEndsTheSession() {
        let harness = saturdaySession()
        harness.run(seconds: 10 * minute)
        harness.send(.sleep)
        harness.clock.advance(5 * 3600)
        harness.send(.wake(gapSeconds: 5 * 3600))
        harness.run(seconds: 70)

        XCTAssertEqual(harness.state.name, "off_hours", "got \(harness.state)")
        XCTAssertFalse(harness.snapshot.adHocSession)
    }

    func testAShorterAbsenceKeepsTheSession() {
        let harness = saturdaySession()
        harness.run(seconds: 10 * minute)
        harness.send(.sleep)
        harness.clock.advance(2 * 3600)
        harness.send(.wake(gapSeconds: 2 * 3600))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "two hours is standby, not the end of the session, got \(harness.state)")
        XCTAssertTrue(harness.snapshot.adHocSession)
    }

    func testAFourHourLaunchGapEndsTheSession() {
        let harness = saturdaySession()
        harness.run(seconds: 10 * minute)
        // Quit for five hours: the relaunch hands the gap over before any tick runs.
        harness.clock.advance(5 * 3600)
        _ = harness.scheduler.applyLaunchGap(seconds: 5 * 3600, now: harness.now)

        XCTAssertEqual(harness.state.name, "off_hours", "got \(harness.state)")
        XCTAssertFalse(harness.snapshot.adHocSession)
    }
}
