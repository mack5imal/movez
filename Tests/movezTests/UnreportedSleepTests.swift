import XCTest
@testable import movez

/// A wake can arrive with no sleep before it: a missed notification, or a gap only the poll
/// noticed. The sleep path's work still has to be done, or a break stays on screen through the
/// quiet minute and the pause-away countdown has nothing put away to hand back.
final class UnreportedSleepTests: XCTestCase {
    private let minute: TimeInterval = 60

    func testAWakeWithNoSleepTakesABreakDownAndKeepsItForTheReturn() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isPendingFull }, limit: 60 * minute)
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.clock.advance(4)
        harness.send(.userStartNow)
        harness.clock.advance(minute)

        harness.clock.advance(2 * minute)
        let effects = harness.send(.wake(gapSeconds: 120))

        XCTAssertTrue(effects.contains(.endFullBreak(.interrupted)), "the overlay comes down, got \(effects)")
        XCTAssertNotNil(harness.snapshot.interruptedBreak)
        XCTAssertEqual(harness.snapshot.interruptedBreak?.elapsedSeconds ?? -1, 60, accuracy: 2,
                       "and the break counts only the minute before the gap")
    }

    func testAWakeWithNoSleepPausesTheCountdownInPauseMode() {
        var config = SchedulerConfig()
        config.awayBehaviour = .pause
        config.microEnabled = false
        let harness = SchedulerHarness(config: config)
        harness.run(seconds: 10 * minute)
        let due = harness.snapshot.nextFullDueAt ?? .distantPast

        harness.clock.advance(5 * minute)
        harness.send(.wake(gapSeconds: 5 * 60))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, due.addingTimeInterval(5 * minute), accuracy: 4,
                      "five minutes away hold the countdown for five minutes")
    }

    func testALatePollWithABreakOnScreenLeavesTheBreak() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isPendingFull }, limit: 60 * minute)
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.clock.advance(4)
        harness.send(.userStartNow)
        harness.clock.advance(15)

        XCTAssertEqual(harness.send(.gapDetected(seconds: 15)), [])
        XCTAssertTrue(harness.state.isFullBreak)
    }

    func testALatePollInsideTheQuietMinuteDoesNotExtendIt() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        harness.send(.sleep)
        harness.clock.advance(10 * minute)
        harness.send(.wake(gapSeconds: 600))
        guard case .postBreakGrace(let until, _) = harness.state else {
            return XCTFail("expected the quiet minute, got \(harness.state)")
        }

        harness.clock.advance(15)
        XCTAssertEqual(harness.send(.gapDetected(seconds: 15)), [])
        guard case .postBreakGrace(let after, _) = harness.state else {
            return XCTFail("expected the quiet minute, got \(harness.state)")
        }
        XCTAssertEqual(after, until)
    }
}
