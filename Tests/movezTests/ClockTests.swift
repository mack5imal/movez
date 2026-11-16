import XCTest
@testable import movez

final class ClockTests: XCTestCase {
    func testManualClockAdvancesExactly() {
        let clock = ManualClock()
        let start = clock.now
        clock.advance(90)
        XCTAssertEqual(clock.now.timeIntervalSince(start), 90)
    }

    func testSystemClockRunsFastAtScale() {
        let clock = SystemClock(timeScale: 60)
        let start = clock.now
        Thread.sleep(forTimeInterval: 0.5)
        let elapsed = clock.now.timeIntervalSince(start)
        // 60x: half a second of real time is half a minute of scheduler time, so a 55-minute
        // interval elapses in 55 seconds at the desk.
        XCTAssertGreaterThanOrEqual(elapsed, 28, "0.5 s at 60x should be at least 28 scaled seconds")
        XCTAssertLessThan(elapsed, 120, "and nowhere near two scaled minutes")
    }

    func testChangingScaleDoesNotJumpTime() {
        let clock = SystemClock(timeScale: 60)
        Thread.sleep(forTimeInterval: 0.1)
        let before = clock.now
        clock.timeScale = 1
        let after = clock.now
        XCTAssertGreaterThanOrEqual(after, before)
        XCTAssertLessThan(after.timeIntervalSince(before), 1, "rebasing is continuous")
    }

    /// The scheduler is a function of the clock it is handed, so an hour simulated in 2 s ticks
    /// always replays the same way. Whether the real aggregator's poll spacing at 60× disturbs
    /// that is a separate question, tested beside the aggregator.
    func testAnHourOfTicksReplaysTheSameTransitions() {
        let harness = SchedulerHarness()
        var elapsed: TimeInterval = 0
        while elapsed < 60 * 60 {
            harness.clock.advance(2)
            elapsed += 2
            harness.send(.tick)
            if harness.state.isPendingFull { harness.send(.input(lastEventAgeSeconds: 12)) }
            if harness.state.isFullBreak {
                harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))
            }
        }
        XCTAssertEqual(
            harness.snapshot.transitions.transitions.prefix(4).map(\.to.name),
            ["micro_count_in", "micro_running", "sitting", "pending_full"]
        )
    }
}
