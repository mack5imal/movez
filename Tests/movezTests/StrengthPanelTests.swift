import XCTest
@testable import movez

/// The heads-up and micro-break panels in both modes: the mode badge's eyebrow, the strength and
/// end-range heads-up words, and the strength micro-break's dose line and posture.
@MainActor
final class StrengthPanelTests: XCTestCase {
    private let strengthLibrary = RoutineTestSupport.strengthLibrary
    private let start = SchedulerHarness.mondayMorning

    // MARK: - Fixtures

    private func headsUp(
        mode: BreakMode,
        announced: HeadsUpAnnouncement,
        snoozesLeft: Int = 2,
        deferred: Bool = false
    ) -> PanelViewModel {
        let clock = ManualClock(now: start)
        let model = PanelViewModel(phase: .headsUp, clock: clock, startedAt: clock.now, totalSeconds: 60)
        model.modeDefinition = mode.definition
        model.announced = announced
        model.blockCount = 5
        model.breakMinutes = 5
        model.snoozesLeft = snoozesLeft
        if deferred {
            model.deferred = PanelViewModel.DeferredInfo(sittingFor: 5_700, reason: .microphone)
        }
        return model
    }

    private func strengthMove(_ id: String) throws -> StrengthMovement {
        try XCTUnwrap(strengthLibrary.movement(id: id), "the bundled strength library has \(id)")
    }

    private func strengthMicro(_ ids: [String], seconds: Int) throws -> StrengthMicroBreak {
        let blocks = try ids.map { StrengthBlock(movement: try strengthMove($0), seconds: seconds) }
        return StrengthMicroBreak(id: UUID(), blocks: blocks, relaxed: [])
    }

    private func microCountIn(_ micro: MicroPanelBreak, mode: BreakMode, clock: ManualClock) -> PanelViewModel {
        let model = PanelViewModel(
            phase: .microCountIn,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(-9),
            totalSeconds: 30
        )
        model.micro = micro
        model.modeDefinition = mode.definition
        return model
    }

    // MARK: - Heads-up

    func testTheStrengthHeadsUpNamesItsModeAndHasTheDesignsWords() {
        let model = headsUp(mode: .strength, announced: .strength(loaded: true))
        XCTAssertEqual(model.eyebrowLabel, .breakEyebrow)
        XCTAssertEqual(model.eyebrow, "STRENGTH BREAK")
        XCTAssertEqual(model.title, "Strength break in a minute")
        XCTAssertEqual(model.body, "About 5 minutes, three sets. Have your weights nearby.")
        XCTAssertEqual(model.discNumerals, "−1:00")
    }

    func testTheEndRangeHeadsUpKeepsTheStrengthEyebrow() {
        let model = headsUp(mode: .strength, announced: .endRange)
        XCTAssertEqual(model.eyebrow, "STRENGTH BREAK", "the design has no end-range label in the eyebrow")
        XCTAssertEqual(model.title, "End-range break in a minute")
        XCTAssertEqual(model.body, "Four minutes, four stretches. No weights needed.")
    }

    func testTheMovementHeadsUpOnlyGainsTheBadge() {
        let model = headsUp(mode: .movement, announced: .movement)
        XCTAssertEqual(model.eyebrowLabel, .breakEyebrow)
        XCTAssertEqual(model.eyebrow, "MOVEMENT BREAK")
        XCTAssertEqual(model.title, "Movement break in a minute")
        XCTAssertEqual(model.body, "Five minutes, five movements.")
    }

    func testTheDeferredStrengthHeadsUpWidensAndDropsASpentSnooze() {
        let model = headsUp(mode: .strength, announced: .strength(loaded: true), snoozesLeft: 0, deferred: true)
        XCTAssertEqual(model.panelWidth, Tokens.Metric.panelWidthDeferred)
        XCTAssertEqual(model.panelWidth, 420)
        XCTAssertEqual(model.deferredBadge, "Sitting for 1 h 35 m · break waited for your call")
        XCTAssertFalse(model.showSnooze)
    }

    /// Bodyweight only is a valid setup (DECISIONS 56), and its breaks hold no weights, so its
    /// heads-up does not ask for them (LIB-6).
    func testABodyweightStrengthBreakIsNotToldToHaveWeightsNearby() {
        let builder = StrengthBreakBuilder(library: StrengthTestSupport.library)
        let order = StrengthTestSupport.plans[0].order
        var bodyweight = StrengthContext()
        bodyweight.seed = 7
        let unloaded = builder.build(letter: .dayA, setOrder: order, context: bodyweight)
        XCTAssertEqual(HeadsUpAnnouncement(.strength(unloaded)), .strength(loaded: false))
        XCTAssertEqual(HeadsUpAnnouncement.strength(loaded: false).fixedBody, "About 5 minutes, three sets.")

        let loaded = builder.build(letter: .dayA, setOrder: order, context: StrengthTestSupport.everythingContext(seed: 7))
        XCTAssertTrue(loaded.sets.contains { !$0.movement.isBodyweight })
        XCTAssertEqual(HeadsUpAnnouncement(.strength(loaded)), .strength(loaded: true))

        let model = headsUp(mode: .strength, announced: .strength(loaded: false))
        XCTAssertEqual(model.body, "About 5 minutes, three sets.")
    }

    func testAHeadsUpAnnouncesTheKindOfBreakItWasBuiltFor() throws {
        let routine = Routine(id: UUID(), blocks: [])
        XCTAssertEqual(HeadsUpAnnouncement(.movement(routine)), .movement)
        let endRange = EndRangeBreak(id: UUID(), blocks: [], relaxed: [])
        XCTAssertEqual(HeadsUpAnnouncement(.endRange(endRange)), .endRange)
    }

    // MARK: - Micro-break eyebrow, both modes

    func testEveryMicroStateCarriesTheModesMicroBreakEyebrow() throws {
        let movementMicro = MicroPanelBreak(MicroBreak(id: UUID(), blocks: [
            RoutineBlock(movement: try XCTUnwrap(RoutineTestSupport.library.movement(id: "HWF-01")), seconds: 60)
        ]))
        let strength = MicroPanelBreak(try strengthMicro(["END-35"], seconds: 60))

        for (micro, mode, eyebrow) in [
            (movementMicro, BreakMode.movement, "MOVEMENT MICRO-BREAK"),
            (strength, BreakMode.strength, "STRENGTH MICRO-BREAK")
        ] {
            let clock = ManualClock(now: start)
            let model = microCountIn(micro, mode: mode, clock: clock)
            XCTAssertEqual(model.eyebrowLabel, .microBreakEyebrow)
            XCTAssertEqual(model.eyebrow, eyebrow, "count-in")

            model.beginMicroRunning(at: clock.now)
            XCTAssertTrue(model.isMicroLeadIn)
            XCTAssertEqual(model.eyebrow, eyebrow, "lead-in")

            for (seconds, side) in [(10, BreakSide.left), (36, BreakSide.right)] {
                clock.advance(TimeInterval(seconds) - model.elapsed)
                model.tick()
                XCTAssertEqual(model.microSide, side)
                XCTAssertEqual(model.eyebrow, eyebrow, "no side in the eyebrow on the \(side) side")
                // The design replaced "MICRO-BREAK · {AREA} · {SIDE} SIDE" with the mode's eyebrow.
                XCTAssertFalse(model.eyebrow.contains("SIDE"))
                XCTAssertFalse(model.eyebrow.contains("·"))
            }
        }
    }

    // MARK: - Strength micro-break

    func testTheStrengthCountInSaysThePostureAndHasNoDose() throws {
        let clock = ManualClock(now: start)
        let model = microCountIn(MicroPanelBreak(try strengthMicro(["END-31", "END-37"], seconds: 30)), mode: .strength, clock: clock)
        XCTAssertEqual(model.title, "\(try strengthMove("END-31").name) in a moment")
        XCTAssertEqual(model.body, "One minute, sitting. Starts in 21 seconds.")
        XCTAssertNil(model.microDose, "the count-in's title already names the move")
    }

    func testThePostureWordsAreTheDesigns() {
        XCTAssertEqual(MicroPanelBreak.strengthPosture([true, true]), "sitting")
        XCTAssertEqual(MicroPanelBreak.strengthPosture([false]), "standing")
        XCTAssertEqual(MicroPanelBreak.strengthPosture([true, false]), "sitting then standing")
    }

    func testTheDoseLineIsPanelDoseInAccentAndFollowsTheDoseRule() throws {
        XCTAssertEqual(PanelHeader.doseStyle, MovezType.panelDose)
        XCTAssertEqual(PanelHeader.doseColor, Tokens.accent)

        let move = try strengthMove("END-33")
        XCTAssertEqual(move.dose, "4/side, 3 s hold")
        let clock = ManualClock(now: start)
        let model = microCountIn(MicroPanelBreak(try strengthMicro(["END-33"], seconds: 60)), mode: .strength, clock: clock)
        model.beginMicroRunning(at: clock.now)

        let dose = try XCTUnwrap(model.microDose, "the lead-in shows the next move's dose")
        XCTAssertEqual(dose, DoseText(move.dose))
        XCTAssertEqual(dose.line, "4 each side")
        XCTAssertEqual(dose.modifier, "3 s hold")
        XCTAssertEqual(model.title, move.name)
    }

    func testAPerSideStrengthMoveSwitchesAtTheHalfwayChime() throws {
        let move = try strengthMove("END-35")
        let clock = ManualClock(now: start)
        let chimes = RecordingChimePlayer()
        let model = microCountIn(MicroPanelBreak(try strengthMicro(["END-35"], seconds: 60)), mode: .strength, clock: clock)
        model.chimes = chimes
        model.beginMicroRunning(at: clock.now)

        XCTAssertTrue(move.instructions.hasSuffix("Switch feet at the chime."))
        XCTAssertEqual(model.body, move.instructions, "an instruction that already names the chime is not repeated")
        XCTAssertEqual(model.microDose?.line, "20 s each side")

        clock.advance(5)
        model.tick()
        XCTAssertEqual(model.microSide, .left)
        clock.advance(30)
        model.tick()
        XCTAssertEqual(model.microSide, .right)
        XCTAssertEqual(model.discMode, .halfShare(sideIndex: 1))
        XCTAssertEqual(chimes.count(of: .transition), 2, "one as the move appears, one at halfway")
    }

    func testAPerSideInstructionWithoutTheChimeGainsIt() throws {
        let move = try strengthMove("END-06")
        XCTAssertTrue(move.perSide)
        XCTAssertFalse(move.instructions.contains("chime"))
        let panel = MicroPanelBreak(try strengthMicro(["END-06"], seconds: 60))
        let shown = try XCTUnwrap(panel.moves.first)
        XCTAssertEqual(panel.instructions(for: shown), "\(move.instructions) Switch at the chime.")
    }

    func testTwoStrengthMovesRunWithALeadInBeforeTheSecond() throws {
        let micro = try strengthMicro(["END-31", "END-37"], seconds: 30)
        let panel = MicroPanelBreak(micro)
        XCTAssertEqual(panel.totalSeconds, micro.totalSeconds)
        XCTAssertEqual(panel.startsAt(move: 1), 40)

        let clock = ManualClock(now: start)
        let model = microCountIn(panel, mode: .strength, clock: clock)
        model.beginMicroRunning(at: clock.now)
        clock.advance(37)
        model.tick()
        XCTAssertEqual(model.title, try strengthMove("END-37").name)
        XCTAssertEqual(model.discNumerals, "−0:03")
        XCTAssertEqual(model.discMode, .leadIn)
        XCTAssertEqual(model.microDose, DoseText(try strengthMove("END-37").dose))
        XCTAssertEqual(model.body, try strengthMove("END-37").instructions, "a two-sided move has no side switch")
    }

    func testAMovementMicroBreakHasNoDoseLine() throws {
        let clock = ManualClock(now: start)
        let micro = MicroPanelBreak(MicroBreak(id: UUID(), blocks: [
            RoutineBlock(movement: try XCTUnwrap(RoutineTestSupport.library.movement(id: "CIR-06")), seconds: 60)
        ]))
        let model = microCountIn(micro, mode: .movement, clock: clock)
        model.beginMicroRunning(at: clock.now)
        XCTAssertNil(model.microDose)
    }
}
