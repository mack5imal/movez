import XCTest
@testable import movez

/// A strength break and an end-range break built by hand from the bundled library, so each test
/// knows every set's dose and length.
enum StrengthTimelineFixture {
    /// Warm-up, then a two-sided rep set ("12 reps"), a per-side rep set ("10/side"), a set with a
    /// hold ("12 reps, alternating, 2 s hold"), then a per-side cool-down.
    static func strengthBreak(thirdSet: String = "COR-05") -> StrengthBreak {
        StrengthBreak(
            id: UUID(),
            letter: .dayA,
            warmUp: StrengthBlock(movement: StrengthTestSupport.movement("SQT-02"), seconds: StrengthTiming.warmUpSeconds),
            sets: [
                StrengthSet(movement: StrengthTestSupport.movement("PSH-04"), setNumber: 1),
                StrengthSet(movement: StrengthTestSupport.movement("SQT-06"), setNumber: 2),
                StrengthSet(movement: StrengthTestSupport.movement(thirdSet), setNumber: 3)
            ],
            coolDown: StrengthBlock(
                movement: StrengthTestSupport.movement("END-01"), seconds: StrengthTiming.coolDownSeconds
            ),
            relaxed: []
        )
    }

    /// Four end-range blocks, the first per-side.
    static func endRangeBreak() -> EndRangeBreak {
        EndRangeBreak(
            id: UUID(),
            blocks: ["END-01", "END-07", "END-02", "END-13"].map {
                StrengthBlock(movement: StrengthTestSupport.movement($0), seconds: StrengthTiming.endRangeBlockSeconds)
            },
            relaxed: []
        )
    }
}

/// The strength break's timeline: the order and length of every segment, and what Done, pause
/// and late ticks do to it.
@MainActor
final class StrengthTimelineTests: XCTestCase {
    private func makeTimeline(clock: ManualClock) -> StrengthSessionTimeline {
        StrengthSessionTimeline(strengthBreak: StrengthTimelineFixture.strengthBreak(), startedAt: clock.now)
    }

    /// Advances the clock in one-second ticks until the timeline is on a segment of `kind`.
    private func run(
        _ timeline: inout StrengthSessionTimeline,
        clock: ManualClock,
        until kind: StrengthSessionTimeline.Kind
    ) {
        var guardTicks = 0
        while timeline.current?.kind != kind, guardTicks < 1_000 {
            clock.advance(1)
            _ = timeline.update(at: clock.now)
            guardTicks += 1
        }
    }

    // MARK: - The sequence

    /// Lead-in → warm-up → lead-in → set 1 → rest 45 s → set 2 → rest 45 s → set 3 → cool-down →
    /// closed, with each set as long as its dose: reps × 3 s + 5 s, plus 3 s and both sides on a
    /// per-side set, and (3 + hold) s a rep with a hold.
    func testTheBreakRunsInOrderWithEachSetAsLongAsItsDose() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        var seen: [(kind: StrengthSessionTimeline.Kind, at: TimeInterval)] = [(timeline.current!.kind, 0)]

        while !timeline.isClosed {
            clock.advance(0.5)
            for event in timeline.update(at: clock.now) {
                if case let .started(kind) = event { seen.append((kind, timeline.segmentStart)) }
            }
        }

        XCTAssertEqual(seen.map(\.kind), [
            .leadIn, .warmUp, .leadIn, .set(1), .rest(beforeSet: 2), .set(2), .rest(beforeSet: 3), .set(3), .coolDown
        ])
        let starts = seen.map(\.at) + [TimeInterval(timeline.totalSeconds)]
        let lengths = zip(starts.dropFirst(), starts).map { Int($0 - $1) }
        let twoSided = 12 * 3 + 5
        let perSide = 10 * 3 * 2 + 3 + 5
        let withHold = 12 * (3 + 2) + 5
        XCTAssertEqual(lengths, [5, 30, 5, twoSided, 45, perSide, 45, withHold, 30])
        XCTAssertEqual(timeline.totalSeconds, StrengthTimelineFixture.strengthBreak().plannedSeconds)
        XCTAssertEqual(timeline.completedWork, 5)
        XCTAssertTrue(timeline.isClosed, "the break closes itself after the cool-down")
    }

    func testTheBreakClosesExactlyAsTheCoolDownEnds() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        clock.advance(TimeInterval(timeline.totalSeconds) - 0.1)
        XCTAssertFalse(timeline.update(at: clock.now).contains(.closed))
        XCTAssertEqual(timeline.current?.kind, .coolDown)
        clock.advance(0.1)
        XCTAssertEqual(timeline.update(at: clock.now).last, .closed)
        XCTAssertNil(timeline.current)
    }

    /// One update an hour late walks through every segment at its planned end.
    func testALateUpdateHandsOverAtPlannedEnds() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        clock.advance(100)
        let events = timeline.update(at: clock.now)
        XCTAssertEqual(events, [.started(.warmUp), .started(.leadIn), .started(.set(1)), .setEnded(1),
                                .started(.rest(beforeSet: 2))])
        // 5 + 30 + 5 + 41 = 81 s in, so the rest has 19 s behind it and 26 s left.
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 26, accuracy: 0.001)
    }

    // MARK: - Done

    func testDoneMidSetStartsTheRestAtOnce() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .set(1))
        clock.advance(10.4)
        _ = timeline.update(at: clock.now)

        let events = timeline.press(at: clock.now)
        XCTAssertEqual(events, [.setEnded(1), .started(.rest(beforeSet: 2))])
        XCTAssertEqual(timeline.current?.kind, .rest(beforeSet: 2))
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 45, accuracy: 0.001, "the whole rest, from now")
        XCTAssertEqual(timeline.breakRemaining(at: clock.now), TimeInterval(45 + 68 + 45 + 65 + 30), accuracy: 0.001)
    }

    func testDoneDuringALeadInIsIgnored() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        clock.advance(2)
        XCTAssertEqual(timeline.press(at: clock.now), [])
        XCTAssertEqual(timeline.current?.kind, .leadIn)
        XCTAssertEqual(timeline.index, 0)

        run(&timeline, clock: clock, until: .warmUp)
        run(&timeline, clock: clock, until: .leadIn)
        clock.advance(1)
        XCTAssertEqual(timeline.press(at: clock.now), [], "the lead-in before set 1 ignores Done too")
        XCTAssertEqual(timeline.current?.kind, .leadIn)

        // A rest's last five seconds are the next set's lead-in.
        run(&timeline, clock: clock, until: .rest(beforeSet: 2))
        clock.advance(41)
        XCTAssertEqual(timeline.press(at: clock.now), [])
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 4, accuracy: 0.001)
    }

    func testTwoPressesInOneSetAdvanceOnce() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .set(1))
        clock.advance(5)

        _ = timeline.press(at: clock.now)
        XCTAssertEqual(timeline.press(at: clock.now), [], "a double click is one Done")
        clock.advance(0.3)
        XCTAssertEqual(timeline.press(at: clock.now), [], "so is Space pressed twice")
        XCTAssertEqual(timeline.current?.kind, .rest(beforeSet: 2))
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 44.7, accuracy: 0.001, "the rest was not skipped")
    }

    /// Done during the rest skips it to the set's lead-in, so the set never starts unannounced.
    func testDoneDuringTheRestSkipsToTheNextSetsLeadIn() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .rest(beforeSet: 2))
        clock.advance(10)

        XCTAssertEqual(timeline.press(at: clock.now), [])
        XCTAssertEqual(timeline.current?.kind, .rest(beforeSet: 2))
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 5, accuracy: 0.001)
        clock.advance(5)
        XCTAssertEqual(timeline.update(at: clock.now), [.started(.set(2))])
    }

    /// A press that lands after the set's clock ran out, before any tick noticed, was aimed at the
    /// set: it ends the set and leaves the rest whole, less only the overrun.
    func testDoneJustAfterASetRanOutDoesNotSkipTheRest() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .set(1))
        clock.advance(TimeInterval(timeline.current!.seconds) + 0.5)

        XCTAssertEqual(timeline.press(at: clock.now), [.setEnded(1), .started(.rest(beforeSet: 2))])
        XCTAssertEqual(timeline.current?.kind, .rest(beforeSet: 2))
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), 44.5, accuracy: 0.001)
    }

    func testDoneOnTheWarmUpAndTheCoolDownMovesOn() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .warmUp)
        clock.advance(3)
        XCTAssertEqual(timeline.press(at: clock.now), [.started(.leadIn)])

        run(&timeline, clock: clock, until: .coolDown)
        clock.advance(3)
        XCTAssertEqual(timeline.press(at: clock.now), [.closed])
        XCTAssertTrue(timeline.isClosed)
        XCTAssertEqual(timeline.press(at: clock.now), [], "nothing happens after the break has closed")
    }

    // MARK: - Pause

    func testPauseFreezesEveryClockAndResumeContinues() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .set(2))
        clock.advance(12.5)
        _ = timeline.update(at: clock.now)
        let elapsed = timeline.elapsed(at: clock.now)
        let segment = timeline.segmentRemaining(at: clock.now)
        let whole = timeline.breakRemaining(at: clock.now)

        timeline.pause(at: clock.now)
        clock.advance(200)
        XCTAssertEqual(timeline.update(at: clock.now), [], "the side switch due meanwhile waits")
        XCTAssertEqual(timeline.press(at: clock.now), [], "Done does nothing while paused")
        XCTAssertEqual(timeline.elapsed(at: clock.now), elapsed)
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), segment)
        XCTAssertEqual(timeline.breakRemaining(at: clock.now), whole)

        timeline.resume(at: clock.now)
        XCTAssertEqual(timeline.elapsed(at: clock.now), elapsed, accuracy: 0.001)
        clock.advance(2)
        _ = timeline.update(at: clock.now)
        XCTAssertEqual(timeline.segmentRemaining(at: clock.now), segment - 2, accuracy: 0.001)
        XCTAssertEqual(timeline.current?.kind, .set(2))
    }

    // MARK: - Sides

    func testPerSideSetsAndTheCoolDownSwitchSides() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = makeTimeline(clock: clock)
        run(&timeline, clock: clock, until: .set(2))
        clock.advance(29)
        XCTAssertEqual(timeline.update(at: clock.now), [])
        clock.advance(1)
        XCTAssertEqual(timeline.update(at: clock.now), [.sideSwitched], "after ten reps on the first side")
        XCTAssertTrue(timeline.sideSwitched)

        run(&timeline, clock: clock, until: .coolDown)
        XCTAssertFalse(timeline.sideSwitched)
        clock.advance(15)
        XCTAssertEqual(timeline.update(at: clock.now), [.sideSwitched], "halfway through the cool-down")
    }

    // MARK: - End-range

    func testAnEndRangeBreakIsFourBlocksEachAfterItsLeadIn() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let endRange = StrengthTimelineFixture.endRangeBreak()
        var timeline = StrengthSessionTimeline(endRangeBreak: endRange, startedAt: clock.now)
        XCTAssertEqual(timeline.segments.map(\.kind), [
            .leadIn, .block(1), .leadIn, .block(2), .leadIn, .block(3), .leadIn, .block(4)
        ])
        XCTAssertEqual(timeline.totalSeconds, endRange.plannedSeconds)

        clock.advance(2)
        XCTAssertEqual(timeline.press(at: clock.now), [.started(.block(1)), .started(.leadIn)],
                       "Next in a lead-in passes its block, as in a movement break")
        XCTAssertEqual(timeline.current?.column, 1)
        clock.advance(TimeInterval(timeline.totalSeconds))
        XCTAssertEqual(timeline.update(at: clock.now).last, .closed)
        XCTAssertEqual(timeline.completedWork, 4)
    }

    /// Next pressed after a block's clock ran out, before any tick noticed, was aimed at that
    /// block: it must not also pass the next block and count it as done.
    func testNextJustAfterAnEndRangeBlockRanOutDoesNotPassTheNextBlock() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        var timeline = StrengthSessionTimeline(endRangeBreak: StrengthTimelineFixture.endRangeBreak(), startedAt: clock.now)
        run(&timeline, clock: clock, until: .block(1))
        clock.advance(TimeInterval(timeline.current!.seconds) + 0.5)

        XCTAssertEqual(timeline.press(at: clock.now), [.started(.leadIn)])
        XCTAssertEqual(timeline.current?.kind, .leadIn)
        XCTAssertEqual(timeline.current?.column, 1)
        XCTAssertEqual(timeline.completedWork, 1, "only the block that ran out counts")
    }

    /// A block the builder times shows the time it runs, not the library's: the cool-down runs
    /// 30 s, so 15 s a side, and an end-range block a minute. A rep dose is still shown as it is
    /// (LIB-16).
    func testTimedBlocksShowTheTimeTheyRunNotTheLibrarys() {
        XCTAssertEqual(StrengthTestSupport.movement("END-01").dose, "25 s/side")
        XCTAssertEqual(StrengthTestSupport.movement("END-07").dose, "30 s")
        let strength = StrengthSessionTimeline(strengthBreak: StrengthTimelineFixture.strengthBreak(), startedAt: Date())
        XCTAssertEqual(strength.segments.last?.dose, "15 s/side")

        let endRange = StrengthSessionTimeline(endRangeBreak: StrengthTimelineFixture.endRangeBreak(), startedAt: Date())
        let doses = endRange.segments.filter { $0.movement != nil }.map(\.dose)
        XCTAssertEqual(doses, ["30 s/side", "60 s", "6/side", "4 reps"])

        XCTAssertEqual(StrengthBlock(movement: StrengthTestSupport.movement("END-07"), seconds: 30).shownDose, "30 s")
        XCTAssertEqual(StrengthBlock(movement: StrengthTestSupport.movement("END-07"), seconds: 60).shownDose, "60 s")
        XCTAssertEqual(StrengthBlock(movement: StrengthTestSupport.movement("END-02"), seconds: 60).shownDose, "6/side")
    }

    /// A strength micro-break's lone move runs the whole minute, and its panel says so.
    func testAStrengthMicroBlockShowsTheTimeItRuns() {
        let block = StrengthBlock(movement: StrengthTestSupport.movement("END-07"), seconds: 60)
        let panel = MicroPanelBreak(StrengthMicroBreak(id: UUID(), blocks: [block], relaxed: []))
        XCTAssertEqual(panel.moves.first?.dose, DoseText("60 s"))
    }
}
