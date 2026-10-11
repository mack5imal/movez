import XCTest
@testable import movez

/// The overlay's two countdowns and its pause: the break's time left and the movement's own
/// clock always agree, and a pause stops both.
@MainActor
final class OverlayTimingTests: XCTestCase {
    private let library = RoutineTestSupport.library

    /// The same four-block routine as `OverlayViewModelTests`, second block per-side.
    private func makeViewModel(
        clock: ManualClock = ManualClock(now: SchedulerHarness.mondayMorning),
        chimes: RecordingChimePlayer? = nil
    ) -> OverlayViewModel {
        let blocks = ["CIR-02", "FLX-01", "STR-04", "BRE-01"].compactMap { id -> RoutineBlock? in
            library.movement(id: id).map { RoutineBlock(movement: $0, seconds: 60) }
        }
        return OverlayViewModel(
            routine: Routine(id: UUID(), blocks: blocks),
            startedAt: clock.now,
            clock: clock,
            chimes: chimes ?? RecordingChimePlayer(),
            snoozesLeft: 2,
            skipsToday: 1,
            streak: 4,
            nextBreakAt: clock.now.addingTimeInterval(3600)
        )
    }

    // MARK: - The two countdowns

    /// The header's time left and the disc never disagree: the header is always the disc's time
    /// plus the blocks still to come, however late the ticks arrive, and both reach zero together.
    func testTheTwoCountdownsAlwaysAgree() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        let routine = viewModel.routine
        let steps: [TimeInterval] = [1.0, 1.3, 1.1, 1.4, 0.9, 1.2]
        var index = 0

        while viewModel.phase == .running {
            let block = viewModel.block!
            let later = routine.blocks.dropFirst(viewModel.blockIndex + 1).reduce(0) { $0 + 5 + $1.seconds }
            let disc = viewModel.isLeadIn ? viewModel.leadInRemaining + block.seconds : viewModel.blockRemaining
            XCTAssertEqual(viewModel.breakRemaining - later, disc, "block \(viewModel.blockIndex)")

            clock.advance(steps[index % steps.count])
            index += 1
            viewModel.tick()
        }

        let ran = clock.now.timeIntervalSince(viewModel.startedAt)
        XCTAssertEqual(viewModel.breakRemaining, 0)
        XCTAssertLessThan(ran, Double(routine.totalSeconds) + 1.5, "late ticks no longer stretch the break")
        XCTAssertGreaterThanOrEqual(ran, Double(routine.totalSeconds))
    }

    func testNextTakesTheRestOfTheBlockOffTheTimeLeft() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        XCTAssertEqual(viewModel.breakRemaining, 4 * 65)

        clock.advance(10)
        viewModel.tick()
        XCTAssertEqual(viewModel.breakRemaining, 4 * 65 - 10)

        viewModel.next()
        XCTAssertEqual(viewModel.breakRemaining, 3 * 65, "the skipped fifty-five seconds are gone")
        XCTAssertEqual(viewModel.state.headerTrailing, "3:15 LEFT")
    }

    // MARK: - Pause

    func testPausingFreezesBothCountdownsAndResumingPicksUpWhereTheyStopped() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        clock.advance(5 + 10)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discNumerals, "0:50")
        let left = viewModel.breakRemaining

        viewModel.togglePause()
        XCTAssertTrue(viewModel.state.isPaused)
        XCTAssertEqual(viewModel.state.pauseLabel, "Resume")
        XCTAssertEqual(viewModel.state.discLabel, "PAUSED")
        XCTAssertEqual(viewModel.state.headerTrailing, "PAUSED · ENDS IN 5:00")
        XCTAssertEqual(viewModel.state.instruction, viewModel.block?.movement.instructions, "the instruction stays")

        clock.advance(90)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discNumerals, "0:50", "the movement's countdown stands still")
        XCTAssertEqual(viewModel.breakRemaining, left, "and so does the break's")
        XCTAssertEqual(viewModel.state.headerTrailing, "PAUSED · ENDS IN 3:30")

        viewModel.togglePause()
        XCTAssertEqual(viewModel.state.headerTrailing, "\(OverlayState.clock(left)) LEFT")
        clock.advance(10)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discNumerals, "0:40")
        XCTAssertEqual(viewModel.breakRemaining, left - 10)
    }

    func testNothingAdvancesOrChimesWhilePaused() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        viewModel.next()                    // the per-side block
        chimes.clear()
        clock.advance(5 + 20)
        viewModel.tick()
        viewModel.togglePause()

        clock.advance(240)
        viewModel.tick()
        XCTAssertEqual(viewModel.blockIndex, 1)
        XCTAssertEqual(viewModel.side, .left, "the side switch waits")
        XCTAssertTrue(chimes.played.isEmpty, "no chime while paused")

        viewModel.next()
        XCTAssertEqual(viewModel.blockIndex, 1, "Next, the disc and → are inert while paused")
    }

    func testSnoozeSkipAndDoneStillWorkWhilePaused() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var snoozed = 0
        var skipped = 0
        viewModel.onSnooze = { snoozed += 1 }
        viewModel.onSkip = { skipped += 1 }
        clock.advance(5)
        viewModel.tick()
        viewModel.togglePause()

        viewModel.snooze()
        viewModel.skip()
        XCTAssertEqual(snoozed, 1)
        XCTAssertEqual(skipped, 1)
    }

    func testTimeSpentPausedDoesNotCountTowardDone() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        viewModel.togglePause()
        clock.advance(TimeInterval(SchedulerConfig().completionSeconds) + 30)
        viewModel.togglePause()
        XCTAssertFalse(viewModel.doneAvailable, "paused time is not break time")
        XCTAssertLessThan(viewModel.elapsedSeconds, 1)
    }

    func testFiveMinutesPausedEndsTheBreakAsSnoozed() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var expired = 0
        var finished = 0
        viewModel.onPauseExpired = { expired += 1 }
        viewModel.onFinished = { _, _, _ in finished += 1 }
        viewModel.togglePause()

        clock.advance(299)
        viewModel.tick()
        XCTAssertEqual(expired, 0)
        XCTAssertEqual(viewModel.state.headerTrailing, "PAUSED · ENDS IN 0:01")

        clock.advance(1)
        viewModel.tick()
        viewModel.tick()
        XCTAssertEqual(expired, 1, "once, however many ticks follow")
        XCTAssertEqual(finished, 0)
    }

    func testFiveMinutesPausedEndsABreakThatAlreadyCountsAsDone() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var expired = 0
        var finished: (Int, Int)?
        viewModel.onPauseExpired = { expired += 1 }
        viewModel.onFinished = { completed, total, _ in finished = (completed, total) }
        viewModel.next()
        viewModel.next()
        XCTAssertTrue(viewModel.doneAvailable)

        viewModel.togglePause()
        clock.advance(300)
        viewModel.tick()
        XCTAssertEqual(expired, 0)
        XCTAssertEqual(finished?.0, 2)
        XCTAssertEqual(viewModel.phase, .complete)
    }

    func testTheLimitIsPerPause() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var expired = 0
        viewModel.onPauseExpired = { expired += 1 }

        viewModel.togglePause()
        clock.advance(240)
        viewModel.tick()
        viewModel.togglePause()
        viewModel.togglePause()
        clock.advance(240)
        viewModel.tick()
        XCTAssertEqual(expired, 0, "eight minutes paused, but never five at once")
        XCTAssertEqual(viewModel.state.headerTrailing, "PAUSED · ENDS IN 1:00")
    }
}
