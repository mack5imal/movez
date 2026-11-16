import XCTest
@testable import movez

/// "Longest sitting bout" on a day of skipped breaks. A skip leaves the bout running, and the
/// bout was measured only when it ended, so a morning of skips read "0 m" on exactly the day the
/// number mattered most (APP-5).
@MainActor
final class LongestBoutTests: XCTestCase {
    /// Sits from 9:00, skipping every heads-up, for three hours.
    private func skipAllMorning(_ harness: CoordinatorHarness) {
        let end = harness.now.addingTimeInterval(3 * 3600)
        while harness.now < end {
            guard harness.run(until: { if case .headsUp = $0 { return true } else { return false } },
                              limit: end.timeIntervalSince(harness.now)) else { return }
            harness.run(seconds: 4)
            harness.coordinator.inject(.userSkip)
        }
    }

    func testADayOfSkipsRecordsTheBoutThatIsStillRunning() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let start = harness.now
        skipAllMorning(harness)

        let longest = harness.history.stats(on: harness.now).longestBoutSeconds
        XCTAssertGreaterThanOrEqual(longest, 2 * 3600, "three skips into a bout that began at 9:00")
        XCTAssertLessThanOrEqual(longest, Int(harness.now.timeIntervalSince(start)))
    }

    /// The menu counts the bout in progress, so it is right between skips as well.
    func testTheMenuIncludesTheBoutInProgress() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        harness.run(seconds: 30 * 60)
        let menu = MenuBarViewModel(coordinator: harness.coordinator)
        XCTAssertEqual(menu.state.longestBout, "Longest sitting bout 30 m")
    }
}
