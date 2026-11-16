import XCTest
@testable import movez

/// The debug time scale is a tool for watching a day go by in minutes. Whatever happens at 60× is
/// scratch: it is never saved, never written into the real history or state file, and it ends
/// back on wall time with a fresh countdown (UI-10, DECISIONS 87).
@MainActor
final class DebugTimeScaleTests: XCTestCase {
    private func harness() -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn)
    }

    // MARK: - Not saved

    func testEveryLaunchStartsAtOneTimes() {
        let suite = ScratchDefaults.make()
        let settings = SettingsStore(defaults: suite)
        settings.debugTimeScale = 60

        XCTAssertEqual(SettingsStore(defaults: suite).debugTimeScale, 1)
    }

    /// A scale an earlier build saved is dropped rather than read back.
    func testAScaleSavedByAnEarlierBuildIsIgnored() {
        let suite = ScratchDefaults.make()
        suite.set(60.0, forKey: "debugTimeScale")

        XCTAssertEqual(SettingsStore(defaults: suite).debugTimeScale, 1)
        XCTAssertNil(suite.object(forKey: "debugTimeScale"), "and the stale key is removed")
    }

    // MARK: - Scratch stores

    func testAScaledRunWritesNothingToTheRealHistoryOrStateFile() {
        let harness = harness()
        harness.run(seconds: 60)
        harness.coordinator.deliver([.persist])
        let realHistory = harness.history.data
        let historySaves = harness.historyStore.saveCount
        let stateSaves = harness.snapshotStore.saveCount
        let debug = DebugViewModel(coordinator: harness.coordinator)

        debug.setTimeScale(60)
        harness.coordinator.takeBreakNow()
        harness.completeBreak()
        harness.run(seconds: 120)

        XCTAssertFalse(harness.coordinator.history === harness.history, "a scratch history while scaled")
        XCTAssertGreaterThan(harness.coordinator.history.data.breakRecords.count, realHistory.breakRecords.count)
        XCTAssertEqual(harness.history.data, realHistory, "the real history is untouched")
        XCTAssertEqual(harness.historyStore.saveCount, historySaves, "and its file is never written")
        XCTAssertEqual(harness.snapshotStore.saveCount, stateSaves, "nor is the state file")
    }

    /// Back at 1×, the real stores come back and the countdown starts again from now: the
    /// scaled run's due times and counters were in a future that never happened.
    func testReturningToOneTimesRestoresTheRealStoresAndReplansFromNow() {
        let harness = harness()
        harness.run(seconds: 20 * 60)
        let doneBefore = harness.scheduler.snapshot.doneToday
        let debug = DebugViewModel(coordinator: harness.coordinator)

        debug.setTimeScale(60)
        harness.coordinator.takeBreakNow()
        harness.completeBreak()
        XCTAssertEqual(harness.scheduler.snapshot.doneToday, doneBefore + 1)
        harness.run(seconds: 600)

        debug.setTimeScale(1)
        XCTAssertTrue(harness.coordinator.history === harness.history)
        XCTAssertEqual(harness.state.name, "sitting")
        XCTAssertEqual(harness.scheduler.snapshot.doneToday, doneBefore, "the scaled break was scratch")
        XCTAssertEqual(
            harness.scheduler.snapshot.secondsUntilFullBreak(at: harness.now),
            harness.scheduler.config.sitSeconds,
            "a fresh countdown from now"
        )

        // The state file is written again, from real time.
        let saves = harness.snapshotStore.saveCount
        harness.coordinator.deliver([.persist])
        harness.run(seconds: 60)
        XCTAssertGreaterThan(harness.snapshotStore.saveCount, saves)
    }

    /// A break on screen when the scale drops is taken down, not left over a fresh countdown.
    func testABreakOnScreenWhenTheScaleDropsIsTakenDown() {
        let harness = harness()
        let debug = DebugViewModel(coordinator: harness.coordinator)
        debug.setTimeScale(60)
        harness.coordinator.takeBreakNow()
        XCTAssertNotNil(harness.coordinator.currentBreak)

        debug.setTimeScale(1)
        XCTAssertNil(harness.coordinator.currentBreak)
        XCTAssertEqual(harness.state.name, "sitting")
    }

    // MARK: - The clock

    func testTheSystemClockSnapsBackToWallTimeAtOneTimes() {
        let clock = SystemClock()
        clock.timeScale = 60
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertGreaterThan(clock.now.timeIntervalSince(Date()), 20, "half a second at 60× is half a minute ahead")

        clock.timeScale = 1
        XCTAssertEqual(clock.now.timeIntervalSince(Date()), 0, accuracy: 0.1)
    }

    func testTheTickTimerFollowsTheScale() {
        let harness = harness()
        harness.coordinator.start()
        defer { harness.coordinator.stop() }
        XCTAssertEqual(harness.coordinator.tickInterval ?? 0, AppCoordinator.tickSeconds, accuracy: 0.001)

        DebugViewModel(coordinator: harness.coordinator).setTimeScale(4)
        XCTAssertEqual(harness.coordinator.tickInterval ?? 0, AppCoordinator.tickSeconds / 4, accuracy: 0.001)
    }

    // MARK: - A state file from the future

    /// A state file saved by a clock that ran ahead (an earlier build's 60×, or a clock set back by
    /// hand) has due times hours away. Its gap measured as zero, so nothing corrected them.
    func testAStateFileSavedInTheFutureIsTreatedAsClockSkew() {
        let harness = harness()
        harness.run(seconds: 60)
        var snapshot = harness.scheduler.snapshot
        let future = harness.now.addingTimeInterval(3 * 3600)
        snapshot.savedAt = future
        snapshot.boutStartedAt = future
        snapshot.nextFullDueAt = future.addingTimeInterval(55 * 60)
        try? harness.snapshotStore.save(snapshot)

        harness.relaunch()
        let remaining = harness.coordinator.scheduler.snapshot.secondsUntilFullBreak(at: harness.now) ?? .max
        XCTAssertLessThanOrEqual(remaining, harness.coordinator.scheduler.config.sitSeconds)
        XCTAssertLessThanOrEqual(harness.coordinator.scheduler.snapshot.boutStartedAt, harness.now)
    }
}
