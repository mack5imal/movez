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

    /// The overlay names each block it finishes; the same block named twice is written once.
    func testABlockRecordedTwiceIsWrittenOnce() throws {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let routine = try XCTUnwrap(harness.coordinator.currentBreak?.routine)
        let before = harness.history.usedMovementIds(on: harness.now).count   // the morning's micro-break
        harness.coordinator.recordOverlayBlock(routine.blocks[0], index: 0)
        harness.coordinator.recordOverlayBlock(routine.blocks[0], index: 0)
        harness.coordinator.recordOverlayBlock(routine.blocks[1], index: 1)

        XCTAssertEqual(harness.coordinator.currentBreak?.completedBlocks, 2)
        XCTAssertEqual(harness.history.usedMovementIds(on: harness.now).count - before, 2)
    }

    /// The lid closed on a break, and the app was relaunched before the user came back. The
    /// kept session died with the process, so the break served on return is a new one, starting
    /// now, with nothing done.
    func testAResumeAfterARelaunchServesAFreshBreakFromNow() {
        let harness = sleepDuringABreak(ran: 2 * minute)
        harness.clock.advance(5)
        harness.relaunch()
        XCTAssertNil(harness.coordinator.interruptedSession)

        harness.clock.advance(30)
        harness.coordinator.inject(.wake(gapSeconds: 35))
        harness.coordinator.inject(.input(lastEventAgeSeconds: 0))
        _ = harness.run(until: { $0.isFullBreak }, limit: 2 * minute)

        let session = harness.coordinator.currentBreak
        XCTAssertNotNil(session, "got \(harness.state)")
        XCTAssertEqual(session?.completedBlocks, 0)
        XCTAssertDate(session?.startedAt, harness.now, accuracy: 70, "not backdated by the two minutes the old break ran")
    }
}
