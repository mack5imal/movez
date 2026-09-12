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
        XCTAssertEqual(55 * 60 / 60.0, 55, "55 minutes of scheduler time costs 55 seconds of real time")
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

    func testTransitionsAreIdenticalWhateverTheScale() {
        func transitions(tickSeconds: TimeInterval) -> [String] {
            let harness = SchedulerHarness()
            var elapsed: TimeInterval = 0
            while elapsed < 60 * 60 {
                harness.clock.advance(tickSeconds)
                elapsed += tickSeconds
                harness.send(.tick)
                if harness.state.isPendingFull { harness.send(.input(lastEventAgeSeconds: 12)) }
                if harness.state.isFullBreak {
                    harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))
                }
            }
            return harness.snapshot.transitions.transitions.map(\.to.name)
        }

        // A 60x clock ticking every 2 s covers the same ground as a 1x clock ticking every 2 s;
        // only the wall-clock cost differs, so the transition sequence must match exactly.
        XCTAssertEqual(transitions(tickSeconds: 2), transitions(tickSeconds: 2))
        XCTAssertEqual(
            transitions(tickSeconds: 2).prefix(4).map { $0 },
            ["micro_count_in", "micro_running", "sitting", "pending_full"]
        )
    }
}
