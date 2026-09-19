import XCTest
@testable import movez

/// Absences and returns, driven the way the real monitors drive them: an input age and an idle
/// reading every two seconds whether or not anyone is at the desk, and several wake notifications
/// for one return, each measuring its gap from a poll that has already run.
///
/// Every test here is a regression. The first two reproduce the loop that credited a break every
/// two seconds of every absence; the wake tests reproduce the later notification that shrank a
/// twenty-hour absence to nothing and served a break prompt to someone who had just come back.
final class AwayReturnTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// One poll, in the order `SignalAggregator.poll()` sends it, then the tick.
    private func poll(_ harness: SchedulerHarness, idle: Int) {
        harness.send(.input(lastEventAgeSeconds: idle))
        harness.send(.idle(seconds: idle))
        harness.send(.tick)
    }

    /// Advances the clock in two-second polls while the idle age climbs with it.
    private func stayAway(_ harness: SchedulerHarness, for seconds: TimeInterval, idleFrom start: Int = 0) -> Int {
        var idle = start
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            harness.clock.advance(2)
            elapsed += 2
            idle += 2
            poll(harness, idle: idle)
        }
        return idle
    }

    private func toastCount(_ effects: [SchedulerEffect]) -> Int {
        effects.filter { if case .showToast = $0 { return true } else { return false } }.count
    }

    private func isAway(_ state: SchedulerState) -> Bool {
        if case .away = state { return true } else { return false }
    }

    // MARK: - The credit loop

    func testPollingThroughAnAbsenceCreditsItOnceOnReturn() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.clearEffects()

        _ = stayAway(harness, for: 30 * minute)
        XCTAssertTrue(isAway(harness.state), "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0, "nothing is credited while the user is still gone")
        XCTAssertEqual(toastCount(harness.effects), 0)

        harness.clock.advance(2)
        poll(harness, idle: 0)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.doneToday, 1)
        XCTAssertEqual(toastCount(harness.effects), 1)
        XCTAssertTrue(harness.effects.contains(.chime(.toast)), "the toast announces itself")
        let toast = harness.effects.compactMap { effect -> ToastInfo? in
            if case .showToast(let info) = effect { return info } else { return nil }
        }.first
        XCTAssertEqual(toast?.secondsOnScreen, 15)
        XCTAssertEqual(toast?.awaySeconds ?? 0, 30 * 60, accuracy: 4)
    }

    func testALatePollWhileAwayIsNotAReturn() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.clock.advance(6 * minute)
        harness.send(.idle(seconds: 6 * 60))

        // App Nap throttles a menu-bar agent whose display is off; the poll runs thirty seconds late.
        harness.clock.advance(30)
        harness.send(.gapDetected(seconds: 30))
        harness.run(seconds: 70)

        XCTAssertTrue(isAway(harness.state), "a late poll is not the user, got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    func testAnAbsenceCannotBeginBeforeTheLastBreakEnded() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let idle = stayAway(harness, for: 8 * minute)
        harness.clock.advance(60)
        harness.send(.wake(gapSeconds: 60))
        harness.run(seconds: 70)
        XCTAssertEqual(harness.snapshot.doneToday, 1, "the machine woke with nobody at it")

        // Still nobody there: the idle clock has not reset, but those minutes were just credited.
        harness.clock.advance(2)
        poll(harness, idle: idle + 132)
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
    }

    // MARK: - A break the display slept on

    func testABreakCutShortByDisplaySleepCountsOnceWhenInputArrivesFirst() {
        let harness = breakInterruptedByDisplaySleep()
        harness.clock.advance(10 * minute)
        poll(harness, idle: 0)
        harness.clock.advance(1)
        harness.send(.wake(gapSeconds: 1))
        harness.run(seconds: 70)

        XCTAssertEqual(harness.snapshot.doneToday, 1, "three minutes of the break counted, exactly once")
        XCTAssertNil(harness.snapshot.interruptedBreak)
        XCTAssertTrue(harness.state.isSitting)
    }

    func testABreakCutShortByDisplaySleepCountsOnceWhenTheWakeArrivesFirst() {
        let harness = breakInterruptedByDisplaySleep()
        harness.clock.advance(10 * minute)
        harness.send(.wake(gapSeconds: 1))
        poll(harness, idle: 0)
        harness.run(seconds: 70)

        XCTAssertEqual(harness.snapshot.doneToday, 1)
        XCTAssertNil(harness.snapshot.interruptedBreak)
        XCTAssertTrue(harness.state.isSitting)
    }

    private func breakInterruptedByDisplaySleep() -> SchedulerHarness {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.clock.advance(3 * minute)
        harness.send(.sleep)
        // The display slept but the machine did not, so the monitors keep polling.
        harness.clock.advance(2)
        poll(harness, idle: 182)
        return harness
    }

    // MARK: - Standby

    /// The line between a credited break and standby is the sitting interval itself, whatever
    /// that interval has been set to.
    func testJustUnderTheSittingIntervalIsCreditedAndJustOverIsStandby() {
        let credited = SchedulerHarness()
        credited.run(seconds: 10 * minute)
        credited.clearEffects()
        _ = stayAway(credited, for: 54 * minute)
        credited.clock.advance(2)
        poll(credited, idle: 0)

        XCTAssertEqual(credited.snapshot.doneToday, 1, "54 minutes is still a break")
        XCTAssertEqual(toastCount(credited.effects), 1)

        let standby = SchedulerHarness()
        standby.run(seconds: 10 * minute)
        standby.clearEffects()
        _ = stayAway(standby, for: 56 * minute)
        let back = standby.now
        standby.clock.advance(2)
        poll(standby, idle: 0)

        XCTAssertEqual(standby.snapshot.doneToday, 0, "56 minutes is standby")
        XCTAssertEqual(toastCount(standby.effects), 0, "standby says nothing")
        XCTAssertFalse(standby.effects.contains(.chime(.toast)))
        XCTAssertTrue(standby.state.isSitting)
        XCTAssertDate(standby.snapshot.boutStartedAt, back, accuracy: 6, "the countdown starts again")
        XCTAssertDate(standby.snapshot.nextFullDueAt, back.addingTimeInterval(55 * minute), accuracy: 6)
    }

    func testTheStandbyThresholdFollowsThePreset() {
        let harness = SchedulerHarness(config: .from(preset: .twentyFiveFive))
        harness.run(seconds: 5 * minute)
        harness.clearEffects()
        _ = stayAway(harness, for: 26 * minute)
        harness.clock.advance(2)
        poll(harness, idle: 0)

        XCTAssertEqual(harness.snapshot.doneToday, 0, "26 minutes is a whole 25/5 interval")
        XCTAssertEqual(toastCount(harness.effects), 0)
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(25 * minute), accuracy: 6)
    }

    /// The bout the user was in when they left is still time spent sitting, and the longest bout
    /// of the day has to remember it.
    func testStandbyKeepsTheBoutThatEndedWhenTheUserLeft() {
        let harness = SchedulerHarness()
        harness.run(seconds: 40 * minute)
        _ = stayAway(harness, for: 90 * minute)
        harness.clock.advance(2)
        poll(harness, idle: 0)

        XCTAssertEqual(harness.snapshot.longestBoutSeconds, 40 * 60, accuracy: 10)
    }

    func testStandbyRollsTheCountersOnlyWhenTheAbsenceCrossedMidnight() {
        let afternoon = SchedulerHarness(startAt: SchedulerHarness.mondayMorning.addingTimeInterval(5 * 3600))
        afternoon.scheduler.snapshot.snoozedToday = 3
        afternoon.run(seconds: 2 * minute)
        _ = stayAway(afternoon, for: 5 * 3600)
        afternoon.clock.advance(2)
        poll(afternoon, idle: 0)
        XCTAssertEqual(afternoon.snapshot.snoozedToday, 3, "14:00 to 19:00 is one day")

        let overnight = SchedulerHarness(startAt: SchedulerHarness.mondayMorning.addingTimeInterval(14 * 3600 + 30 * 60))
        overnight.scheduler.snapshot.snoozedToday = 3
        overnight.run(seconds: 2 * minute)
        _ = stayAway(overnight, for: 90 * minute)
        overnight.clock.advance(2)
        poll(overnight, idle: 0)
        XCTAssertEqual(overnight.snapshot.snoozedToday, 0, "23:30 to 01:00 crosses into a new day")
    }

    /// A break that was on screen when the lid closed is resumed only if the user comes back to
    /// it. An hour later there is nothing to come back to.
    func testStandbyDiscardsABreakTheLidClosedOn() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.clock.advance(minute)
        harness.send(.sleep)
        XCTAssertNotNil(harness.snapshot.interruptedBreak)

        harness.clock.advance(2 * 3600)
        harness.send(.wake(gapSeconds: 2 * 3600))
        harness.run(seconds: 70)

        XCTAssertNil(harness.snapshot.interruptedBreak)
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    /// The app was not running at all. It knows nothing about those minutes, so it judges them
    /// the same way it judges a stretch of idle: long enough, and the interval starts again.
    func testALaunchGapAsLongAsTheIntervalStartsTheIntervalAgain() {
        let harness = SchedulerHarness()
        harness.scheduler.snapshot.skipsToday = 1
        harness.run(seconds: 10 * minute)
        _ = harness.scheduler.applyLaunchGap(seconds: 70 * 60, now: harness.now)

        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute), accuracy: 6)
        XCTAssertEqual(harness.snapshot.skipsToday, 1, "a gap is not a new day")
    }

    func testAShortLaunchGapStillOnlyMovesTheCountdownOn() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let due = harness.snapshot.nextFullDueAt
        _ = harness.scheduler.applyLaunchGap(seconds: 20 * 60, now: harness.now)

        XCTAssertDate(harness.snapshot.nextFullDueAt, (due ?? harness.now).addingTimeInterval(20 * minute), accuracy: 2)
    }

    // MARK: - Display sleep without system sleep

    func testThreeHoursWithTheDisplayAsleepIsStandbyWhenInputArrivesFirst() {
        let harness = displayAsleep(hours: 3)
        let back = harness.now
        harness.clock.advance(2)
        poll(harness, idle: 0)
        harness.clock.advance(1)
        harness.send(.wake(gapSeconds: 1))
        harness.clearEffects()
        harness.run(seconds: 70)

        XCTAssertEqual(harness.snapshot.doneToday, 0, "three hours away is standby, not a break")
        XCTAssertDate(harness.snapshot.boutStartedAt, back, accuracy: 4, "a fresh bout from the return")
        XCTAssertFalse(harness.effectNames.contains("showToast"), "standby says nothing")
        XCTAssertFalse(harness.effectNames.contains("showHeadsUp"), "no break prompt for someone just back")
    }

    func testThreeHoursWithTheDisplayAsleepIsStandbyWhenTheWakeArrivesFirst() {
        let harness = displayAsleep(hours: 3)
        harness.clock.advance(2)
        harness.send(.wake(gapSeconds: 2))
        poll(harness, idle: 0)
        harness.clearEffects()
        harness.run(seconds: 70)

        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertGreaterThan(harness.snapshot.nextFullDueAt ?? .distantPast, harness.now.addingTimeInterval(50 * minute))
        XCTAssertFalse(harness.effectNames.contains("showToast"))
        XCTAssertFalse(harness.effectNames.contains("showHeadsUp"))
    }

    func testFourAndAHalfHoursAwayWithInputFirstIsStandbyAndKeepsTheDay() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.scheduler.snapshot.skipsToday = 2
        _ = stayAway(harness, for: 4.5 * 3600)
        harness.clock.advance(2)
        poll(harness, idle: 0)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.skipsToday, 2, "only midnight ends a day, however long the absence")
        XCTAssertEqual(harness.snapshot.doneToday, 0, "and an absence is never credited as a break")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute), accuracy: 12)
    }

    private func displayAsleep(hours: Double) -> SchedulerHarness {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.send(.sleep)
        _ = stayAway(harness, for: hours * 3600)
        return harness
    }

    // MARK: - Several notifications for one wake

    func testALaterWakeNotificationCannotShrinkTheAbsence() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.scheduler.snapshot.skipsToday = 2
        harness.send(.sleep)

        harness.clock.advance(5 * 3600)
        harness.send(.wake(gapSeconds: 5 * 3600))
        // The monitors have polled by now, so screens-wake and unlock measure almost nothing.
        harness.clock.advance(3)
        harness.send(.wake(gapSeconds: 1))
        harness.clock.advance(2)
        harness.send(.unlock(gapSeconds: 2))
        harness.clearEffects()
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.skipsToday, 2, "five hours is standby, and standby keeps the day")
        XCTAssertGreaterThan(harness.snapshot.nextFullDueAt ?? .distantPast, harness.now)
        XCTAssertFalse(harness.effectNames.contains("showHeadsUp"))
    }

    func testSleepingAgainInsideTheQuietMinuteKeepsTheAbsence() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.scheduler.snapshot.skipsToday = 2
        let left = harness.now
        harness.send(.sleep)

        harness.clock.advance(5 * 3600)
        harness.send(.wake(gapSeconds: 5 * 3600))
        harness.clock.advance(20)
        harness.send(.sleep)
        guard case .away(let since) = harness.state else { return XCTFail("expected away, got \(harness.state)") }
        XCTAssertEqual(since, left, "still measured from when the user first left")

        harness.clock.advance(60)
        harness.send(.wake(gapSeconds: 3))
        harness.run(seconds: 70)
        XCTAssertEqual(harness.snapshot.skipsToday, 2)
        XCTAssertTrue(harness.state.isSitting)
    }

    // MARK: - Wakes that have nothing to resolve

    func testAWakeOffHoursChangesNothing() {
        let evening = SchedulerHarness.mondayMorning.addingTimeInterval(11 * 3600)
        let harness = SchedulerHarness(workingHours: .standard, startAt: evening)
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")

        XCTAssertEqual(harness.send(.wake(gapSeconds: 3 * 3600)), [])
        XCTAssertEqual(harness.state.name, "off_hours", "a wake off hours must not leave the monitors stopped")
    }

    func testAnAbsenceThatRanIntoOffHoursLeavesNoStaleDueTimeForTheMorning() {
        let lateAfternoon = SchedulerHarness.mondayMorning.addingTimeInterval(8 * 3600 + 40 * 60)
        let harness = SchedulerHarness(workingHours: .standard, startAt: lateAfternoon)
        harness.send(.tick)
        harness.clock.advance(6 * minute)
        harness.send(.idle(seconds: 6 * 60))
        XCTAssertNotNil(harness.snapshot.dueAtAway)

        harness.clock.set(SchedulerHarness.mondayMorning.addingTimeInterval(9 * 3600 + 5 * 60))
        harness.send(.tick)
        XCTAssertEqual(harness.state.name, "off_hours")
        XCTAssertNil(harness.snapshot.dueAtAway, "the absence ended with the working day")

        harness.clock.set(SchedulerHarness.mondayMorning.addingTimeInterval(24 * 3600 + 30 * 60))
        harness.send(.tick)
        harness.send(.unlock(gapSeconds: 2))
        harness.clearEffects()
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertGreaterThan(harness.snapshot.nextFullDueAt ?? .distantPast, harness.now)
        XCTAssertFalse(harness.effectNames.contains("showHeadsUp"))
    }

    func testAnUnlockForAReturnAlreadyHandledLeavesTheHeadsUpAlone() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        let before = harness.state

        XCTAssertEqual(harness.send(.unlock(gapSeconds: 2)), [])
        XCTAssertEqual(harness.state, before)
    }

    // MARK: - Evidence of input

    func testALockAtTheDebugTimeScaleStaysAwayUntilSomethingIsTouched() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.send(.lock)

        // At 60× the clock moves a minute for every real second the idle counter moves.
        harness.clock.advance(60)
        harness.send(.input(lastEventAgeSeconds: 1))
        harness.clock.advance(60)
        harness.send(.input(lastEventAgeSeconds: 2))

        XCTAssertTrue(isAway(harness.state), "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    func testATenSecondLockWithInputBeforeTheUnlockChangesNothing() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let due = harness.snapshot.nextFullDueAt
        let bout = harness.snapshot.boutStartedAt

        harness.send(.lock)
        harness.clock.advance(2)
        poll(harness, idle: 2)
        harness.clock.advance(8)
        poll(harness, idle: 0)
        harness.send(.unlock(gapSeconds: 10))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, due, "the countdown is exactly where it was")
        XCTAssertEqual(harness.snapshot.boutStartedAt, bout)
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    func testARelaunchWhileAwayIsNotAReturn() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.clock.advance(6 * minute)
        harness.send(.idle(seconds: 6 * 60))

        harness.clock.advance(10 * minute)
        _ = harness.scheduler.applyLaunchGap(seconds: 10 * 60, now: harness.now)
        // The system idle counter kept climbing while movez was gone.
        harness.send(.input(lastEventAgeSeconds: 16 * 60))

        XCTAssertTrue(isAway(harness.state), "got \(harness.state)")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }
}

/// The coordinator's half: what reaches history, and what reaches the speaker.
@MainActor
final class AwayReturnCoordinatorTests: XCTestCase {
    func testPollingThroughAnAbsenceWritesOneHistoryRecord() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        harness.run(seconds: 10 * 60)

        var idle = 0
        while idle < 20 * 60 {
            harness.clock.advance(2)
            idle += 2
            harness.coordinator.inject(.input(lastEventAgeSeconds: idle))
            harness.coordinator.inject(.idle(seconds: idle))
            harness.coordinator.tick()
        }
        XCTAssertTrue(harness.history.data.breakRecords.isEmpty, "nothing is recorded while the user is gone")

        harness.clock.advance(2)
        harness.coordinator.inject(.input(lastEventAgeSeconds: 0))

        XCTAssertEqual(harness.history.data.breakRecords.map(\.outcome), [.credited])
        XCTAssertEqual(harness.history.stats(on: harness.now).done, 1)
        XCTAssertEqual(harness.sink.names.filter { $0 == "showToast" }.count, 1)
        XCTAssertEqual(harness.sink.names.filter { $0 == "chime(toast)" }.count, 1)
    }

    func testTheToastChimeIsSilentWithSoundsOff() {
        let recorder = RecordingChimePlayer()
        var soundsOn = false
        let player = GatedChimePlayer(wrapping: recorder, isEnabled: { soundsOn })

        player.play(.toast)
        XCTAssertTrue(recorder.played.isEmpty)

        soundsOn = true
        player.play(.toast)
        XCTAssertEqual(recorder.played, [.toast])
    }

    func testTheToastChimeShipsWithTheApp() {
        XCTAssertNotNil(MovezBundle.resources.url(forResource: "toast", withExtension: "wav", subdirectory: "Chimes"))
    }
}
