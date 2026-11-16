import XCTest
@testable import movez

/// A settings change re-plans the countdown that is running, by the change it made. It must never
/// bring back a break the user skipped, paused or has just finished, which is what re-planning
/// from the bout start used to do: a skip, a resumed pause and a closed micro-break all move the
/// countdown on without moving the bout.
final class SchedulerSettingsReplanTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// A copy of the running config with one unrelated setting changed, the way most clicks in
    /// Settings (focus, equipment, the away threshold) reach the scheduler.
    private func unrelatedChange(_ harness: SchedulerHarness) -> SchedulerConfig {
        var config = harness.scheduler.config
        config.awayThresholdSeconds += 60
        return config
    }

    private func skipAtTheHeadsUp(_ harness: SchedulerHarness) {
        harness.run(until: { $0.isPendingFull }, limit: 60 * minute)
        harness.send(.input(lastEventAgeSeconds: 12))
        XCTAssertTrue(harness.state.isHeadsUp, "got \(harness.state)")
        harness.clock.advance(4)
        harness.send(.userSkip)
        XCTAssertTrue(harness.state.isSitting)
    }

    func testASettingChangedAfterASkipKeepsTheFreshInterval() {
        let harness = SchedulerHarness()
        skipAtTheHeadsUp(harness)
        let due = harness.snapshot.nextFullDueAt

        harness.run(seconds: 4 * minute)
        harness.send(.settingsChanged(unrelatedChange(harness)))
        harness.run(seconds: 10)

        XCTAssertTrue(harness.state.isSitting, "the skipped break must not come straight back, got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, due, "an unrelated setting leaves the countdown alone")
    }

    func testAPresetChangedAfterASkipMovesTheBreakByTheChange() {
        let harness = SchedulerHarness()
        skipAtTheHeadsUp(harness)
        let due = harness.snapshot.nextFullDueAt ?? .distantPast

        harness.run(seconds: 4 * minute)
        var longer = harness.scheduler.config
        longer.sitSeconds = 85 * 60
        harness.send(.settingsChanged(longer))

        XCTAssertDate(harness.snapshot.nextFullDueAt, due.addingTimeInterval(30 * minute),
                      "thirty minutes more sitting moves the break thirty minutes on")
    }

    func testASettingChangedAfterAManualPauseKeepsTheRestoredCountdown() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.send(.userPause(seconds: 60 * 60))
        harness.clock.advance(60 * minute)
        harness.send(.tick)
        XCTAssertTrue(harness.state.isSitting, "the pause ran out, got \(harness.state)")
        let due = harness.snapshot.nextFullDueAt ?? .distantPast
        XCTAssertDate(due, harness.now.addingTimeInterval(45 * minute), accuracy: 4,
                      "the pause hands back the 45 minutes it held")

        harness.send(.settingsChanged(unrelatedChange(harness)))
        harness.run(seconds: 10)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, due)
    }

    func testASettingChangedAfterAMicroBreakDoesNotServeASecondOne() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        harness.run(until: { $0.isSitting }, limit: 5 * minute)
        let micro = harness.snapshot.nextMicroDueAt
        harness.run(seconds: 3 * minute)

        harness.send(.settingsChanged(unrelatedChange(harness)))
        harness.run(seconds: 10)

        XCTAssertTrue(harness.state.isSitting, "a second micro-break must not start, got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextMicroDueAt, micro)
    }

    /// The case the old behaviour was right about, kept: changing the preset mid-bout keeps the
    /// time already sat, so the break lands where the new preset puts it from the bout start.
    func testAPresetChangedMidBoutStillCountsTheTimeAlreadySat() {
        let harness = SchedulerHarness()
        harness.run(seconds: 20 * minute)
        var shorter = harness.scheduler.config
        shorter.sitSeconds = 25 * 60
        shorter.microEnabled = false
        harness.send(.settingsChanged(shorter))

        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.start.addingTimeInterval(25 * minute))
        XCTAssertNil(harness.snapshot.nextMicroDueAt, "micro-breaks switched off")
    }

    func testTurningMicroBreaksBackOnPlansOneFromNow() {
        let harness = SchedulerHarness()
        var off = harness.scheduler.config
        off.microEnabled = false
        harness.send(.settingsChanged(off))
        harness.run(seconds: 10 * minute)

        var on = off
        on.microEnabled = true
        harness.send(.settingsChanged(on))

        XCTAssertDate(harness.snapshot.nextMicroDueAt, harness.now.addingTimeInterval(30 * minute),
                      "a micro-break turned on mid-bout is planned from the change, never in the past")
    }
}
