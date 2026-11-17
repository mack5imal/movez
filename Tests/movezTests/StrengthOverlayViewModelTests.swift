import XCTest
@testable import movez

/// What the strength overlay draws at each moment of a break, driven by a `ManualClock`.
@MainActor
final class StrengthOverlayViewModelTests: XCTestCase {
    private func makeViewModel(
        clock: ManualClock,
        chimes: RecordingChimePlayer? = nil,
        thirdSet: String = "COR-05",
        reduceMotion: Bool = false
    ) -> StrengthOverlayViewModel {
        StrengthOverlayViewModel(
            strengthBreak: StrengthTimelineFixture.strengthBreak(thirdSet: thirdSet),
            startedAt: clock.now,
            clock: clock,
            chimes: chimes ?? RecordingChimePlayer(),
            snoozesLeft: 2,
            skipsToday: 1,
            reduceMotion: reduceMotion
        )
    }

    /// Ticks one second at a time until the overlay shows a segment of `kind`.
    private func run(_ viewModel: StrengthOverlayViewModel, clock: ManualClock, until kind: StrengthSessionTimeline.Kind) {
        var ticks = 0
        while viewModel.state.segment != kind, ticks < 1_000 {
            clock.advance(1)
            viewModel.tick()
            ticks += 1
        }
    }

    private func name(_ id: String) -> String { StrengthTestSupport.movement(id).name }

    // MARK: - Each segment

    func testTheLeadInShowsTheWarmUp() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let state = makeViewModel(clock: clock).state

        XCTAssertEqual(state.eyebrow, "STRENGTH BREAK")
        XCTAssertEqual(state.segment, .leadIn)
        XCTAssertEqual(state.kicker, "Warm-up")
        XCTAssertEqual(state.movementName, name("SQT-02"))
        XCTAssertEqual(state.dose, "", "the warm-up has no rep target")
        XCTAssertNil(state.pacer)
        XCTAssertEqual(state.discNumerals, "−0:05")
        XCTAssertEqual(state.discLabel, "GET READY")
        XCTAssertEqual(state.discMode, .leadIn)
        XCTAssertEqual(state.headerTrailing, "5:34 LEFT")
        XCTAssertEqual(state.strip.map(\.title), ["Warm-up", "Set 1", "Set 2", "Set 3", "Cool-down"])
        XCTAssertEqual(
            state.strip.map(\.name), ["SQT-02", "PSH-04", "SQT-06", "COR-05", "END-01"].map(name),
            "each column names its move under the label, with no /side"
        )
        XCTAssertEqual(state.strip.map(\.state), [.current, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    func testTheWarmUpRunsWithNext() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .warmUp)
        XCTAssertEqual(viewModel.state.kicker, "Warm-up")
        XCTAssertEqual(viewModel.state.discNumerals, "0:30")
        XCTAssertEqual(viewModel.state.discLabel, "NEXT →")
        XCTAssertEqual(viewModel.state.discMode, .full)
    }

    func testTheLeadInBeforeSetOneShowsItsEmptyMeter() throws {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .warmUp)
        run(viewModel, clock: clock, until: .leadIn)

        let state = viewModel.state
        XCTAssertEqual(state.kicker, "Set 1 of 3")
        XCTAssertEqual(state.movementName, name("PSH-04"))
        XCTAssertEqual(state.dose, "12 reps")
        let pacer = try XCTUnwrap(state.pacer)
        XCTAssertEqual(pacer.direction, .up)
        XCTAssertEqual(pacer.level, .smooth(0))
        XCTAssertEqual(state.counter, "Rep 1 of 12")
        XCTAssertEqual(state.discLabel, "GET READY")
        XCTAssertEqual(state.strip[1].state, .current)
    }

    func testASetShowsItsKickerDoseMeterAndDone() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(1))
        clock.advance(7)
        viewModel.tick()

        let state = viewModel.state
        XCTAssertEqual(state.kicker, "Set 1 of 3")
        XCTAssertEqual(state.dose, "12 reps")
        XCTAssertNil(state.doseModifier)
        XCTAssertEqual(state.counter, "Rep 3 of 12")
        XCTAssertEqual(state.discLabel, "DONE")
        XCTAssertEqual(state.discMode, .full)
        XCTAssertEqual(state.discNumerals, "0:34")
        XCTAssertEqual(state.instruction, StrengthTestSupport.movement("PSH-04").instructions)
    }

    func testTheRestShowsWhatIsNext() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .rest(beforeSet: 2))
        clock.advance(13)
        viewModel.tick()

        let state = viewModel.state
        XCTAssertEqual(state.headline, "Rest")
        XCTAssertEqual(state.upNext, "Up next: \(name("SQT-06")) · 10 each side")
        XCTAssertEqual(state.kicker, "Set 2 of 3")
        XCTAssertEqual(state.instruction, StrengthTestSupport.movement("SQT-06").instructions)
        XCTAssertNil(state.pacer, "a rest has no meter")
        XCTAssertEqual(state.discMode, .leadIn)
        XCTAssertEqual(state.discLabel, "REST")
        XCTAssertEqual(state.discNumerals, "−0:32")
        XCTAssertEqual(state.strip.map(\.state), [.done, .done, .current, .upcoming, .upcoming],
                       "the next set's column is current during its rest")
        XCTAssertEqual(state.strip[2].sideIndex, 0)
    }

    func testAPerSideSetSwitchesSides() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(2))
        XCTAssertEqual(viewModel.state.dose, "10 each side")
        XCTAssertEqual(viewModel.state.side, .left)
        XCTAssertTrue(viewModel.state.isSideBlock)

        clock.advance(31)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.counter, "Switch sides")
        XCTAssertEqual(viewModel.state.side, .right)
        XCTAssertEqual(viewModel.state.strip[2].sideIndex, 1)
        clock.advance(2)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.counter, "Rep 1 of 10")
    }

    func testADoseWithModifiersShowsThemOnTheirOwnLine() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(3))
        XCTAssertEqual(viewModel.state.dose, "12 reps")
        XCTAssertEqual(viewModel.state.doseModifier, "Alternating · 2 s hold")
        clock.advance(1.5)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.pacer?.direction, .hold)
    }

    func testThePerSideCoolDownShowsTheHalfThenNext() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .coolDown)
        XCTAssertEqual(viewModel.state.kicker, "Cool-down")
        XCTAssertEqual(viewModel.state.dose, "25 s each side")
        XCTAssertEqual(viewModel.state.discLabel, "THEN RIGHT")
        XCTAssertEqual(viewModel.state.discMode, .halfShare(sideIndex: 0))
        clock.advance(16)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discLabel, "NEXT →")
        XCTAssertEqual(viewModel.state.discMode, .halfShare(sideIndex: 1))
    }

    // MARK: - Done, pause and the end

    func testDoneMidSetStartsTheRestWithOneChime() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        run(viewModel, clock: clock, until: .set(1))
        clock.advance(4)
        viewModel.tick()

        viewModel.done()
        viewModel.done()
        XCTAssertEqual(viewModel.state.segment, .rest(beforeSet: 2))
        XCTAssertEqual(viewModel.state.discNumerals, "−0:45")
        XCTAssertEqual(chimes.played, [.transition], "one set-end chime for two presses")
    }

    func testPauseFreezesTheMeterAndEveryClock() throws {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(1))
        // A quarter-second step keeps every time exact, so frozen values compare equal.
        clock.advance(7.25)
        viewModel.tick()
        let before = viewModel.state
        let beforePacer = try XCTUnwrap(before.pacer)

        viewModel.togglePause()
        for _ in 0..<60 {
            clock.advance(1)
            viewModel.tick()
        }
        let paused = viewModel.state
        let pausedPacer = try XCTUnwrap(paused.pacer)
        XCTAssertEqual(pausedPacer.rep, beforePacer.rep)
        XCTAssertEqual(pausedPacer.phase, beforePacer.phase)
        XCTAssertEqual(pausedPacer.level, beforePacer.level)
        XCTAssertEqual(pausedPacer.direction, .paused)
        XCTAssertEqual(paused.counter, before.counter)
        XCTAssertEqual(paused.discNumerals, before.discNumerals)
        XCTAssertEqual(paused.discProgress, before.discProgress)
        XCTAssertEqual(paused.discLabel, "PAUSED")
        XCTAssertEqual(paused.headerTrailing, "PAUSED · ENDS IN 4:00")
        XCTAssertTrue(paused.isPaused)

        viewModel.togglePause()
        XCTAssertEqual(viewModel.state.pacer, beforePacer, "resume picks up from the same values")
        XCTAssertEqual(viewModel.state.headerTrailing, before.headerTrailing)
        clock.advance(1.5)
        viewModel.tick()
        let meter = try XCTUnwrap(viewModel.timeline.current?.pacer)
        XCTAssertEqual(viewModel.state.pacer, meter.state(at: 7.25 + 1.5))
    }

    /// The only chimes are the set ends, the side switches and the completion chime as the break
    /// closes; the meter never sounds a rep.
    func testNoChimePerRepOnlySetEndsAndSideSwitches() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = makeViewModel(clock: clock, chimes: chimes)
        var finished: [Int] = []
        viewModel.onFinished = { finished = [$0, $1, $2] }
        var counters: Set<String> = []

        while !viewModel.isClosed {
            clock.advance(0.5)
            viewModel.tick()
            counters.insert(viewModel.state.counter)
        }

        XCTAssertTrue(counters.isSuperset(of: ["Rep 12 of 12", "Rep 10 of 10", "Switch sides"]),
                      "the counter moved through every rep")
        // Three set ends, the per-side set's switch and the per-side cool-down's switch, then the
        // completion chime once as the break closes.
        XCTAssertEqual(chimes.played, Array(repeating: .transition, count: 5) + [.completion])
        XCTAssertTrue(viewModel.state.isClosed, "the break closes itself; there is no end screen")
        XCTAssertEqual(finished, [5, 5, 334], "every move done, of five, over the planned 334 s")
    }

    /// The overlay sink drops the scheduler's completion chime while the overlay is up, so a
    /// break that runs to its end must play it itself, once (DECISIONS 31).
    func testABreakThatRunsToItsEndPlaysTheCompletionChimeOnce() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let strengthChimes = RecordingChimePlayer()
        let strength = makeViewModel(clock: clock, chimes: strengthChimes)
        var lastChimeAtFinish: [Chime?] = []
        strength.onFinished = { _, _, _ in lastChimeAtFinish.append(strengthChimes.played.last) }
        while !strength.isClosed {
            clock.advance(1)
            strength.tick()
        }
        strength.tick()
        XCTAssertEqual(strengthChimes.count(of: .completion), 1)
        XCTAssertEqual(strengthChimes.played.last, .completion)
        XCTAssertEqual(lastChimeAtFinish, [.completion], "the chime plays before the break ends, and it ends once")

        let endRangeChimes = RecordingChimePlayer()
        let endRange = StrengthOverlayViewModel(
            endRangeBreak: StrengthTimelineFixture.endRangeBreak(), startedAt: clock.now, clock: clock, chimes: endRangeChimes
        )
        while !endRange.isClosed {
            clock.advance(1)
            endRange.tick()
        }
        endRange.tick()
        XCTAssertEqual(endRangeChimes.count(of: .completion), 1)
        XCTAssertEqual(endRangeChimes.played.last, .completion)
    }

    /// Each finished part is reported by its index in the break's part order, so the app can
    /// record the part the overlay finished rather than its own position.
    func testEachFinishedPartIsReportedByItsIndex() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var indices: [Int] = []
        viewModel.onWorkCompleted = { indices.append($0) }
        while !viewModel.isClosed {
            clock.advance(1)
            viewModel.tick()
        }
        XCTAssertEqual(indices, [0, 1, 2, 3, 4])
    }

    func testReduceMotionGivesASteppedMeter() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock, reduceMotion: true)
        run(viewModel, clock: clock, until: .set(1))
        clock.advance(7.6)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.pacer?.level, .stepped(filled: 2))
    }

    func testASlowMoveSetHasNoMeter() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock, thirdSet: "COR-16")
        run(viewModel, clock: clock, until: .set(3))
        XCTAssertNil(viewModel.state.pacer)
        XCTAssertEqual(viewModel.state.counter, "")
        XCTAssertEqual(viewModel.state.discLabel, "DONE")
        XCTAssertEqual(viewModel.state.discNumerals, OverlayState.clock(StrengthTestSupport.movement("COR-16").blockSeconds))
    }

    // MARK: - End-range

    func testAnEndRangeBreakIsTheMovementFlowWithTheDoseLine() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let chimes = RecordingChimePlayer()
        let viewModel = StrengthOverlayViewModel(
            endRangeBreak: StrengthTimelineFixture.endRangeBreak(), startedAt: clock.now, clock: clock, chimes: chimes
        )
        XCTAssertEqual(viewModel.state.eyebrow, "STRENGTH BREAK")
        XCTAssertEqual(viewModel.state.strip.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(viewModel.state.strip[0].name, OverlayViewModel.stripName(name: name("END-01"), perSide: true))
        XCTAssertEqual(viewModel.state.kicker, "")
        XCTAssertEqual(viewModel.state.dose, "25 s each side")
        XCTAssertEqual(viewModel.state.discLabel, "GET READY")

        run(viewModel, clock: clock, until: .block(1))
        XCTAssertEqual(viewModel.state.discLabel, "THEN RIGHT")
        run(viewModel, clock: clock, until: .block(2))
        XCTAssertEqual(viewModel.state.dose, "30 s")
        XCTAssertEqual(viewModel.state.discLabel, "NEXT →")
        XCTAssertEqual(chimes.played, [.transition, .transition], "the halfway switch, then the next block")

        while !viewModel.isClosed {
            clock.advance(1)
            viewModel.tick()
        }
        XCTAssertTrue(viewModel.state.isClosed, "no end state: the overlay closes when the last block ends")
    }
}
