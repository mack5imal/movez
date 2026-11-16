import XCTest
@testable import movez

/// A break the lid closed on, and the user came back to after it was due to end, is judged by
/// the completion rule. Whatever the verdict, it reaches history, which is what the menu's
/// Today, the strength planner and recency all read.
@MainActor
final class InterruptedBreakHistoryTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// Starts a break, lets it run for `ran` seconds and closes the lid on it.
    private func sleepDuringABreak(ran: TimeInterval) -> CoordinatorHarness {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        XCTAssertNotNil(harness.coordinator.currentBreak)
        harness.clock.advance(ran)
        harness.coordinator.inject(.sleep)
        XCTAssertNotNil(harness.coordinator.interruptedSession)
        return harness
    }

    private func wake(_ harness: CoordinatorHarness, after gap: TimeInterval) {
        harness.clock.advance(gap)
        harness.coordinator.inject(.wake(gapSeconds: Int(gap)))
        harness.run(seconds: 90)
    }

    private func outcomes(_ harness: CoordinatorHarness) -> [BreakResult] {
        harness.history.breaks(on: harness.now).map(\.outcome)
    }

    func testABreakThatAlreadyCountedIsRecordedAsDone() {
        let harness = sleepDuringABreak(ran: 3 * minute)
        wake(harness, after: 20 * minute)

        XCTAssertEqual(outcomes(harness), [.done], "three minutes of a break is past the half")
        XCTAssertEqual(harness.scheduler.snapshot.doneToday, 1)
        XCTAssertNil(harness.coordinator.interruptedSession)
    }

    func testABreakThatHadNotCountedIsRecordedAsSkippedWithAFreshAllowance() {
        let harness = sleepDuringABreak(ran: minute)
        wake(harness, after: 20 * minute)

        XCTAssertEqual(outcomes(harness), [.skipped])
        XCTAssertEqual(harness.scheduler.snapshot.skipsToday, 1)
        XCTAssertEqual(harness.scheduler.snapshot.snoozesUsedThisBreak, 0)
        XCTAssertNil(harness.scheduler.snapshot.snoozeAllowanceThisBreak, "the next break keeps both snoozes")
    }

    func testStandbyStillCreditsABreakThatHadCounted() {
        let harness = sleepDuringABreak(ran: 3 * minute)
        wake(harness, after: 2 * 3600)

        XCTAssertEqual(outcomes(harness).filter { !$0.isAbsence }, [.done])
        XCTAssertEqual(harness.scheduler.snapshot.doneToday, 1)
    }

    func testStandbyLetsGoOfABreakThatHadNotCountedWithoutASkip() {
        let harness = sleepDuringABreak(ran: minute)
        wake(harness, after: 2 * 3600)

        XCTAssertEqual(outcomes(harness).filter { !$0.isAbsence }, [], "the user left; they did not turn it down")
        XCTAssertEqual(harness.scheduler.snapshot.skipsToday, 0)
    }

    /// Back before the break was due to end, the break resumes, even though the wake is only
    /// confirmed a quiet minute later.
    func testComingBackJustBeforeThePlannedEndResumesTheBreak() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let length = TimeInterval(harness.scheduler.config.breakSeconds)
        harness.clock.advance(minute)
        harness.coordinator.inject(.sleep)
        // Asleep until thirty seconds before the end; the quiet minute then runs past it.
        let gap = length - minute - 30
        harness.clock.advance(gap)
        harness.coordinator.inject(.wake(gapSeconds: Int(gap)))
        harness.run(seconds: 70)

        XCTAssertTrue(harness.state.isFullBreak, "got \(harness.state)")
    }
}
