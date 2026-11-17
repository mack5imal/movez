import XCTest
@testable import movez

/// The rep meter's model: rep index and phase as a function of a set's elapsed seconds.
@MainActor
final class RepPacerTests: XCTestCase {
    private func pacer(_ dose: String, perSide: Bool = false) -> RepPacer? {
        let parsed = StrengthDose(text: dose)
        return RepPacer(
            reps: parsed.reps,
            perSide: perSide,
            holdSeconds: parsed.holdSeconds,
            paceSeconds: StrengthTiming.repPaceSeconds,
            switchSidesSeconds: StrengthTiming.switchSidesSeconds
        )
    }

    private func fill(_ state: RepPacerState) -> Double? {
        if case let .smooth(value) = state.level { return value }
        return nil
    }

    // MARK: - A twelve-rep set

    func testRepIndexAndPhaseThroughATwelveRepSet() throws {
        let meter = try XCTUnwrap(pacer("12 reps"))
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let setStart = clock.now
        func now() -> RepPacerState { meter.state(at: clock.now.timeIntervalSince(setStart)) }

        var state = now()
        XCTAssertEqual(state.rep, 1, "rep 1 starts with the set")
        XCTAssertEqual(state.phase, .rising)
        XCTAssertEqual(state.direction, .up)
        XCTAssertEqual(try XCTUnwrap(fill(state)), 0, accuracy: 1e-9)

        clock.advance(0.75)
        XCTAssertEqual(try XCTUnwrap(fill(now())), 0.5, accuracy: 1e-9, "halfway up at the middle of the rise")

        clock.advance(0.75)
        state = now()
        XCTAssertEqual(state.rep, 1)
        XCTAssertEqual(state.phase, .falling, "at 1.5 s the fill is full and turns down")
        XCTAssertEqual(state.direction, .down)
        XCTAssertEqual(try XCTUnwrap(fill(state)), 1, accuracy: 1e-9)

        clock.advance(1.5)
        state = now()
        XCTAssertEqual(state.rep, 2, "the counter moves as a rep starts rising")
        XCTAssertEqual(state.phase, .rising)
        XCTAssertEqual(try XCTUnwrap(fill(state)), 0, accuracy: 1e-9)

        clock.set(setStart.addingTimeInterval(34.5))
        state = now()
        XCTAssertEqual(state.rep, 12)
        XCTAssertEqual(state.phase, .falling)
        XCTAssertEqual(try XCTUnwrap(fill(state)), 1, accuracy: 1e-9)
        XCTAssertEqual(state.counter, "Rep 12 of 12")

        clock.set(setStart.addingTimeInterval(36))
        state = now()
        XCTAssertEqual(state.stage, .finished)
        XCTAssertEqual(state.counter, "Rep 12 of 12", "the counter reads N of N at reps × 3 s")
        XCTAssertEqual(state.phase, .still, "the meter has stopped")
        XCTAssertEqual(state.direction, .stopped)
        XCTAssertEqual(try XCTUnwrap(fill(state)), 0, accuracy: 1e-9)

        clock.advance(4.9)
        XCTAssertEqual(now(), state, "nothing moves through the 5 s grace")
        XCTAssertEqual(meter.meterSeconds + TimeInterval(StrengthTiming.setGraceSeconds), 41)
    }

    func testTheRiseIsAnEaseInOutSine() throws {
        let meter = try XCTUnwrap(pacer("12 reps"))
        let quarter = try XCTUnwrap(fill(meter.state(at: 0.375)))
        XCTAssertEqual(quarter, (1 - cos(Double.pi / 4)) / 2, accuracy: 1e-9)
        let fallingQuarter = try XCTUnwrap(fill(meter.state(at: 1.5 + 0.375)))
        XCTAssertEqual(fallingQuarter, 1 - quarter, accuracy: 1e-9, "the fall mirrors the rise")
    }

    // MARK: - Per-side sets

    func testAPerSideSetCuesTheSwitchForThreeSecondsThenCountsAgain() throws {
        let meter = try XCTUnwrap(pacer("10/side", perSide: true))
        XCTAssertEqual(meter.state(at: 27).counter, "Rep 10 of 10")
        XCTAssertEqual(meter.state(at: 27).sideIndex, 0)

        for second in [30.0, 31.5, 32.99] {
            let cue = meter.state(at: second)
            XCTAssertEqual(cue.stage, .switchSides, "at \(second) s")
            XCTAssertEqual(cue.counter, "Switch sides")
            XCTAssertEqual(cue.sideIndex, 1)
            XCTAssertEqual(fill(cue), 0, "the meter empties for the cue")
        }

        let again = meter.state(at: 33)
        XCTAssertEqual(again.stage, .rep)
        XCTAssertEqual(again.counter, "Rep 1 of 10")
        XCTAssertEqual(again.sideIndex, 1)
        XCTAssertEqual(again.phase, .rising)

        XCTAssertEqual(meter.state(at: 62.9).counter, "Rep 10 of 10")
        XCTAssertEqual(meter.state(at: 63).stage, .finished)
        XCTAssertEqual(
            Int(meter.meterSeconds) + StrengthTiming.setGraceSeconds,
            StrengthSet(movement: StrengthTestSupport.movement("SQT-06"), setNumber: 2).plannedSeconds,
            "the meter and the set clock agree"
        )
    }

    // MARK: - Holds

    func testADoseWithAHoldRisesHoldsThenFalls() throws {
        let meter = try XCTUnwrap(pacer("12 reps, alternating, 2 s hold"))
        XCTAssertEqual(meter.repSeconds, 5)

        let top = meter.state(at: 1.5)
        XCTAssertEqual(top.phase, .holding)
        XCTAssertEqual(top.direction, .hold)
        XCTAssertEqual(fill(top), 1)
        XCTAssertEqual(meter.state(at: 3.4).phase, .holding)

        let down = meter.state(at: 3.5)
        XCTAssertEqual(down.phase, .falling)
        XCTAssertEqual(try XCTUnwrap(fill(down)), 1, accuracy: 1e-9)
        XCTAssertEqual(meter.state(at: 5).rep, 2)
        XCTAssertEqual(meter.state(at: 60).stage, .finished, "alternating reps all count toward the 12")
    }

    // MARK: - Pause

    func testPausedStateFreezesRepAndFill() throws {
        let meter = try XCTUnwrap(pacer("12 reps"))
        let running = meter.state(at: 7.1)
        let paused = meter.state(at: 7.1, paused: true)
        XCTAssertEqual(paused.direction, .paused)
        XCTAssertEqual(paused.rep, running.rep)
        XCTAssertEqual(paused.phase, running.phase)
        XCTAssertEqual(paused.level, running.level)
    }

    // MARK: - Reduce Motion

    func testReduceMotionStepsWholeSegments() throws {
        let meter = try XCTUnwrap(pacer("12 reps"))
        for tenth in 0..<360 {
            let second = Double(tenth) / 10
            let state = meter.state(at: second, stepped: true)
            guard case let .stepped(filled) = state.level else {
                return XCTFail("a smooth level at \(second) s with Reduce Motion on")
            }
            XCTAssertEqual(filled, Int(second / 3), "one segment fills per rep, at \(second) s")
            XCTAssertEqual(state.rep, Int(second / 3) + 1)
        }
        XCTAssertEqual(meter.state(at: 36, stepped: true).level, .stepped(filled: 12))
        XCTAssertEqual(meter.state(at: 31, stepped: true).counter, meter.state(at: 31).counter,
                       "the counter is the same either way")
    }

    // MARK: - No meter

    func testHoldsSecondsDosesAndSlowMovesHaveNoMeter() {
        XCTAssertNil(pacer("30 s hold"), "a timed hold")
        XCTAssertNil(pacer("6 × 5 s"), "a dose in seconds")
        XCTAssertNil(pacer("45–60 s"))
        let slow = StrengthSet(movement: StrengthTestSupport.movement("COR-16"), setNumber: 3)
        XCTAssertNil(RepPacer(
            reps: slow.reps, perSide: slow.perSide, holdSeconds: slow.holdSeconds,
            paceSeconds: StrengthTiming.repPaceSeconds, switchSidesSeconds: StrengthTiming.switchSidesSeconds
        ), "COR-16 is one of the slow multi-part moves")
        XCTAssertEqual(slow.plannedSeconds, StrengthTestSupport.movement("COR-16").blockSeconds)
    }
}
