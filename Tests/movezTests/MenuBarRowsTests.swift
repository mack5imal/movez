import XCTest
@testable import movez

/// The dropdown's rows in each state, and what each one does when it is pressed. A row is shown
/// only where the scheduler acts on it: a row that does nothing when clicked, with no feedback, is
/// worse than no row (UI-4, UI-5).
@MainActor
final class MenuBarRowsTests: XCTestCase {
    private func harness() -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn)
    }

    private func viewModel(_ harness: CoordinatorHarness) -> MenuBarViewModel {
        MenuBarViewModel(coordinator: harness.coordinator)
    }

    /// Brings the next micro-break due now, the way the debug button does.
    private func startMicro(_ harness: CoordinatorHarness) {
        harness.coordinator.scheduler.snapshot.nextMicroDueAt = harness.now
        harness.coordinator.tick()
    }

    private func reachHeadsUp(_ harness: CoordinatorHarness) {
        XCTAssertTrue(harness.run { if case .headsUp = $0 { return true } else { return false } })
    }

    // MARK: - Sitting

    func testPlainSittingOffersTheBreakTheMakeDueStepsAndPause() {
        let harness = harness()
        harness.run(seconds: 60)
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .makeDue, .pauseFor])

        menu.makeDue(5)
        XCTAssertEqual(harness.scheduler.snapshot.secondsUntilFullBreak(at: harness.now), 5 * 60)
    }

    func testAnAdHocSessionEndsByHandInsteadOfPausing() {
        let saturday = SchedulerHarness.mondayMorning.addingTimeInterval(5 * 86_400)
        let harness = CoordinatorHarness(workingHours: .standard, startAt: saturday)
        harness.run(seconds: 4)
        let menu = viewModel(harness)
        menu.startSession()
        XCTAssertEqual(menu.state.rows, [.takeBreak, .makeDue, .endSession])
    }

    // MARK: - Make due in

    /// The scheduler moves the due time only in plain sitting; anywhere else the steps did nothing.
    func testMakeDueIsHiddenDuringASnooze() {
        let harness = harness()
        reachHeadsUp(harness)
        harness.coordinator.inject(.userSnooze)
        XCTAssertEqual(harness.state.name, "snoozed")
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .pauseFor])

        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break", "a break by hand cuts a snooze short")
    }

    func testMakeDueIsHiddenDuringAHeadsUp() {
        let harness = harness()
        reachHeadsUp(harness)
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .pauseFor])

        menu.pause(.fifteenMinutes)
        XCTAssertEqual(harness.state.name, "paused", "pausing from a heads-up dismisses it")
    }

    func testMakeDueIsHiddenWhileAway() {
        let harness = harness()
        harness.run(seconds: 10 * 60)
        harness.coordinator.inject(.idle(seconds: 6 * 60))
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.mode, .away)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .pauseFor])

        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break")
    }

    func testMakeDueIsHiddenOnACall() {
        let harness = harness()
        harness.run(seconds: 60)
        harness.coordinator.inject(.signals(SignalSnapshot(microphoneActive: true)))
        XCTAssertEqual(harness.state.name, "suppressed")
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .pauseFor])
    }

    // MARK: - Take a break now

    /// The micro-break gives way to the full break the user asked for.
    func testTakeABreakNowDuringAMicroBreakReplacesItWithTheFullBreak() {
        let harness = harness()
        harness.run(seconds: 60)
        startMicro(harness)
        XCTAssertEqual(harness.state.name, "micro_count_in")
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.takeBreak, .pauseFor])

        harness.sink.clear()
        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break")
        XCTAssertEqual(
            harness.sink.order(of: ["hideMicro", "startFullBreak"]),
            ["hideMicro", "startFullBreak"],
            "the micro panel is taken down before the overlay goes up"
        )
    }

    func testTakeABreakNowFromARunningMicroBreak() {
        let harness = harness()
        harness.run(seconds: 60)
        startMicro(harness)
        harness.coordinator.inject(.userMicroStartNow)
        XCTAssertEqual(harness.state.name, "micro_running")

        viewModel(harness).takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break")
    }

    /// The break the row would start is already on screen.
    func testAFullBreakOnScreenOffersNoSecondBreak() {
        let harness = harness()
        let menu = viewModel(harness)
        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break")
        menu.refresh()
        XCTAssertFalse(menu.state.rows.contains(.takeBreak))
        XCTAssertFalse(menu.state.rows.contains(.makeDue))
        XCTAssertFalse(menu.state.rows.contains(.pauseFor), "the scheduler does not pause a running break")
        XCTAssertEqual(menu.state.rows, [], "and the overlay's own buttons are the way out of it")

        harness.coordinator.pause(forSeconds: 30 * 60)
        XCTAssertEqual(harness.state.name, "full_break", "which is why the row is not offered")
    }

    // MARK: - Paused

    func testATimedPauseOffersResumeExtendAndAQuietBreak() {
        let harness = harness()
        let menu = viewModel(harness)
        menu.pause(.thirtyMinutes)
        XCTAssertEqual(menu.state.rows, [.resume, .extendPause, .takeBreak])
        XCTAssertFalse(menu.state.pauseIndefinite)
        XCTAssertEqual(menu.labelText, "‖ 30m")
    }

    /// A Focus pause ends when the Focus does. It has no minutes to show and nothing to extend,
    /// and extending it turned "until the Focus ends" into fifteen minutes.
    func testAFocusPauseShowsNoMinutesAndCannotBeExtended() {
        let harness = harness()
        harness.coordinator.focusFilter(paused: true)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.mode, .paused)
        XCTAssertTrue(menu.state.pauseIndefinite)
        XCTAssertEqual(menu.labelText, "‖")
        XCTAssertEqual(menu.state.title, "Paused")
        XCTAssertEqual(menu.state.rows, [.resume, .takeBreak])

        menu.resume()
        XCTAssertEqual(harness.state.name, "sitting", "Resume now still lifts it")
    }

    func testTheSchedulerLeavesAFocusPauseAloneWhenAskedToExtendIt() {
        let harness = harness()
        harness.coordinator.focusFilter(paused: true)
        harness.coordinator.extendPause(bySeconds: 15 * 60)
        XCTAssertEqual(harness.state, .paused(until: nil))

        harness.run(seconds: 20 * 60)
        XCTAssertEqual(harness.state, .paused(until: nil), "still paused while the Focus is on")
        harness.coordinator.focusFilter(paused: false)
        XCTAssertEqual(harness.state.name, "sitting", "and the Focus ending still lifts it")
    }

    // MARK: - Off hours

    func testOffHoursOffersASessionAndABreak() {
        let saturday = SchedulerHarness.mondayMorning.addingTimeInterval(5 * 86_400)
        let harness = CoordinatorHarness(workingHours: .standard, startAt: saturday)
        harness.run(seconds: 4)
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.rows, [.startSession, .takeBreak])

        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break")
    }

    // MARK: - The countdown during a snooze (UI-6)

    /// A snooze leaves the original due time in the past; the break comes back when the snooze
    /// ends, so that is what the menu counts down to.
    func testASnoozeCountsDownToTheSnoozesEnd() {
        let harness = harness()
        reachHeadsUp(harness)
        harness.coordinator.inject(.userSnooze)
        harness.run(seconds: 60)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.mode, .sitting)
        XCTAssertEqual(menu.state.minutesRemaining, 4)
        XCTAssertEqual(menu.state.title, "Next break in 4 min")
        XCTAssertEqual(menu.labelText, "4m")
        XCTAssertEqual(menu.state.elapsedFraction, 0.2, accuracy: 0.01, "a fifth of the five-minute snooze")
    }

    /// A break that has fallen due and is waiting for the user's next keystroke is not "in 0 min".
    func testABreakWaitingForInputSaysItIsDue() {
        let harness = harness()
        harness.coordinator.scheduler.snapshot.nextFullDueAt = harness.now
        harness.coordinator.tick()
        guard case .pendingFull = harness.state else {
            return XCTFail("expected the break to wait for input, got \(harness.state.name)")
        }
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.title, "Break due")
    }

    func testABreakDeferredByACallSaysWhatItIsWaitingFor() {
        let harness = harness()
        harness.run(seconds: 60)
        harness.coordinator.inject(.signals(SignalSnapshot(microphoneActive: true)))
        harness.run(seconds: 55 * 60)
        guard case .suppressed(_, let deferred) = harness.state, deferred != nil else {
            return XCTFail("expected a deferred break, got \(harness.state)")
        }
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.title, "Break waiting for your call")
    }

    // MARK: - Redraws (UI-16)

    /// The coordinator publishes every two seconds; the menu-bar item should redraw only when
    /// something it draws changes, which while sitting is about once a minute.
    func testTheMenuBarStateIsNotRepublishedOnEveryTick() {
        let harness = harness()
        harness.run(seconds: 10 * 60 + 4)
        let menu = viewModel(harness)
        var publishes = 0
        let subscription = menu.$state.dropFirst().sink { _ in publishes += 1 }
        for _ in 0..<10 {
            harness.run(seconds: 2)
            menu.refresh()
        }
        subscription.cancel()
        XCTAssertLessThanOrEqual(publishes, 1, "twenty seconds of ticks inside one minute")
    }
}
