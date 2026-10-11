import XCTest
@testable import movez

/// The micro-break panel once its count-in is over: a lead-in before each movement, the side
/// switch, the chimes, and a ring that runs the way the full break's does.
@MainActor
final class MicroPanelTests: XCTestCase {
    private let library = RoutineTestSupport.library
    private let start = SchedulerHarness.mondayMorning

    private func microCountIn(clock: ManualClock) -> PanelViewModel {
        let model = PanelViewModel(
            phase: .microCountIn,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(21 - 30),
            totalSeconds: 30
        )
        model.microSeconds = 70
        return model
    }

    // MARK: - The running micro-break

    private func running(_ blocks: [(id: String, seconds: Int)], clock: ManualClock, chimes: RecordingChimePlayer) -> PanelViewModel {
        let model = microCountIn(clock: clock)
        model.micro = MicroBreak(id: UUID(), blocks: blocks.compactMap { entry in
            library.movement(id: entry.id).map { RoutineBlock(movement: $0, seconds: entry.seconds) }
        })
        model.chimes = chimes
        model.beginMicroRunning(at: clock.now)
        return model
    }

    /// Both movements are on screen in turn. The panel used to run the first for the whole minute
    /// while history recorded the second as done too.
    func testATwoMovementMicroBreakShowsBothWithALeadInBetween() {
        let clock = ManualClock(now: start)
        let chimes = RecordingChimePlayer()
        let model = running([("CIR-06", 30), ("EYE-01", 30)], clock: clock, chimes: chimes)
        var ended = 0
        model.actions.microEnded = { ended += 1 }

        model.tick()
        XCTAssertEqual(model.title, "Arm circles")
        XCTAssertEqual(model.discNumerals, "−0:05")
        XCTAssertEqual(model.discMode, .leadIn)
        XCTAssertEqual(chimes.count(of: .transition), 1, "the first movement chimes as it appears, as the second does")

        clock.advance(5)
        model.tick()
        XCTAssertEqual(model.discNumerals, "0:30")
        XCTAssertEqual(model.discMode, .full)

        clock.advance(30)
        model.tick()
        XCTAssertEqual(model.title, "Distance gaze (20-20-20)", "the second movement appears to be read")
        XCTAssertEqual(model.eyebrow, "MICRO-BREAK · EYES")
        XCTAssertEqual(model.discNumerals, "−0:05")
        XCTAssertEqual(model.discMode, .leadIn)
        XCTAssertEqual(chimes.count(of: .transition), 2, "the chime plays as it appears")

        clock.advance(5)
        model.tick()
        XCTAssertEqual(model.discNumerals, "0:30")
        XCTAssertEqual(model.discMode, .full)
        XCTAssertEqual(model.body, library.movement(id: "EYE-01")?.instructions)

        clock.advance(25)
        model.tick()
        XCTAssertEqual(ended, 0, "two halves and two lead-ins run 70 seconds")

        clock.advance(5)
        model.tick()
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(chimes.count(of: .transition), 2, "the completion chime is the scheduler's")
    }

    func testAPerSideMicroBreakSwitchesSidesHalfway() {
        let clock = ManualClock(now: start)
        let chimes = RecordingChimePlayer()
        let model = running([("HWF-01", 60)], clock: clock, chimes: chimes)
        var ended = 0
        model.actions.microEnded = { ended += 1 }

        XCTAssertEqual(model.title, "Wrist flexor stretch")
        XCTAssertEqual(model.discMode, .leadIn)

        clock.advance(5)
        model.tick()
        XCTAssertEqual(model.eyebrow, "MICRO-BREAK · HANDS · LEFT SIDE")
        XCTAssertEqual(model.discMode, .halfShare(sideIndex: 0))
        XCTAssertEqual(chimes.count(of: .transition), 1, "the lead-in's chime")

        clock.advance(29)
        model.tick()
        XCTAssertEqual(chimes.count(of: .transition), 1)

        clock.advance(1)
        model.tick()
        XCTAssertEqual(model.eyebrow, "MICRO-BREAK · HANDS · RIGHT SIDE")
        XCTAssertEqual(model.discMode, .halfShare(sideIndex: 1))
        XCTAssertEqual(chimes.count(of: .transition), 2, "the halfway chime")

        clock.advance(30)
        model.tick()
        XCTAssertEqual(ended, 1, "a single movement runs its lead-in and the minute")
    }

    func testOnlyTheMovementsThatRanHalfwayAreRecorded() throws {
        let first = try XCTUnwrap(library.movement(id: "CIR-06"))
        let second = try XCTUnwrap(library.movement(id: "EYE-01"))
        let micro = MicroBreak(id: UUID(), blocks: [
            RoutineBlock(movement: first, seconds: 30),
            RoutineBlock(movement: second, seconds: 30)
        ])
        XCTAssertEqual(micro.totalSeconds, 70)
        XCTAssertEqual(micro.startsAt(block: 0), 5)
        XCTAssertEqual(micro.startsAt(block: 1), 40)
        XCTAssertEqual(micro.blocksRun(seconds: 15).map(\.movement.id), [], "the lead-in is not movement time")
        XCTAssertEqual(micro.blocksRun(seconds: 45).map(\.movement.id), ["CIR-06"])
        XCTAssertEqual(micro.blocksRun(seconds: 55).map(\.movement.id), ["CIR-06", "EYE-01"])
    }

    /// A movement's ring fills as it runs, as the full break's does; only lead-ins and count-ins
    /// drain, counting down to a start.
    func testTheMicroRingFillsLikeTheFullBreaks() {
        let clock = ManualClock(now: start)
        let chimes = RecordingChimePlayer()
        let model = running([("CIR-06", 30), ("EYE-01", 30)], clock: clock, chimes: chimes)
        XCTAssertEqual(model.discProgress, 1, accuracy: 0.01, "a lead-in starts full")
        clock.advance(2.5)
        model.tick()
        XCTAssertEqual(model.discProgress, 0.5, accuracy: 0.01, "and drains")

        clock.advance(2.5)
        model.tick()
        XCTAssertEqual(model.discProgress, 0, accuracy: 0.01, "a movement starts empty")
        clock.advance(10)
        model.tick()
        XCTAssertEqual(model.discProgress, 1.0 / 3.0, accuracy: 0.01, "and fills")
    }

    func testAPerSideMicroRingFillsEachSide() {
        let clock = ManualClock(now: start)
        let model = running([("HWF-01", 60)], clock: clock, chimes: RecordingChimePlayer())
        clock.advance(5 + 15)
        model.tick()
        XCTAssertEqual(model.microSide, .left)
        XCTAssertEqual(model.discProgress, 0.5, accuracy: 0.01)
        clock.advance(10)
        model.tick()
        XCTAssertEqual(model.discProgress, 5.0 / 6.0, accuracy: 0.01, "filling, not draining")

        clock.advance(6)
        model.tick()
        XCTAssertEqual(model.microSide, .right)
        XCTAssertEqual(model.discProgress, 1.0 / 30.0, accuracy: 0.01, "the right side starts again from empty")
    }

    func testTheSecondMicroSnoozeIsASkip() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        var snoozes = 0
        var skips = 0
        model.actions.microSnooze = { snoozes += 1 }
        model.actions.microSkip = { skips += 1 }

        model.snooze()
        XCTAssertEqual(snoozes, 1)
        XCTAssertEqual(skips, 0)

        model.snooze()
        XCTAssertEqual(snoozes, 1)
        XCTAssertEqual(skips, 1, "one snooze is the allowance; asking again is a skip")
    }

    func testAMicroBreakSkipCarriesNoCount() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        XCTAssertEqual(model.skipLabel, "Skip")
        XCTAssertTrue(model.showSnooze)
    }
}
