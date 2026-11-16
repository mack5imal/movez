import XCTest
@testable import movez

/// The Focus filter's request is held and re-applied until the scheduler can take it, rather than
/// fired once as an event that a full break, a missing coordinator or a relaunch could lose
/// (APP-1, DECISIONS 88).
@MainActor
final class FocusFilterStateTests: XCTestCase {
    override func tearDown() {
        FocusFilterRequest.latest = nil
        super.tearDown()
    }

    private func harness() -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn)
    }

    private func isFocusPaused(_ harness: CoordinatorHarness) -> Bool {
        harness.state == .paused(until: nil) && harness.scheduler.snapshot.pauseIsFocusInitiated
    }

    /// (b) A Focus that turns on during a full break pauses breaks once the break is over.
    func testAFocusThatStartsDuringAFullBreakPausesWhenTheBreakEnds() {
        let harness = harness()
        harness.coordinator.takeBreakNow()
        harness.coordinator.focusFilter(paused: true)
        XCTAssertEqual(harness.state.name, "full_break", "a break on screen is not cut short")

        harness.completeBreak()
        harness.run(seconds: 4)
        XCTAssertTrue(isFocusPaused(harness), "got \(harness.state)")
    }

    /// (a) A Focus that turned on before there was a coordinator (the notice not yet accepted,
    /// or the login item still starting) is applied when it starts.
    func testARequestThatArrivedBeforeTheCoordinatorIsAppliedAtStart() {
        FocusFilterRequest.latest = true
        let harness = harness()
        harness.coordinator.start()
        defer { harness.coordinator.stop() }
        XCTAssertTrue(isFocusPaused(harness), "got \(harness.state)")
    }

    /// (c) A Focus pause restored from the state file, after a Focus that ended while Movez was
    /// not running, is lifted when macOS says no Focus is on.
    func testARestoredFocusPauseIsLiftedWhenMacOSSaysTheFocusEnded() {
        let harness = harness()
        harness.coordinator.focusFilter(paused: true)
        XCTAssertTrue(isFocusPaused(harness))
        harness.coordinator.deliver([.persist])

        harness.relaunch()
        let read = expectation(description: "current Focus read")
        harness.coordinator.readCurrentFocus = {
            read.fulfill()
            return false
        }
        harness.coordinator.start()
        defer { harness.coordinator.stop() }
        wait(for: [read], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(harness.coordinator.scheduler.state.name, "sitting")
    }

    /// Held is not stubborn: once the pause has been applied, "Resume now" wins until the Focus
    /// changes again.
    func testResumingByHandDuringAFocusIsNotUndone() {
        let harness = harness()
        harness.coordinator.focusFilter(paused: true)
        XCTAssertTrue(isFocusPaused(harness))

        harness.coordinator.resume()
        harness.run(seconds: 120)
        XCTAssertEqual(harness.state.name, "sitting")
    }

    func testTheFocusEndingStillResumes() {
        let harness = harness()
        harness.coordinator.focusFilter(paused: true)
        harness.coordinator.focusFilter(paused: false)
        XCTAssertEqual(harness.state.name, "sitting")
    }
}
