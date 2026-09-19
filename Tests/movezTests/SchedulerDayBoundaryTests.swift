import XCTest
@testable import movez

/// Midnight, crossed while the user is still at the desk.
///
/// The day-scoped counters, the routine seed and the streak key all start over. The sitting bout
/// does not: fifteen minutes from a break at 23:45 is fifteen minutes from a break at 00:01.
final class SchedulerDayBoundaryTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// Monday 7 September 2026, at whatever time the test needs.
    private static func date(day: Int = 7, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_767_225_600)
    }

    private func lateEvening(minute: Int = 45) -> Date { Self.date(hour: 23, minute: minute) }

    // MARK: - The countdown

    func testCrossingMidnightWhileSittingKeepsTheCountdown() {
        let harness = SchedulerHarness(startAt: lateEvening())
        let due = harness.snapshot.nextFullDueAt
        let boutStart = harness.start

        harness.run(seconds: 20 * minute)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertDate(harness.snapshot.nextFullDueAt, due, accuracy: 2,
                      "midnight must not hand back a fresh fifty-five minutes")
        XCTAssertDate(harness.start, boutStart, accuracy: 2, "nor move the bout it is measuring")
    }

    func testTheBreakAfterMidnightLandsOnTheOriginalSchedule() {
        // Micro-breaks off: they come due every half hour and would be the first thing to
        // interrupt the sitting run, which is not what this test is measuring.
        var config = SchedulerConfig()
        config.microEnabled = false
        let harness = SchedulerHarness(config: config, startAt: lateEvening())

        // 23:45 + 55 min = 00:40, with the heads-up a minute before it.
        harness.run(until: { !$0.isSitting }, limit: 90 * minute)

        XCTAssertTrue(harness.state.isPendingFull || harness.state.isHeadsUp,
                      "expected the break to come due, got \(harness.state)")
        XCTAssertDate(harness.now, Self.date(day: 8, hour: 0, minute: 39), accuracy: 90,
                      "the break belongs at 00:39–00:40, not 01:35")
    }

    func testCrossingMidnightRollsTheCountersAndTheDayKey() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 58))
        harness.scheduler.snapshot.doneToday = 4
        harness.scheduler.snapshot.skipsToday = 2
        harness.scheduler.snapshot.snoozedToday = 1
        harness.scheduler.snapshot.longestBoutSeconds = 3000
        harness.scheduler.snapshot.microEmphasisIndex = 3

        harness.run(seconds: 4 * minute)

        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertEqual(harness.snapshot.skipsToday, 0)
        XCTAssertEqual(harness.snapshot.snoozedToday, 0)
        XCTAssertEqual(harness.snapshot.longestBoutSeconds, 0)
        XCTAssertEqual(harness.snapshot.microEmphasisIndex, 0)
        XCTAssertEqual(harness.snapshot.dayKey, DayKey.key(for: harness.now, calendar: .current))
    }

    // MARK: - Every state outlasts midnight

    func testCrossingMidnightDuringABreakLeavesTheBreakOnScreen() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 58))
        harness.send(.userTakeBreakNow)
        guard case .fullBreak(let startedAt) = harness.state else {
            return XCTFail("expected a full break, got \(harness.state)")
        }
        harness.clearEffects()

        harness.run(seconds: 4 * minute)

        guard case .fullBreak(let stillStartedAt) = harness.state else {
            return XCTFail("the break was taken off screen at midnight, state is \(harness.state)")
        }
        XCTAssertDate(stillStartedAt, startedAt, accuracy: 2)
        XCTAssertFalse(harness.effectNames.contains("endFullBreak"))
    }

    func testCrossingMidnightDuringAPauseKeepsThePause() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 58))
        harness.send(.userPause(seconds: 60 * 60))
        guard case .paused(let until) = harness.state else {
            return XCTFail("expected paused, got \(harness.state)")
        }
        let held = harness.snapshot.remainingAtPauseSeconds

        harness.run(seconds: 4 * minute)

        guard case .paused(let stillUntil) = harness.state else {
            return XCTFail("the pause was cancelled at midnight, state is \(harness.state)")
        }
        XCTAssertDate(stillUntil, until, accuracy: 2)
        XCTAssertEqual(harness.snapshot.remainingAtPauseSeconds, held)
    }

    func testCrossingMidnightWhileAwayKeepsTheAbsence() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 58))
        harness.send(.idle(seconds: 4 * 60))
        guard case .away(let since) = harness.state else {
            return XCTFail("expected away, got \(harness.state)")
        }

        harness.run(seconds: 4 * minute)

        guard case .away(let stillSince) = harness.state else {
            return XCTFail("the absence was ended at midnight, state is \(harness.state)")
        }
        XCTAssertDate(stillSince, since, accuracy: 2,
                      "the absence must still be measured from when it began, not from midnight")
    }

    func testCrossingMidnightDuringACallStillOwesTheBreak() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 50))
        // The break has to come due *during* the call for there to be anything to defer.
        harness.send(.userMakeDueIn(seconds: 5 * 60))
        harness.send(.signals(SignalSnapshot(microphoneActive: true)))
        guard case .suppressed = harness.state else {
            return XCTFail("expected suppressed, got \(harness.state)")
        }

        harness.run(seconds: 20 * minute)

        guard case .suppressed = harness.state else {
            return XCTFail("the call was cut short at midnight, state is \(harness.state)")
        }
        XCTAssertNotNil(harness.snapshot.deferredFullDueAt,
                        "a break deferred by a call is still owed on the other side of midnight")
    }

    func testCrossingMidnightKeepsTheSessionTransients() {
        let harness = SchedulerHarness(startAt: lateEvening(minute: 58))
        harness.scheduler.snapshot.interruptedBreak = InterruptedBreak(
            startedAt: harness.now,
            plannedEnd: harness.now.addingTimeInterval(300),
            elapsedSeconds: 60,
            completedBlocks: 1,
            totalBlocks: 4
        )
        harness.scheduler.snapshot.deferredFullDueAt = harness.now.addingTimeInterval(600)

        harness.run(seconds: 4 * minute)

        XCTAssertNotNil(harness.snapshot.interruptedBreak,
                        "a break interrupted at 23:58 must still be resumable at 00:02")
        XCTAssertNotNil(harness.snapshot.deferredFullDueAt)
    }

    // MARK: - Gaps that cross midnight

    func testAMinuteAsleepAcrossMidnightKeepsTheCountdown() {
        // The gap itself has to span midnight — that is the case where `shouldResetDay` used to
        // see "a working day opened during the gap" and hand back a fresh fifty-five minutes,
        // because under contiguous hours the day opens at midnight.
        let harness = SchedulerHarness(startAt: Self.date(hour: 23, minute: 30))
        harness.run(seconds: 29 * minute)   // 23:59, still the day before
        let due = harness.snapshot.nextFullDueAt

        harness.send(.sleep)
        harness.clock.advance(90)           // 00:00:30 — asleep across the boundary
        harness.send(.wake(gapSeconds: 90))
        harness.run(seconds: 70)

        XCTAssertDate(harness.snapshot.nextFullDueAt, due, accuracy: 4,
                      "a minute asleep across a day boundary is not a new day")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    func testSleepingThroughTheStartOfTheWorkingDayStillOpensItFresh() {
        let harness = SchedulerHarness(
            workingHours: .standard,
            startAt: Self.date(day: 8, hour: 8)
        )
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")

        harness.clock.set(Self.date(day: 8, hour: 9, minute: 30))
        harness.send(.wake(gapSeconds: 90 * 60))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        // Off hours the wake itself changes nothing; the first tick inside working hours opens the
        // day with a fresh interval. Measured from the bout, not from `now`, which has moved on.
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.start.addingTimeInterval(55 * 60), accuracy: 4)
    }

    func testAGapAcrossAWorkingDayThatClosedAndReopenedStartsItFresh() {
        // A genuine split shift: Monday evening 20:00–23:00, Tuesday 00:30–08:00.
        var days = Array(repeating: DayHours.off, count: 7)
        days[2] = DayHours(enabled: true, startMinutes: 20 * 60, endMinutes: 23 * 60)   // Monday
        days[3] = DayHours(enabled: true, startMinutes: 30, endMinutes: 8 * 60)         // Tuesday
        let harness = SchedulerHarness(
            workingHours: WorkingHours(days: days),
            startAt: Self.date(hour: 22, minute: 55)
        )
        harness.scheduler.snapshot.skipsToday = 3

        harness.send(.sleep)
        harness.clock.set(Self.date(day: 8, hour: 0, minute: 45))
        harness.send(.wake(gapSeconds: 110 * 60))   // under four hours
        harness.run(seconds: 70)

        XCTAssertEqual(harness.snapshot.skipsToday, 0,
                       "the window genuinely closed and reopened, so this is a new working day")
    }

    func testTheWorkingDayOpensWithCleanCountersAfterMidnightRolledThem() {
        let harness = SchedulerHarness(
            workingHours: .standard,
            startAt: Self.date(hour: 23, minute: 50)
        )
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")
        harness.scheduler.snapshot.doneToday = 5
        harness.scheduler.snapshot.skipsToday = 2

        harness.run(seconds: 15 * minute)           // midnight rolls the counters, still off hours
        XCTAssertEqual(harness.state.name, "off_hours", "the roll must not open the day early")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertEqual(harness.snapshot.skipsToday, 0)

        harness.scheduler.snapshot.interruptedBreak = InterruptedBreak(
            startedAt: harness.now, plannedEnd: harness.now, elapsedSeconds: 30,
            completedBlocks: 0, totalBlocks: 4
        )
        harness.clock.set(Self.date(day: 8, hour: 9))
        harness.send(.tick)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0, "the working day opens with clean counters")
        XCTAssertNil(harness.snapshot.interruptedBreak,
                     "a break left over from last night is not resumed this morning")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.start.addingTimeInterval(55 * 60), accuracy: 4)
    }
}
