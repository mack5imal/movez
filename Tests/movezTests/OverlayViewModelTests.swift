import XCTest
@testable import movez

@MainActor
final class OverlayViewModelTests: XCTestCase {
    private let library = RoutineTestSupport.library

    /// A four-block routine whose second block is per-side — the shape the handoff draws.
    private func fixtureRoutine() -> Routine {
        let ids = ["CIR-02", "FLX-01", "STR-04", "BRE-01"]
        let blocks = ids.compactMap { id -> RoutineBlock? in
            guard let movement = library.movement(id: id) else { return nil }
            return RoutineBlock(movement: movement, seconds: 60)
        }
        return Routine(id: UUID(), blocks: blocks)
    }

    private func makeViewModel(
        clock: ManualClock = ManualClock(now: SchedulerHarness.mondayMorning),
        chimes: RecordingChimePlayer? = nil,
        reduceMotion: Bool = false
    ) -> OverlayViewModel {
        OverlayViewModel(
            routine: fixtureRoutine(),
            startedAt: clock.now,
            clock: clock,
            chimes: chimes ?? RecordingChimePlayer(),
            snoozesLeft: 2,
            skipsToday: 1,
            streak: 4,
            nextBreakAt: clock.now.addingTimeInterval(3600),
            reduceMotion: reduceMotion
        )
    }

    func testFixtureRoutineHasExactlyOnePerSideBlock() {
        let routine = fixtureRoutine()
        XCTAssertEqual(routine.blocks.count, 4)
        XCTAssertTrue(routine.blocks[1].perSide, "FLX-01 is a per-side movement")
        XCTAssertEqual(routine.blocks.filter(\.perSide).count, 1, "the handoff's shape: one /side block")
    }

    // MARK: - Progression

    func testNextAdvancesAndRecordsTheBlock() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var recorded: [String] = []
        viewModel.onBlockCompleted = { block, _ in recorded.append(block.movement.id) }

        XCTAssertEqual(viewModel.blockIndex, 0)
        viewModel.next()
        XCTAssertEqual(viewModel.blockIndex, 1)
        XCTAssertEqual(viewModel.completedBlocks, 1)
        XCTAssertEqual(recorded, ["CIR-02"])
        XCTAssertEqual(viewModel.state.strip[0].state, .done)
        XCTAssertEqual(viewModel.state.strip[1].state, .current)
    }

    func testThereIsNoWayBack() throws {
        let viewModel = makeViewModel()
        viewModel.next()
        XCTAssertEqual(viewModel.blockIndex, 1)

        // The design is explicit that the overlay has no Back control. The only "Back" string in
        // the view is the end state's "Back to work" button.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/movez/UI/Overlay/OverlayView.swift"),
            encoding: .utf8
        )
        let backMentions = source.components(separatedBy: "Back").count - 1
        XCTAssertEqual(backMentions, 0, "OverlayView should not mention Back at all")
    }

    func testTheLastBlockEndsTheBreak() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        var finished: (completed: Int, total: Int)?
        viewModel.onFinished = { completed, total in finished = (completed, total) }

        for _ in 0..<4 {
            clock.advance(60)
            viewModel.next()
        }
        XCTAssertEqual(viewModel.phase, .complete)
        XCTAssertEqual(finished?.completed, 4)
        XCTAssertEqual(finished?.total, 4)
        XCTAssertEqual(viewModel.state.strip.allSatisfy { $0.state == .done }, true)
    }

    func testTicksAdvanceWhenABlockRunsOut() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        clock.advance(5 + 30)
        viewModel.tick()
        XCTAssertEqual(viewModel.blockIndex, 0)
        XCTAssertEqual(viewModel.state.discNumerals, "0:30")

        clock.advance(30)
        viewModel.tick()
        XCTAssertEqual(viewModel.blockIndex, 1, "the block ran out")
    }

    // MARK: - Lead-in

    /// Every movement, the first included, opens with five seconds to read it before its clock
    /// starts, on a hollow disc counting down with a minus.
    func testEveryMovementOpensWithAFiveSecondLeadIn() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)

        XCTAssertTrue(viewModel.isLeadIn)
        XCTAssertEqual(viewModel.state.discNumerals, "−0:05")
        XCTAssertEqual(viewModel.state.discMode, .leadIn)
        XCTAssertEqual(viewModel.state.discLabel, "GET READY")
        XCTAssertEqual(viewModel.state.movementName, "March in place", "the movement is on screen to read")

        clock.advance(4)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discNumerals, "−0:01")

        clock.advance(1)
        viewModel.tick()
        XCTAssertFalse(viewModel.isLeadIn)
        XCTAssertEqual(viewModel.state.discNumerals, "1:00", "the movement's own minute starts whole")
        XCTAssertEqual(viewModel.state.discMode, .full)
        XCTAssertEqual(viewModel.state.discLabel, "NEXT →")

        viewModel.next()
        XCTAssertTrue(viewModel.isLeadIn, "the next movement opens with its own lead-in")
        XCTAssertEqual(viewModel.state.discNumerals, "−0:05")
        XCTAssertEqual(viewModel.state.discMode, .leadIn, "a per-side block's lead-in is not split")
    }

    func testNextDuringALeadInGoesToTheNextMovement() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        clock.advance(2)
        viewModel.next()
        XCTAssertEqual(viewModel.blockIndex, 1)
        XCTAssertEqual(viewModel.completedBlocks, 1, "as Next always has, it counts the movement")
    }

    func testTheBreakIsFiveMovementsAndFiveLeadIns() {
        let routine = RoutineTestSupport.routine(seed: 1)
        XCTAssertEqual(routine.totalSeconds, 5 * (60 + 5))
        XCTAssertEqual(SchedulerConfig().breakSeconds, routine.totalSeconds, "the scheduler's break is the routine's length")

        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = OverlayViewModel(routine: routine, startedAt: clock.now, clock: clock)
        XCTAssertEqual(viewModel.state.headerTrailing, "5:25 LEFT")
    }

    // MARK: - Per-side blocks

    func testSideSwitchesAtTheHalfwayChime() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        viewModel.next()
        chimes.clear()

        XCTAssertEqual(viewModel.side, .left)
        XCTAssertEqual(viewModel.state.strip[1].sideIndex, 0, "the strip rule is half filled")
        clock.advance(5)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discLabel, "THEN RIGHT")
        XCTAssertEqual(viewModel.state.discMode, .halfShare(sideIndex: 0))

        clock.advance(29)
        viewModel.tick()
        XCTAssertEqual(viewModel.side, .left)
        XCTAssertEqual(chimes.count(of: .transition), 0)

        clock.advance(1)
        viewModel.tick()
        XCTAssertEqual(viewModel.side, .right)
        XCTAssertEqual(chimes.count(of: .transition), 1, "the halfway chime")
        XCTAssertEqual(viewModel.state.discLabel, "NEXT →")
        XCTAssertEqual(viewModel.state.discMode, .halfShare(sideIndex: 1))
        XCTAssertEqual(viewModel.state.strip[1].sideIndex, 1)
    }

    func testTheRingShowsOnlyTheHalfsShare() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        viewModel.next()

        clock.advance(5 + 15)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discProgress, 0.5, accuracy: 0.02, "half of the left half")

        clock.advance(30)
        viewModel.tick()
        XCTAssertEqual(viewModel.side, .right)
        XCTAssertEqual(viewModel.state.discProgress, 0.5, accuracy: 0.05, "half of the right half")
    }

    // MARK: - The instruction

    func testTheInstructionIsAlwaysOnScreen() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        for _ in 0..<viewModel.totalBlocks {
            XCTAssertEqual(viewModel.state.instruction, viewModel.block?.movement.instructions)
            XCTAssertFalse(viewModel.state.instruction.isEmpty)
            viewModel.next()
        }
    }

    // MARK: - Snooze, done and skip

    func testSnoozeBecomesDoneHalfwayThrough() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var snoozed = 0
        viewModel.onSnooze = { snoozed += 1 }

        XCTAssertTrue(viewModel.state.snoozeAvailable)
        XCTAssertFalse(viewModel.state.doneAvailable)
        clock.advance(4)
        viewModel.snooze()
        XCTAssertEqual(snoozed, 1)

        // Two of four blocks is half the break.
        viewModel.next()
        viewModel.next()
        XCTAssertTrue(viewModel.state.doneAvailable)
        XCTAssertFalse(viewModel.state.snoozeAvailable, "Done replaces Snooze once the break counts")

        viewModel.snooze()
        XCTAssertEqual(snoozed, 1, "snoozing is refused once Done is offered")
    }

    func testSkipIsInertForThreeSeconds() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var skipped = 0
        viewModel.onSkip = { skipped += 1 }

        XCTAssertFalse(viewModel.state.skipEnabled)
        viewModel.skip()
        XCTAssertEqual(skipped, 0)

        clock.advance(3)
        viewModel.refresh()
        XCTAssertTrue(viewModel.state.skipEnabled)
        viewModel.skip()
        XCTAssertEqual(skipped, 1)
        XCTAssertEqual(viewModel.state.skipLabel, "Skip · 1 today")
    }

    func testDoneIsRefusedUntilTheBreakCounts() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var finished = 0
        viewModel.onFinished = { _, _ in finished += 1 }

        viewModel.done()
        XCTAssertEqual(finished, 0)
        XCTAssertEqual(viewModel.phase, .running)

        viewModel.next()
        viewModel.next()
        viewModel.done()
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(viewModel.phase, .complete)
    }

    func testHalfTheTimeAlsoCounts() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        XCTAssertFalse(viewModel.doneAvailable)
        clock.advance(TimeInterval(SchedulerConfig().completionSeconds))
        viewModel.refresh()
        XCTAssertTrue(viewModel.doneAvailable, "half the planned time counts even with no blocks done")
    }

    /// The overlay's Done gate and the scheduler's completion rule have to be the same rule. When
    /// they were not, a routine shorter than the configured break let the user press Done and be
    /// recorded as having skipped.
    func testDoneIsNeverOfferedBeforeTheSchedulerWouldAcceptIt() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        let config = SchedulerConfig()

        for elapsed in stride(from: 0, through: config.breakSeconds, by: 10) {
            clock.set(SchedulerHarness.mondayMorning.addingTimeInterval(TimeInterval(elapsed)))
            viewModel.refresh()
            let schedulerWouldAccept = Scheduler.meetsCompletionRule(
                completed: viewModel.completedBlocks,
                total: viewModel.totalBlocks,
                elapsed: elapsed,
                config: config
            )
            XCTAssertEqual(viewModel.doneAvailable, schedulerWouldAccept, "at \(elapsed) s")
        }
    }

    // MARK: - End state

    func testEndStateCopy() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = OverlayViewModel(
            routine: fixtureRoutine(),
            startedAt: clock.now,
            clock: clock,
            streak: 4,
            nextBreakAt: clock.now.addingTimeInterval(3 * 3600 + 5 * 60)
        )
        for _ in 0..<4 { viewModel.next() }

        XCTAssertEqual(viewModel.state.phase, .complete)
        XCTAssertEqual(viewModel.state.eyebrow, "MOVEMENT BREAK · COMPLETE")
        XCTAssertEqual(viewModel.state.headerTrailing, "NEXT BREAK 12:05")
        XCTAssertEqual(viewModel.state.completionTitle, "Break done")
        XCTAssertEqual(viewModel.state.endSummary, "Four movements done. Next break at 12:05.")
        XCTAssertEqual(viewModel.state.streak, 4)
    }

    func testStreakChipIsSingularForOne() {
        XCTAssertEqual(OverlayState.numberWord(3), "Three")
        XCTAssertEqual(OverlayState.numberWord(5), "Five")
        XCTAssertEqual(OverlayState.clock(252), "4:12")
        XCTAssertEqual(OverlayState.clock(42), "0:42")
        XCTAssertEqual(OverlayState.clock(-5), "0:00")
    }

    // MARK: - Chimes

    func testChimesForAWholeBreak() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)

        // Run the break in real time, lead-ins and all, so the per-side halfway chime fires too.
        for _ in 0..<(4 * (5 + 60)) {
            clock.advance(1)
            viewModel.tick()
        }

        XCTAssertEqual(viewModel.phase, .complete)
        XCTAssertEqual(chimes.count(of: .transition), 4, "three movements appearing plus one halfway")
        XCTAssertEqual(chimes.count(of: .completion), 1)
    }

    func testNoChimesWhenSoundsAreOff() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        chimes.enabled = false
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        for _ in 0..<4 { viewModel.next() }
        XCTAssertTrue(chimes.played.isEmpty)
    }

    func testTheRealPlayerLoadsAllThreeChimes() {
        let player = AudioChimePlayer()
        XCTAssertEqual(player.loadedChimes, Chime.allCases.count)
    }

    // MARK: - Reduce Motion

    func testReduceMotionTurnsAnimationsOff() {
        XCTAssertTrue(makeViewModel().animationsEnabled)
        XCTAssertFalse(makeViewModel(reduceMotion: true).animationsEnabled)
    }

    // MARK: - Strip naming

    func testPerSideBlocksAreAbbreviatedInTheStrip() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.state.strip[0].name, "March in place")
        XCTAssertEqual(viewModel.state.strip[1].name, "Hip flexor /side")
    }
}
