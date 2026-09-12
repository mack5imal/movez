import XCTest
@testable import movez

/// The corners: the ends of the ranges, the ends of the day, and the moments two things happen at
/// once.
@MainActor
final class EdgeCaseTests: XCTestCase {
    private func settingsViewModel(_ harness: CoordinatorHarness) -> SettingsViewModel {
        SettingsViewModel(
            settings: harness.settings,
            library: RoutineTestSupport.library,
            launchAtLogin: FakeLaunchAtLogin(),
            onChange: { [coordinator = harness.coordinator] in coordinator.settingsChanged() }
        )
    }

    private static func date(month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? SchedulerHarness.mondayMorning
    }

    // MARK: - The ends of the custom range

    func testTheCustomPresetAtBothEnds() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let settings = settingsViewModel(harness)
        settings.setPreset(.custom)

        settings.setCustomMinutes(15)
        XCTAssertEqual(harness.settings.schedulerConfig.sitSeconds, 15 * 60)
        XCTAssertFalse(harness.settings.microToggleAvailable, "a fifteen-minute bout needs no micro-break")

        settings.setCustomMinutes(120)
        XCTAssertEqual(harness.settings.schedulerConfig.sitSeconds, 120 * 60)
        XCTAssertTrue(harness.settings.microToggleAvailable)
    }

    // MARK: - Working hours

    func testWorkingHoursCannotCrossMidnight() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let settings = settingsViewModel(harness)
        let before = harness.settings.workingHours

        settings.beginEditingHours()
        settings.hoursDraft = .standard
        settings.hoursDraft.days[1].startMinutes = 23 * 60
        settings.hoursDraft.days[1].endMinutes = 6 * 60
        settings.applyHours()

        XCTAssertEqual(settings.hoursError, "End must be after start (Mon)")
        XCTAssertEqual(harness.settings.workingHours, before, "nothing is written until it is valid")
    }

    /// "Pause for the rest of the day" a minute before the day ends is a one-minute pause, not a
    /// pause that outlives the working day.
    func testRestOfDayAtOneMinuteToSix() {
        let start = Self.date(month: 9, day: 11, hour: 17, minute: 59)
        let harness = CoordinatorHarness(workingHours: .standard, startAt: start)
        harness.run(seconds: 4)

        MenuBarViewModel(coordinator: harness.coordinator).pause(.restOfDay)

        guard case .paused(let until) = harness.state else {
            return XCTFail("expected a pause, got \(harness.state.name)")
        }
        let end = try? XCTUnwrap(until)
        XCTAssertEqual(end?.timeIntervalSince(start) ?? 0, 60, accuracy: 1, "it runs to six o'clock and stops")
    }

    /// A break that comes due inside the working day fires; one that comes due after it has
    /// closed does not, because by then movez is off hours.
    func testABreakDueAtTheEndOfTheDayFiresAndOneDueAfterDoesNot() {
        let inside = CoordinatorHarness(workingHours: .standard, startAt: Self.date(month: 9, day: 11, hour: 17, minute: 50))
        inside.run(seconds: 4)
        inside.coordinator.makeDue(inSeconds: 120)
        _ = inside.run(until: { $0.name != "sitting" }, limit: 300)
        XCTAssertEqual(inside.state.name, "pending_full", "17:52 is still the working day")

        let outside = CoordinatorHarness(workingHours: .standard, startAt: Self.date(month: 9, day: 11, hour: 17, minute: 59))
        outside.run(seconds: 4)
        outside.coordinator.makeDue(inSeconds: 120)
        outside.run(seconds: 180)
        XCTAssertEqual(outside.state.name, "off_hours", "18:01 is not")
    }

    // MARK: - Interruptions landing on each other

    func testSleepDuringAMicroCountInTakesItDownAndGoesAway() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let debug = DebugViewModel(coordinator: harness.coordinator)
        debug.fire(.fireMicro)
        XCTAssertEqual(harness.state.name, "micro_count_in")

        harness.sink.clear()
        debug.fire(.sleep)

        XCTAssertEqual(harness.state.name, "away")
        XCTAssertTrue(harness.sink.names.contains("hideMicro"))
        XCTAssertNil(harness.coordinator.currentMicro)
    }

    func testMakeDueInFiveWhileAMicroIsRunningKeepsThemApart() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        DebugViewModel(coordinator: harness.coordinator).fire(.fireMicro)
        XCTAssertEqual(harness.state.name, "micro_count_in")

        // Make due in only applies while sitting; the micro-break is left to finish.
        harness.coordinator.makeDue(inSeconds: 5 * 60)
        XCTAssertEqual(harness.state.name, "micro_count_in")

        harness.coordinator.microSkip()
        harness.coordinator.makeDue(inSeconds: 5 * 60)
        let due = harness.scheduler.snapshot.nextFullDueAt ?? .distantPast
        XCTAssertEqual(due.timeIntervalSince(harness.now), 300, accuracy: 2)
        XCTAssertNil(
            harness.scheduler.snapshot.nextMicroDueAt,
            "a micro-break ten minutes from a full break is not worth having"
        )
    }

    /// Changing the time scale re-anchors the clock; it must not move time backwards under a
    /// break that is already running.
    func testTheTimeScaleChangingMidBreakKeepsTimeMovingForwards() {
        let clock = SystemClock()
        let before = clock.now
        clock.timeScale = 60
        let after = clock.now
        XCTAssertGreaterThanOrEqual(after, before)

        clock.timeScale = 1
        XCTAssertGreaterThanOrEqual(clock.now, after, "and back down again")
    }

    func testTheOverlayCountdownNeverGoesBackwardsAcrossAScaleChange() {
        let clock = SystemClock()
        let routine = RoutineTestSupport.builder.build(context: RoutineContext())
        let viewModel = OverlayViewModel(routine: routine, startedAt: clock.now, clock: clock)

        let first = viewModel.breakRemaining
        clock.timeScale = 60
        let second = viewModel.breakRemaining
        XCTAssertLessThanOrEqual(second, first)
        XCTAssertGreaterThanOrEqual(second, 0)
    }

    // MARK: - Doing nothing while there is nothing to do

    /// The idle CPU story is this: while movez cannot act on what a poll would tell it, it does
    /// not poll.
    func testNothingIsPolledWhilePausedOrOffHours() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let aggregator = SignalAggregator(
            idle: FakeIdleSource(),
            mic: FakeMicSource(),
            capture: FakeCaptureSource(),
            fullscreen: FakeFullscreenSource(),
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { _ in }
        )
        harness.coordinator.aggregator = aggregator
        aggregator.setPolling(true)
        XCTAssertTrue(aggregator.isRunning)

        harness.coordinator.pause(forSeconds: 30 * 60)
        XCTAssertFalse(harness.scheduler.pollingRequired)
        XCTAssertFalse(aggregator.isRunning, "a paused movez samples nothing")

        let polls = aggregator.pollCount
        harness.run(seconds: 30)
        XCTAssertEqual(aggregator.pollCount, polls, "and the count does not move while it is paused")

        harness.coordinator.resume()
        XCTAssertTrue(aggregator.isRunning, "and starts again when there is something to notice")
    }

    // MARK: - The weekend

    func testASaturdayIsOffHoursAndASessionStartedByHandIsNot() {
        let harness = CoordinatorHarness(workingHours: .standard, startAt: Self.date(month: 9, day: 12, hour: 10))
        harness.run(seconds: 4)
        XCTAssertEqual(harness.state.name, "off_hours")
        XCTAssertFalse(harness.scheduler.pollingRequired, "nothing is polled at the weekend")

        harness.coordinator.startSession()
        XCTAssertEqual(harness.state.name, "sitting")
        XCTAssertTrue(harness.scheduler.pollingRequired)
    }
}
