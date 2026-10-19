import XCTest
@testable import movez

/// macOS performs a Focus filter with its default values whenever no Focus is on, once after
/// every boot and each time a Focus ends, so the default has to mean "breaks running".
final class FocusFilterTests: XCTestCase {
    func testTheDefaultLeavesBreaksRunning() {
        XCTAssertFalse(MovezFocusFilterIntent().pauseBreaks)
    }

    /// What the after-boot pass now sends: a filter that is off resumes nothing the user paused,
    /// and leaves a sitting scheduler sitting.
    func testTheNoFocusDefaultNeitherPausesNorUndoesAUserPause() {
        let harness = SchedulerHarness()
        harness.run(seconds: 60)
        harness.send(.focusFilter(paused: MovezFocusFilterIntent().pauseBreaks))
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")

        harness.send(.userPause(seconds: nil))
        harness.send(.focusFilter(paused: false))
        guard case .paused = harness.state else { return XCTFail("a user pause stays, got \(harness.state)") }
    }

    /// A Focus that paused breaks resumes them when it ends.
    func testAFocusEndingResumesTheBreaksItPaused() {
        let harness = SchedulerHarness()
        harness.run(seconds: 60)
        harness.send(.focusFilter(paused: true))
        guard case .paused = harness.state else { return XCTFail("expected paused, got \(harness.state)") }
        harness.send(.focusFilter(paused: MovezFocusFilterIntent().pauseBreaks))
        XCTAssertTrue(harness.state.isSitting, "got \(harness.state)")
    }
}
