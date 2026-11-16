import XCTest
@testable import movez

/// The strength overlay's keys, disc, header and close, driven through the view model and the
/// view values the overlay is built from.
@MainActor
final class StrengthOverlayViewTests: XCTestCase {
    private func makeViewModel(
        clock: ManualClock,
        strengthBreak: StrengthBreak = StrengthTimelineFixture.strengthBreak()
    ) -> StrengthOverlayViewModel {
        StrengthOverlayViewModel(
            strengthBreak: strengthBreak,
            startedAt: clock.now,
            clock: clock,
            chimes: RecordingChimePlayer(),
            snoozesLeft: 2,
            skipsToday: 1,
            mode: .strength
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

    // MARK: - Done

    func testSpaceEndsTheSetAndStartsTheRest() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(1))
        clock.advance(10)
        viewModel.tick()

        XCTAssertTrue(viewModel.handleKey(OverlayKeyMap.space), "Space is the disc on a strength break")
        XCTAssertEqual(viewModel.state.segment, .rest(beforeSet: 2))
        XCTAssertEqual(viewModel.state.headline, "Rest")
        XCTAssertEqual(viewModel.state.discLabel, "REST")
    }

    func testClickingTheDiscEndsTheSet() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(1))
        clock.advance(10)
        viewModel.tick()
        XCTAssertEqual(viewModel.state.discLabel, "DONE")

        StrengthOverlayScreen(viewModel: viewModel).actions.disc()

        XCTAssertEqual(viewModel.state.segment, .rest(beforeSet: 2))
    }

    func testSpaceNeverPausesAStrengthBreakButStillPausesAMovementBreak() {
        XCTAssertEqual(OverlayKeyMap.timeline(OverlayKeyMap.space), .disc)
        XCTAssertEqual(OverlayKeyMap.timeline(OverlayKeyMap.returnKey), .disc)
        XCTAssertEqual(OverlayKeyMap.timeline(53), .ignored, "Escape does nothing")
        XCTAssertEqual(OverlayKeyMap.routine(OverlayKeyMap.space), .togglePause)
        XCTAssertEqual(OverlayKeyMap.routine(OverlayKeyMap.rightArrow), .next)

        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        run(viewModel, clock: clock, until: .set(1))
        XCTAssertFalse(viewModel.handleKey(53))
        XCTAssertEqual(viewModel.state.segment, .set(1))
        XCTAssertFalse(viewModel.state.isPaused)
    }

    // MARK: - Close

    func testTheClosedSessionDismissesTheCardWithNoEndScreen() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock)
        var finished: [[Int]] = []
        var worked = 0
        viewModel.onFinished = { finished.append([$0, $1, $2]) }
        viewModel.onWorkCompleted = { _ in worked += 1 }
        XCTAssertTrue(StrengthOverlayView(state: viewModel.state).showsCard)

        var ticks = 0
        while !viewModel.isClosed, ticks < 2_000 {
            clock.advance(1)
            viewModel.tick()
            ticks += 1
        }

        XCTAssertTrue(viewModel.state.isClosed)
        XCTAssertNil(viewModel.state.segment, "nothing is left on screen: no end state follows the cool-down")
        XCTAssertEqual(viewModel.state.headline, "")
        XCTAssertEqual(viewModel.state.movementName, "")
        XCTAssertFalse(StrengthOverlayView(state: viewModel.state).showsCard, "the card fades as the session closes")
        XCTAssertEqual(finished.count, 1, "the close ends the break once, which dismisses the overlay")
        XCTAssertEqual(finished.first?.prefix(2), [5, 5], "every move done, of five")
        XCTAssertEqual(worked, 5, "warm-up, three sets and cool-down are each recorded once")
    }

    func testTheCardFadesFasterThanTheDim() {
        XCTAssertEqual(StrengthOverlayScreen.cardFade, 0.24)
        XCTAssertEqual(OverlayWindowController.dismissFade, 0.3)
    }

    // MARK: - Header badge

    func testTheStrengthHeaderShowsTheStrengthBadgeFromTheSessionsMode() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let state = makeViewModel(clock: clock).state
        let badge = OverlayHeader(mode: state.mode, trailing: state.headerTrailing).badge

        XCTAssertEqual(badge.definition, BreakMode.strength.definition)
        XCTAssertEqual(badge.text, "STRENGTH BREAK")
        XCTAssertEqual(badge.glyph?.id, "mode.strength")
    }

    func testAnEndRangeBreakWearsTheStrengthBadge() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = StrengthOverlayViewModel(
            endRangeBreak: StrengthTimelineFixture.endRangeBreak(), startedAt: clock.now, clock: clock, mode: .strength
        )
        let badge = OverlayHeader(mode: viewModel.state.mode, trailing: "").badge

        XCTAssertEqual(badge.text, "STRENGTH BREAK")
        XCTAssertEqual(viewModel.state.strip.map(\.heading), ["1", "2", "3", "4"])
    }

    func testTheMovementHeaderShowsTheMovementBadgeFromTheSessionsMode() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let blocks = ["CIR-02", "FLX-01", "STR-04", "BRE-01"].compactMap { id in
            RoutineTestSupport.library.movement(id: id).map { RoutineBlock(movement: $0, seconds: 60) }
        }
        let viewModel = OverlayViewModel(
            routine: Routine(id: UUID(), blocks: blocks), startedAt: clock.now, clock: clock, mode: .movement
        )
        let badge = OverlayHeader(mode: viewModel.state.mode, trailing: viewModel.state.headerTrailing).badge

        XCTAssertEqual(badge.definition, BreakMode.movement.definition)
        XCTAssertEqual(badge.text, "MOVEMENT BREAK")
        XCTAssertEqual(badge.glyph?.id, "mode.movement")
    }

    // MARK: - Copy

    /// The instruction is the library's text, shown exactly as written. The design's sample
    /// instruction stands in for a library entry here.
    func testTheSetShowsItsInstructionVerbatim() {
        let sample = "Hold the weight at your chest. Sit back between your heels, chest up, then stand tall."
        let base = StrengthTestSupport.movement("PSH-04")
        let movement = StrengthMovement(
            id: base.id, name: base.name, bucket: base.bucket, regions: base.regions, dose: base.dose,
            perSide: base.perSide, blockSeconds: base.blockSeconds, difficulty: base.difficulty,
            settings: base.settings, onFloor: base.onFloor, equipment: base.equipment,
            vigorous: base.vigorous, load: base.load,
            gripDemand: base.gripDemand, microEligible: base.microEligible, instructions: sample,
            v4Overlap: base.v4Overlap
        )
        let fixture = StrengthTimelineFixture.strengthBreak()
        let strengthBreak = StrengthBreak(
            id: fixture.id, letter: fixture.letter, warmUp: fixture.warmUp,
            sets: [StrengthSet(movement: movement, setNumber: 1)] + Array(fixture.sets.dropFirst()),
            coolDown: fixture.coolDown, relaxed: []
        )
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let viewModel = makeViewModel(clock: clock, strengthBreak: strengthBreak)
        run(viewModel, clock: clock, until: .set(1))

        XCTAssertEqual(viewModel.state.instruction, sample)
        XCTAssertTrue(viewModel.state.showsMeter, "a rep-counted set has the two-column body")
        XCTAssertEqual(viewModel.state.counter, "Rep 1 of 12")
    }

    func testTheSideToggleSaysLeftAndRight() {
        XCTAssertEqual(BreakSide.left.label, "Left")
        XCTAssertEqual(BreakSide.right.label, "Right")
    }
}
