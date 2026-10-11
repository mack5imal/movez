import XCTest
@testable import movez

final class SchedulerInterruptionTests: XCTestCase {
    private let minute: TimeInterval = 60

    // MARK: - Idle

    func testShortIdleChangesNothing() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let due = harness.snapshot.nextFullDueAt
        harness.send(.idle(seconds: 120))
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, due)
    }

    private func toast(_ harness: SchedulerHarness) -> ToastInfo? {
        harness.effects.compactMap { effect -> ToastInfo? in
            if case .showToast(let info) = effect { return info } else { return nil }
        }.first
    }

    private func absences(_ harness: SchedulerHarness) -> [AbsenceRecord] {
        harness.effects.compactMap { effect -> AbsenceRecord? in
            if case .recordAbsence(let record) = effect { return record } else { return nil }
        }
    }

    private func pausing() -> SchedulerConfig {
        var config = SchedulerConfig()
        config.awayBehaviour = .pause
        return config
    }

    /// Reset, the default: any absence past the threshold starts both countdowns again, and is
    /// logged, but it is not a break.
    func testAKitchenTripResetsBothCountdownsAndIsNotABreak() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let lastBreak = harness.snapshot.lastCompletedBreakAt

        harness.clock.advance(4 * minute)
        harness.send(.idle(seconds: 240))
        guard case .away(let since) = harness.state else { return XCTFail("expected away, got \(harness.state)") }
        XCTAssertEqual(since, harness.now.addingTimeInterval(-240))

        harness.clearEffects()
        harness.send(.input(lastEventAgeSeconds: 0))
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.boutStartedAt, harness.now)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, harness.now.addingTimeInterval(30 * minute))
        XCTAssertEqual(harness.snapshot.doneToday, 0, "an absence is not a break")
        XCTAssertEqual(harness.snapshot.lastCompletedBreakAt, lastBreak)

        XCTAssertEqual(toast(harness)?.behaviour, .reset)
        XCTAssertEqual(toast(harness)?.awaySeconds, 240)
        XCTAssertEqual(toast(harness)?.reversal, .wasSitting)
        XCTAssertEqual(absences(harness), [AbsenceRecord(behaviour: .reset, awaySeconds: 240)])
        XCTAssertEqual(harness.effectNames.prefix(3), ["recordAbsence(reset)", "showToast", "chime(toast)"])
    }

    func testALongerAbsenceIsTheSameResetAndStillNotABreak() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.clearEffects()
        harness.send(.input(lastEventAgeSeconds: 0))

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertEqual(harness.snapshot.boutStartedAt, harness.now)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
        XCTAssertEqual(toast(harness)?.behaviour, .reset)
        XCTAssertEqual(absences(harness).count, 1)
    }

    /// Pause: both countdowns stand still while the user is gone and carry on with exactly what
    /// they had.
    func testPauseHandsBothCountdownsBackWithTheTimeTheyHad() {
        let harness = SchedulerHarness(config: pausing())
        harness.run(seconds: 10 * minute)
        let fullLeft = harness.snapshot.nextFullDueAt!.timeIntervalSince(harness.now)
        let microLeft = harness.snapshot.nextMicroDueAt!.timeIntervalSince(harness.now)

        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.clearEffects()
        harness.send(.input(lastEventAgeSeconds: 0))

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(fullLeft))
        XCTAssertDate(harness.snapshot.nextMicroDueAt, harness.now.addingTimeInterval(microLeft))
        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertEqual(toast(harness)?.behaviour, .pause)
        XCTAssertEqual(absences(harness), [AbsenceRecord(behaviour: .pause, awaySeconds: 420)])
    }

    /// The bout moves forward with the due times, so re-planning on a settings change keeps the
    /// countdown the pause handed back.
    func testASettingsChangeAfterAPauseDoesNotMoveTheCountdown() {
        let harness = SchedulerHarness(config: pausing())
        harness.run(seconds: 10 * minute)
        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.send(.input(lastEventAgeSeconds: 0))
        let full = harness.snapshot.nextFullDueAt
        let micro = harness.snapshot.nextMicroDueAt

        var config = pausing()
        config.workingHours = .alwaysOn
        config.awayThresholdSeconds = 240
        harness.send(.settingsChanged(config))
        XCTAssertEqual(harness.snapshot.nextFullDueAt, full)
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, micro)
    }

    func testIWasSittingUndoesAResetExactly() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let before = harness.snapshot

        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.send(.input(lastEventAgeSeconds: 0))

        harness.clock.advance(3)
        harness.send(.toastReverse(.wasSitting))
        XCTAssertEqual(harness.snapshot.doneToday, before.doneToday)
        XCTAssertEqual(harness.snapshot.boutStartedAt, before.boutStartedAt)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, before.nextFullDueAt)
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, before.nextMicroDueAt)
        XCTAssertEqual(harness.snapshot.lastCompletedBreakAt, before.lastCompletedBreakAt)
        XCTAssertTrue(harness.state.isSitting)
    }

    func testIWasSittingUndoesAPauseExactly() {
        let harness = SchedulerHarness(config: pausing())
        harness.run(seconds: 10 * minute)
        let before = harness.snapshot

        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.send(.input(lastEventAgeSeconds: 0))
        XCTAssertNotEqual(harness.snapshot.nextFullDueAt, before.nextFullDueAt)

        harness.clock.advance(3)
        let effects = harness.send(.toastReverse(.wasSitting))
        XCTAssertTrue(effects.contains(.hideToast))
        XCTAssertEqual(harness.snapshot.boutStartedAt, before.boutStartedAt)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, before.nextFullDueAt, "the minutes away count as sitting")
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, before.nextMicroDueAt)
        XCTAssertEqual(harness.snapshot.microAnchorAt, before.microAnchorAt)
    }

    func testReversalExpiresWithTheToast() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.clock.advance(7 * minute)
        harness.send(.idle(seconds: 7 * 60))
        harness.send(.input(lastEventAgeSeconds: 0))
        let due = harness.snapshot.nextFullDueAt

        harness.clock.advance(30)
        XCTAssertEqual(harness.send(.toastReverse(.wasSitting)), [], "the toast is long gone")
        XCTAssertEqual(harness.snapshot.nextFullDueAt, due)
    }

    /// A closed lid pauses the countdowns too, from when the lid closed to when the machine woke;
    /// the quiet minute after the wake is the user back at the desk.
    func testALidClosedForTenMinutesPausesTheCountdowns() {
        let harness = SchedulerHarness(config: pausing())
        harness.run(seconds: 10 * minute)
        let fullLeft = harness.snapshot.nextFullDueAt!.timeIntervalSince(harness.now)
        harness.send(.sleep)
        harness.clock.advance(10 * minute)
        let wokeAt = harness.now
        harness.send(.wake(gapSeconds: 600))
        harness.clearEffects()
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, wokeAt.addingTimeInterval(fullLeft))
        XCTAssertEqual(absences(harness), [AbsenceRecord(behaviour: .pause, awaySeconds: 600)])
        XCTAssertEqual(toast(harness)?.behaviour, .pause)
    }

    /// Standby is the same whichever behaviour is chosen: silent, and logged as a reset.
    func testStandbyIsSilentInBothBehavioursAndLoggedAsAReset() {
        for config in [SchedulerConfig(), pausing()] {
            let harness = SchedulerHarness(config: config)
            harness.run(seconds: 10 * minute)
            harness.clock.advance(70 * minute)
            harness.send(.idle(seconds: 70 * 60))
            harness.clearEffects()
            harness.send(.input(lastEventAgeSeconds: 0))

            XCTAssertNil(toast(harness), "\(config.awayBehaviour)")
            XCTAssertEqual(absences(harness), [AbsenceRecord(behaviour: .reset, awaySeconds: 70 * 60)])
            XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
            XCTAssertEqual(harness.snapshot.doneToday, 0)
        }
    }

    // MARK: - Sleep, lock and wake

    func testSleepDuringABreakInterruptsItAndAShortGapResumesIt() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.clock.advance(60)

        harness.clearEffects()
        harness.send(.sleep)
        XCTAssertTrue(harness.effects.contains(.endFullBreak(.interrupted)))
        XCTAssertTrue(harness.effects.contains(.hideHeadsUp))
        XCTAssertTrue(harness.effects.contains(.hideMicro))
        XCTAssertNotNil(harness.snapshot.interruptedBreak)

        harness.clock.advance(120)
        harness.send(.wake(gapSeconds: 120))
        guard case .postBreakGrace = harness.state else { return XCTFail("expected grace, got \(harness.state)") }

        harness.clearEffects()
        harness.run(seconds: 50)
        XCTAssertFalse(harness.effectNames.contains("showHeadsUp"), "nothing fires during the quiet minute")
        XCTAssertFalse(harness.effectNames.contains("startFullBreak"))

        harness.run(seconds: 20)
        XCTAssertTrue(harness.state.isFullBreak, "the break picks up where it left off")
        XCTAssertTrue(harness.effectNames.contains("startFullBreak"))
    }

    func testALongGapEndsAnInterruptedBreakByTheCompletionRule() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.clock.advance(3 * minute)
        harness.send(.sleep)

        harness.clock.advance(20 * minute)
        harness.send(.wake(gapSeconds: 1200))
        harness.run(until: { !$0.isBreakSurfaceVisible && $0 != .away(since: harness.now) }, limit: 5 * minute)
        harness.run(seconds: 70)

        XCTAssertFalse(harness.state.isFullBreak, "a break that expired while asleep is not resumed")
        XCTAssertEqual(harness.snapshot.doneToday, 1, "three minutes of it counted")
        XCTAssertNil(harness.snapshot.interruptedBreak)
    }

    func testAFiveHourGapIsStandby() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.clock.advance(4)
        harness.send(.userSkip)
        XCTAssertEqual(harness.snapshot.skipsToday, 1)

        harness.send(.sleep)
        harness.clock.advance(5 * 3600)
        harness.send(.wake(gapSeconds: 5 * 3600))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.skipsToday, 1, "the day's counters outlast any absence; only midnight rolls them")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute), accuracy: 12)
    }

    func testATenSecondLockChangesNothing() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let due = harness.snapshot.nextFullDueAt
        let bout = harness.snapshot.boutStartedAt

        harness.send(.lock)
        harness.clock.advance(10)
        harness.send(.unlock(gapSeconds: 10))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, due, "the countdown is exactly where it was")
        XCTAssertEqual(harness.snapshot.boutStartedAt, bout)
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    // MARK: - Suppression

    func testACallDefersTheBreakAndBringsItBackWithABadge() {
        let harness = SchedulerHarness()
        harness.run(seconds: 50 * minute)
        let dueBefore = harness.snapshot.nextFullDueAt
        harness.scheduler.snapshot.nextMicroDueAt = harness.now.addingTimeInterval(2 * minute)

        harness.send(.signals(SignalSnapshot(microphoneActive: true)))
        guard case .suppressed = harness.state else { return XCTFail("expected suppressed, got \(harness.state)") }

        harness.clearEffects()
        harness.run(seconds: 10 * minute)
        guard case .suppressed(_, let deferred) = harness.state else { return XCTFail("still expected suppressed") }
        XCTAssertNotNil(deferred, "the break is waiting, not gone")
        XCTAssertEqual(harness.snapshot.nextFullDueAt, dueBefore, "the due time never moved")
        XCTAssertFalse(harness.effectNames.contains("showMicroCountIn"), "no micro-break during a call")

        harness.run(seconds: 35 * minute)
        harness.send(.signals(.quiet))
        guard case .postBreakGrace = harness.state else { return XCTFail("expected the 2 min grace") }

        harness.run(seconds: 130)
        XCTAssertTrue(harness.state.isPendingFull)

        harness.clearEffects()
        harness.send(.input(lastEventAgeSeconds: 12))
        let info = harness.effects.compactMap { effect -> HeadsUpInfo? in
            if case .showHeadsUp(let info) = effect { return info } else { return nil }
        }.first
        XCTAssertEqual(info?.showDeferredBadge, true)
        XCTAssertEqual(info?.maxSnoozes, 1)
        XCTAssertEqual(info?.sittingSince, harness.snapshot.boutStartedAt)
        XCTAssertEqual(harness.scheduler.snoozesLeft, 1)
    }

    func testSignalsDoNotInterruptABreakAlreadyOnScreen() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        XCTAssertEqual(harness.send(.signals(SignalSnapshot(fullscreenActive: true))), [])
        XCTAssertTrue(harness.state.isFullBreak)
    }

    // MARK: - Pause

    func testPauseHandsBackTheRemainingCountdown() {
        let harness = SchedulerHarness()
        harness.run(seconds: 35 * minute)
        let remaining = Int(harness.snapshot.nextFullDueAt?.timeIntervalSince(harness.now) ?? 0)
        XCTAssertEqual(remaining, 20 * 60, accuracy: 2)

        harness.clearEffects()
        harness.send(.userPause(seconds: 30 * 60))
        guard case .paused(let until) = harness.state else { return XCTFail("expected paused, got \(harness.state)") }
        XCTAssertEqual(until, harness.now.addingTimeInterval(30 * minute))
        XCTAssertTrue(harness.effects.contains(.pollingChanged(false)))
        XCTAssertFalse(harness.scheduler.pollingRequired)

        harness.send(.userExtendPause(seconds: 15 * 60))
        guard case .paused(let extended) = harness.state else { return XCTFail("expected paused") }
        XCTAssertEqual(extended, harness.now.addingTimeInterval(45 * minute))

        harness.clearEffects()
        harness.run(until: { $0.isSitting }, limit: 60 * minute)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(TimeInterval(remaining)), accuracy: 3)
        XCTAssertTrue(harness.effects.contains(.pollingChanged(true)))
    }

    func testResumeAndTakeABreakBothEndAPause() {
        let harness = SchedulerHarness()
        harness.run(seconds: 20 * minute)
        harness.send(.userPause(seconds: 2 * 3600))
        harness.clock.advance(minute)
        harness.send(.userResume)
        XCTAssertTrue(harness.state.isSitting)

        harness.send(.userPause(seconds: 2 * 3600))
        harness.send(.userTakeBreakNow)
        XCTAssertTrue(harness.state.isFullBreak)
        XCTAssertTrue(harness.scheduler.pollingRequired)
    }

    func testFocusFilterPausesAndOnlyLiftsItsOwnPause() {
        let harness = SchedulerHarness()
        harness.run(seconds: 20 * minute)
        harness.send(.focusFilter(paused: true))
        XCTAssertEqual(harness.state, .paused(until: nil))

        harness.send(.focusFilter(paused: false))
        XCTAssertTrue(harness.state.isSitting)

        harness.send(.userPause(seconds: 3600))
        XCTAssertEqual(harness.send(.focusFilter(paused: false)), [], "a hand-set pause outranks Focus")
        guard case .paused = harness.state else { return XCTFail("expected the manual pause to survive") }
    }

    func testRestOfDayPauseRunsToTheEndOfWorkingHours() {
        let harness = SchedulerHarness(workingHours: .standard)
        harness.send(.userPause(seconds: nil))
        guard case .paused(let until) = harness.state else { return XCTFail("expected paused") }
        let expected = WorkingHours.standard.endOfToday(harness.now, calendar: .current)
        XCTAssertEqual(until, expected)
    }

    // MARK: - Working hours

    func testSaturdayIsOffHoursUntilAHandStartedSession() {
        let saturday = Calendar.current.date(byAdding: .day, value: 5, to: SchedulerHarness.mondayMorning)
        let harness = SchedulerHarness(workingHours: .standard, startAt: saturday?.addingTimeInterval(101 * minute))
        harness.run(seconds: 10)
        XCTAssertEqual(harness.state, .offHours)
        XCTAssertFalse(harness.scheduler.pollingRequired)

        let nextStart = harness.scheduler.nextWorkingStart(after: harness.now)
        let weekday = nextStart.map { Calendar.current.component(.weekday, from: $0) }
        XCTAssertEqual(weekday, 2, "the next opening is Monday")
        XCTAssertEqual(nextStart.map { WorkingHours.minutes(of: $0, calendar: .current) }, 9 * 60)

        harness.send(.userStartSession)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
        XCTAssertTrue(harness.scheduler.pollingRequired)

        harness.send(.userEndSession)
        XCTAssertEqual(harness.state, .offHours)
    }

    func testAnAdHocSessionEndsAtMidnight() {
        let saturday = Calendar.current.date(byAdding: .day, value: 5, to: SchedulerHarness.mondayMorning)
        let harness = SchedulerHarness(
            workingHours: .standard,
            startAt: saturday?.addingTimeInterval(13 * 3600)
        )
        harness.run(seconds: 10)
        harness.send(.userStartSession)
        XCTAssertTrue(harness.snapshot.adHocSession)

        harness.clock.advance(3 * 3600)
        harness.send(.tick)
        XCTAssertEqual(harness.state, .offHours)
        XCTAssertFalse(harness.snapshot.adHocSession)
    }

    func testWorkingHoursStartOpensAFreshInterval() {
        // Sunday 09:00 plus 23 hours is Monday 08:00 — an hour before the working day opens.
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: SchedulerHarness.mondayMorning)
        let harness = SchedulerHarness(
            workingHours: .standard,
            startAt: sunday?.addingTimeInterval(23 * 3600)
        )
        harness.run(seconds: 10)
        XCTAssertEqual(harness.state, .offHours)

        harness.clock.advance(90 * minute)
        harness.send(.tick)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    // MARK: - Polling

    func testPollingIsOffOnlyWhenPausedOrOffHours() {
        let harness = SchedulerHarness()
        XCTAssertTrue(harness.scheduler.pollingRequired)

        harness.send(.userPause(seconds: 3600))
        XCTAssertFalse(harness.scheduler.pollingRequired)
        harness.send(.userResume)
        XCTAssertTrue(harness.scheduler.pollingRequired)

        harness.send(.idle(seconds: 400))
        XCTAssertTrue(harness.scheduler.pollingRequired, "away still needs to notice the user coming back")
        harness.send(.input(lastEventAgeSeconds: 0))

        harness.send(.signals(SignalSnapshot(microphoneActive: true)))
        XCTAssertTrue(harness.scheduler.pollingRequired, "suppressed still needs to notice the call ending")
    }

    // MARK: - Evidence

    func testWritesSuppressionAndSleepTransitionLogs() {
        let suppression = SchedulerHarness()
        suppression.run(seconds: 50 * minute)
        suppression.send(.signals(SignalSnapshot(microphoneActive: true)))
        suppression.run(seconds: 40 * minute)
        suppression.send(.signals(.quiet))
        suppression.run(seconds: 130)
        suppression.send(.input(lastEventAgeSeconds: 12))
        RoutineTestSupport.write(
            "A 40-minute call that starts five minutes before a break is due\n\n"
                + suppression.snapshot.transitions.rendered() + "\n",
            to: "transition-log-suppression.txt"
        )

        let sleep = SchedulerHarness()
        sleep.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        sleep.send(.userStartNow)
        sleep.clock.advance(60)
        sleep.send(.sleep)
        sleep.clock.advance(2 * minute)
        sleep.send(.wake(gapSeconds: 120))
        sleep.run(seconds: 70)
        RoutineTestSupport.write(
            "A lid closed one minute into a break and reopened two minutes later\n\n"
                + sleep.snapshot.transitions.rendered() + "\n",
            to: "transition-log-sleep.txt"
        )

        XCTAssertTrue(suppression.snapshot.transitions.count > 3)
        XCTAssertTrue(sleep.snapshot.transitions.count > 3)
    }
}
