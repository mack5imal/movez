import XCTest
@testable import movez

/// One test per defect found in the phase-14 review, each pinned so it cannot come back.
@MainActor
final class ReviewFixTests: XCTestCase {
    private static func date(month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? SchedulerHarness.mondayMorning
    }

    // MARK: - Sleep and lock

    /// A lock on top of an idle stretch used to re-enter `.away` with a fresh `since`, so six
    /// minutes away were measured as the four since the screen locked — a full-break credit
    /// became a micro-break credit.
    func testLockingWhileAlreadyAwayDoesNotRestartTheAbsence() {
        let harness = SchedulerHarness()
        harness.send(.idle(seconds: 4 * 60))
        guard case .away(let firstSince) = harness.state else {
            return XCTFail("expected away, got \(harness.state.name)")
        }

        harness.clock.advance(120)
        harness.send(.lock)

        guard case .away(let stillSince) = harness.state else {
            return XCTFail("expected away, got \(harness.state.name)")
        }
        XCTAssertEqual(stillSince, firstSince, "the absence is still measured from when it began")
    }

    /// Closing the lid during a pause used to cancel the pause and credit a break the user never
    /// took.
    func testSleepingWhilePausedKeepsThePause() {
        let harness = SchedulerHarness()
        harness.send(.userPause(seconds: 60 * 60))
        let held = harness.snapshot.remainingAtPauseSeconds

        harness.send(.sleep)

        XCTAssertEqual(harness.state.name, "paused", "a pause outlasts a closed lid")
        XCTAssertEqual(harness.snapshot.remainingAtPauseSeconds, held)
        XCTAssertEqual(harness.snapshot.doneToday, 0, "and nothing is credited")
    }

    func testSleepingOffHoursChangesNothing() {
        let harness = SchedulerHarness(workingHours: .standard, startAt: Self.date(month: 9, day: 12, hour: 10))
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")

        harness.send(.sleep)
        XCTAssertEqual(harness.state.name, "off_hours")
    }

    // MARK: - Pause and Focus

    /// A Focus turning on over a manual pause used to stretch it to the end of the working day
    /// and leave the Focus unable to lift what it had not set.
    func testAFocusTurningOnDoesNotRewriteAManualPause() {
        let harness = SchedulerHarness()
        harness.send(.userPause(seconds: 15 * 60))
        guard case .paused(let until) = harness.state else {
            return XCTFail("expected paused, got \(harness.state.name)")
        }

        harness.send(.focusFilter(paused: true))

        guard case .paused(let stillUntil) = harness.state else {
            return XCTFail("expected paused, got \(harness.state.name)")
        }
        XCTAssertEqual(stillUntil, until, "the pause the user set is unchanged")
        XCTAssertFalse(harness.snapshot.pauseIsFocusInitiated)

        harness.send(.focusFilter(paused: false))
        XCTAssertEqual(harness.state.name, "paused", "and a Focus cannot lift it")
    }

    // MARK: - Suppression

    /// A snooze running out during a call used to put the heads-up on screen until the next poll.
    func testASnoozeThatRunsOutDuringACallIsDeferred() {
        let harness = SchedulerHarness()
        // Typing straight through, so the heads-up arrives on the input-wait cap rather than on
        // a pause in typing.
        harness.run(seconds: 55 * 60 + 70, inputAge: 0)
        XCTAssertEqual(harness.state.name, "heads_up")

        harness.send(.userSnooze)
        XCTAssertEqual(harness.state.name, "snoozed")

        harness.send(.signals(SignalSnapshot(microphoneActive: true)))
        XCTAssertEqual(harness.state.name, "suppressed")
        XCTAssertNotNil(harness.snapshot.deferredFullDueAt, "the break is owed, not dropped")

        harness.run(seconds: 10 * 60)
        XCTAssertEqual(harness.state.name, "suppressed", "and no panel appeared while the call ran")
    }

    // MARK: - A day that ended before the app came back

    func testASnapshotRestoredOnALaterDayStartsTheDayOver() {
        let friday = Self.date(month: 9, day: 11, hour: 17)
        var scheduler = Scheduler(config: SchedulerConfig(workingHours: .alwaysOn), now: friday)
        scheduler.snapshot.doneToday = 6
        scheduler.snapshot.skipsToday = 2
        scheduler.snapshot.snoozedToday = 1

        let monday = Self.date(month: 9, day: 14, hour: 10)
        var restored = Scheduler(snapshot: scheduler.snapshot, config: SchedulerConfig(workingHours: .alwaysOn))
        _ = restored.rollDayIfStale(now: monday)

        XCTAssertEqual(restored.snapshot.doneToday, 0)
        XCTAssertEqual(restored.snapshot.skipsToday, 0)
        XCTAssertEqual(restored.snapshot.snoozedToday, 0)
        XCTAssertEqual(restored.snapshot.dayKey, DayKey.key(for: monday, calendar: .current))
    }

    func testASnapshotRestoredOnTheSameDayKeepsItsCounters() {
        let morning = Self.date(month: 9, day: 11, hour: 9)
        var scheduler = Scheduler(config: SchedulerConfig(workingHours: .alwaysOn), now: morning)
        scheduler.snapshot.doneToday = 3

        var restored = Scheduler(snapshot: scheduler.snapshot, config: SchedulerConfig(workingHours: .alwaysOn))
        _ = restored.rollDayIfStale(now: Self.date(month: 9, day: 11, hour: 14))

        XCTAssertEqual(restored.snapshot.doneToday, 3)
    }

    // MARK: - A break the lid closed on

    func testAnInterruptedBreakResumesAsTheSameBreak() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        harness.coordinator.takeBreakNow()
        let original = harness.coordinator.currentBreak
        XCTAssertNotNil(original)

        harness.clock.advance(60)
        harness.coordinator.nextBlock()
        harness.coordinator.inject(.sleep)
        XCTAssertNil(harness.coordinator.currentBreak, "the overlay is gone")
        XCTAssertNotNil(harness.coordinator.interruptedSession, "but the break is kept")

        harness.clock.advance(60)
        harness.coordinator.inject(.wake(gapSeconds: 60))
        harness.run(seconds: 90)

        let resumed = harness.coordinator.currentBreak
        XCTAssertEqual(resumed?.routine.id, original?.routine.id, "the same movements, not a fresh routine")
        XCTAssertEqual(resumed?.completedBlocks, 1, "and it picks up where it left off")
        XCTAssertEqual(harness.coordinator.routinesToday.count, 1, "counted against the day once")
    }

    // MARK: - Working hours

    func testWorkingHoursDecodedFromAShortBlobDoNotCrash() throws {
        let json = Data(#"{"days":[{"enabled":true,"startMinutes":540,"endMinutes":1080}]}"#.utf8)
        let hours = try JSONDecoder().decode(WorkingHours.self, from: json)

        XCTAssertEqual(hours.days.count, 7, "decoding goes through the validating initialiser")
        XCTAssertNotNil(hours.nextStart(after: SchedulerHarness.mondayMorning, calendar: .current))
    }

    /// Day boundaries are built with the calendar, not by adding seconds to midnight, so the two
    /// days a year the clocks change do not move the working day by an hour.
    func testDayBoundariesSurviveADaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        // 8 March 2026: the clocks go forward at 02:00 local.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 0
        let springForward = try XCTUnwrap(calendar.date(from: components))

        let nine = WorkingHours.moment(onDayOf: springForward, minutes: 9 * 60, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: nine), 9, "nine o'clock is nine o'clock")
        XCTAssertEqual(calendar.component(.minute, from: nine), 0)
    }

    func testMidnightIsTheEndOfTheDayNotTheStartOfIt() {
        let calendar = Calendar.current
        let day = Self.date(month: 9, day: 11, hour: 12)
        let end = WorkingHours.moment(onDayOf: day, minutes: 24 * 60, calendar: calendar)

        XCTAssertEqual(end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)))
    }

    // MARK: - Purity

    func testTheSchedulerNeverReadsTheWallClock() throws {
        // Clock.swift is the one file whose job is to read the wall clock; everything else in
        // the scheduler is a function of what it hands them.
        let schedulerFiles = try AccessibilityTests.sourceFiles()
            .filter { $0.path.contains("/Scheduler/") && $0.lastPathComponent != "Clock.swift" }
        XCTAssertFalse(schedulerFiles.isEmpty)

        for url in schedulerFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                XCTAssertFalse(
                    code.contains("Date()"),
                    "\(url.lastPathComponent):\(index + 1) reads the wall clock; the scheduler is a function of the clock it is handed"
                )
            }
        }
    }
}
