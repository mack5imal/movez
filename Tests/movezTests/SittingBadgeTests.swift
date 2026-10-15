import XCTest
@testable import movez

/// The heads-up's "Sitting for …" counts the current sitting bout. It once counted from the last
/// completed break, which an absence no longer moves, so a morning after a night away read
/// "Sitting for 17 h" although standby had restarted everything (DECISIONS 48).
final class SittingBadgeTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// Finishes a full break taken now, so that `lastCompletedBreakAt` is set.
    private func completeABreak(_ harness: SchedulerHarness) {
        harness.send(.userTakeBreakNow)
        XCTAssertTrue(harness.run(until: { $0.isFullBreak }, limit: 2 * minute), "got \(harness.state)")
        harness.run(seconds: 325)
        harness.send(.userDone(completedBlocks: 5, totalBlocks: 5, elapsed: 325))
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
    }

    func testTheBadgeCountsFromTheReturnAfterStandby() throws {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        completeABreak(harness)
        let lastBreak = try XCTUnwrap(harness.snapshot.lastCompletedBreakAt)

        harness.clock.advance(60 * minute)
        harness.send(.idle(seconds: 3600))
        harness.send(.input(lastEventAgeSeconds: 0))
        let back = harness.now
        harness.run(seconds: 20 * minute)

        let info = harness.scheduler.headsUpInfo(now: harness.now, deferredSince: back)
        XCTAssertEqual(info.sittingSince, harness.snapshot.boutStartedAt)
        XCTAssertDate(info.sittingSince, back, accuracy: 4)
        XCTAssertNotEqual(info.sittingSince, lastBreak)
        XCTAssertEqual(Double(info.sittingSeconds), 20 * minute, accuracy: 4)
    }

    /// A paused absence shifts the bout forward by its length, so the badge counts desk time only.
    func testTheBadgeLeavesOutAPausedAbsence() {
        var config = SchedulerConfig()
        config.awayBehaviour = .pause
        let harness = SchedulerHarness(config: config)
        harness.run(seconds: 10 * minute)
        completeABreak(harness)
        harness.run(seconds: 10 * minute)

        harness.clock.advance(20 * minute)
        harness.send(.idle(seconds: 1200))
        harness.send(.input(lastEventAgeSeconds: 0))
        harness.run(seconds: 10 * minute)

        let info = harness.scheduler.headsUpInfo(now: harness.now, deferredSince: nil)
        XCTAssertEqual(info.sittingSince, harness.snapshot.boutStartedAt)
        XCTAssertEqual(Double(info.sittingSeconds), 20 * minute, accuracy: 4, "ten minutes either side of the absence")
    }
}
