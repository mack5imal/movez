import XCTest
@testable import movez

/// A break deferred for a call belongs to the countdown it was deferred from. Once that countdown
/// starts again (a reset absence, a skip, a finished break) the deferral is spent, and must not
/// relabel the next break or make a later call end in an early one.
final class SchedulerDeferralTests: XCTestCase {
    private let minute: TimeInterval = 60
    private let call = SignalSnapshot(microphoneActive: true)
    private let quiet = SignalSnapshot()

    private func harness() -> SchedulerHarness {
        var config = SchedulerConfig()
        config.microEnabled = false
        return SchedulerHarness(config: config)
    }

    /// A break comes due during a call at 09:55; the call ends at 09:57, and the lid closes in
    /// the grace before the break is served. Back twenty minutes later, the countdown resets.
    private func deferThenResetByAnAbsence(_ harness: SchedulerHarness) {
        harness.run(seconds: 50 * minute)
        harness.send(.signals(call))
        harness.run(seconds: 7 * minute)
        XCTAssertNotNil(harness.snapshot.deferredFullDueAt, "the break came due during the call")

        harness.send(.signals(quiet))
        harness.run(seconds: 30)
        harness.send(.sleep)
        harness.clock.advance(20 * minute)
        harness.send(.wake(gapSeconds: 20 * 60))
        harness.run(seconds: 70)
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
        XCTAssertDate(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute), accuracy: 70,
                      "the absence reset the countdown")
    }

    func testAResetCountdownSpendsTheDeferral() {
        let harness = harness()
        deferThenResetByAnAbsence(harness)
        XCTAssertNil(harness.snapshot.deferredFullDueAt)
        XCTAssertNil(harness.snapshot.deferredReason)
    }

    func testALaterCallDoesNotEndInAnEarlyBreak() {
        let harness = harness()
        deferThenResetByAnAbsence(harness)

        harness.run(seconds: 20 * minute)
        harness.send(.signals(call))
        harness.run(seconds: 5 * minute)
        harness.send(.signals(quiet))
        harness.run(seconds: 3 * minute)

        XCTAssertTrue(harness.state.isSitting, "nothing was due when this call ended, got \(harness.state)")
    }

    func testTheNextBreakIsNotLabelledAsWaitingForACall() {
        let harness = harness()
        deferThenResetByAnAbsence(harness)

        harness.run(until: { $0.isPendingFull }, limit: 60 * minute)
        harness.send(.input(lastEventAgeSeconds: 12))
        guard case .headsUp(_, let deferredSince) = harness.state else {
            return XCTFail("expected the heads-up, got \(harness.state)")
        }
        XCTAssertNil(deferredSince, "a fresh break never waited for a call")
        XCTAssertNil(harness.snapshot.snoozeAllowanceThisBreak, "and keeps its full two snoozes")
    }
}
