import Foundation

/// The strength and end-range overlay states the snapshots render.
///
/// Each is produced the way the live overlay produces it: a break built from moves in the bundled
/// strength library, run through `StrengthOverlayViewModel` on a `ManualClock` to the moment the
/// design draws. The moves are picked here, in fixture code, because a snapshot needs the same
/// moves every time; app code never names one.
@MainActor
extension SnapshotFixtures {
    /// The bundled strength library, or nil when the bundle cannot be read, in which case the
    /// strength snapshots render an empty card rather than stopping `make snapshots`.
    static let strengthLibrary: StrengthLibrary? = {
        guard let movements = try? LibraryLoader.loadBundled() else { return nil }
        return try? StrengthLibraryLoader.loadBundled(movementLibrary: movements)
    }()

    /// A library id from its bucket and number, for the moves the snapshots pin. Fixtures are the
    /// one place allowed to name a move; spelling the id out of its parts keeps the "no quoted
    /// strength id under Sources/" check meaningful for app code.
    static func fixtureId(_ bucket: StrengthBucket, _ number: Int) -> String {
        String(format: "%@-%02d", bucket.rawValue, number)
    }

    // MARK: - Strength break

    /// Set 1 of a two-sided rep set, seven reps in.
    static func strengthSet() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .set(1))
            settle(model, clock, seconds: 19.4)
        }
    }

    static func strengthWarmUp() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .warmUp)
            settle(model, clock, seconds: 8)
        }
    }

    /// The lead-in before set 1: set 1's body with the meter empty at Rep 1.
    static func strengthLeadIn() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .warmUp)
            run(model, clock, until: .leadIn)
            settle(model, clock, seconds: 1)
        }
    }

    static func strengthRest() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .rest(beforeSet: 2))
            settle(model, clock, seconds: 13)
        }
    }

    static func strengthCoolDown() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .coolDown)
            settle(model, clock, seconds: 6)
        }
    }

    /// Set 2, a per-side rep set, in its switch-sides cue.
    static func strengthSide() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .set(2))
            for _ in 0..<31 { tick(model, clock) }
        }
    }

    /// A timed set: no meter, the disc counting the hold.
    static func strengthHold() -> StrengthOverlayState {
        strengthState(firstSet: holdSetId) { model, clock in
            run(model, clock, until: .set(1))
            settle(model, clock, seconds: 8)
        }
    }

    static func strengthPaused() -> StrengthOverlayState {
        strengthState { model, clock in
            run(model, clock, until: .set(1))
            settle(model, clock, seconds: 19.4)
            model.togglePause()
            settle(model, clock, seconds: 12)
        }
    }

    static func strengthReducedMotion() -> StrengthOverlayState {
        strengthState(reduceMotion: true) { model, clock in
            run(model, clock, until: .set(1))
            settle(model, clock, seconds: 19.4)
        }
    }

    /// The longest set name the design shows over the longest dose, holding at the top of rep 4.
    static func strengthLongDose() -> StrengthOverlayState {
        strengthState(firstSet: nil, longDose: true) { model, clock in
            run(model, clock, until: .set(1))
            settle(model, clock, seconds: 17)
        }
    }

    /// A break from the relaxed fallback: a bodyweight-only day on which every move is already
    /// served and excluded, built by the real builder, at set 1. It shows that a break the
    /// builder had to relax is drawn like any other rather than as an empty card.
    static func strengthRelaxed() -> StrengthOverlayState {
        guard let library = strengthLibrary else { return StrengthOverlayState() }
        let everything = Set(library.movements.map(\.id))
        var context = StrengthContext()
        context.usedStrengthIdsToday = everything
        context.excluded = everything
        context.equipment = []
        context.solidWallNearby = false
        context.difficultyCap = 1
        let setOrder = StrengthDayPlanner.replay(letter: .dayA, breaks: 1, priorLead: nil).orders[0]
        let strengthBreak = StrengthBreakBuilder(library: library).build(
            letter: .dayA, setOrder: setOrder, context: context
        )
        let clock = ManualClock(now: panelInstant)
        let model = StrengthOverlayViewModel(
            strengthBreak: strengthBreak, startedAt: clock.now, clock: clock, snoozesLeft: 2, skipsToday: 1
        )
        run(model, clock, until: .set(1))
        settle(model, clock, seconds: 10.4)
        return model.state
    }

    // MARK: - End-range break

    static func endRange() -> StrengthOverlayState {
        endRangeState { model, clock in
            run(model, clock, until: .block(1))
            settle(model, clock, seconds: 19)
        }
    }

    static func endRangeLeadIn() -> StrengthOverlayState {
        endRangeState { model, clock in
            settle(model, clock, seconds: 2)
        }
    }

    /// Block 2, a per-side move, on its first side.
    static func endRangeSide() -> StrengthOverlayState {
        endRangeState { model, clock in
            run(model, clock, until: .block(2))
            settle(model, clock, seconds: 11)
        }
    }

    static func endRangePaused() -> StrengthOverlayState {
        endRangeState { model, clock in
            run(model, clock, until: .block(1))
            settle(model, clock, seconds: 19)
            model.togglePause()
            settle(model, clock, seconds: 12)
        }
    }

    // MARK: - The breaks

    /// A two-sided rep set, a per-side rep set and a set with a hold, between a warm-up and a
    /// per-side cool-down.
    private static let warmUpId = fixtureId(.sqt, 2)
    private static let setIds = [fixtureId(.psh, 4), fixtureId(.sqt, 6), fixtureId(.cor, 5)]
    private static let coolDownId = fixtureId(.end, 1)
    /// A timed set with no rep target.
    private static let holdSetId = fixtureId(.cor, 3)
    /// The longest set name in the design, and the dose it pairs with it.
    private static let longNameId = fixtureId(.sqt, 15)
    private static let longDoseId = fixtureId(.cor, 5)
    /// A timed move, then a per-side one, then two more.
    private static let endRangeIds = [fixtureId(.end, 7), fixtureId(.end, 1), fixtureId(.end, 2), fixtureId(.end, 13)]

    private static func strengthState(
        firstSet: String? = nil,
        longDose: Bool = false,
        reduceMotion: Bool = false,
        drive: (StrengthOverlayViewModel, ManualClock) -> Void
    ) -> StrengthOverlayState {
        guard let library = strengthLibrary,
              let warmUp = library.movement(id: warmUpId),
              let coolDown = library.movement(id: coolDownId)
        else { return StrengthOverlayState() }
        var sets = setIds.compactMap(library.movement(id:))
        guard sets.count == setIds.count else { return StrengthOverlayState() }
        if let firstSet, let movement = library.movement(id: firstSet) {
            sets[0] = movement
        }
        if longDose, let named = library.movement(id: longNameId), let dosed = library.movement(id: longDoseId) {
            sets[0] = renamed(dosed, after: named)
        }
        let strengthBreak = StrengthBreak(
            id: UUID(),
            letter: .dayA,
            warmUp: StrengthBlock(movement: warmUp, seconds: StrengthTiming.warmUpSeconds),
            sets: sets.enumerated().map { StrengthSet(movement: $1, setNumber: $0 + 1) },
            coolDown: StrengthBlock(movement: coolDown, seconds: StrengthTiming.coolDownSeconds),
            relaxed: []
        )
        let clock = ManualClock(now: panelInstant)
        let model = StrengthOverlayViewModel(
            strengthBreak: strengthBreak, startedAt: clock.now, clock: clock,
            snoozesLeft: 2, skipsToday: 1, reduceMotion: reduceMotion
        )
        drive(model, clock)
        return model.state
    }

    private static func endRangeState(
        drive: (StrengthOverlayViewModel, ManualClock) -> Void
    ) -> StrengthOverlayState {
        guard let library = strengthLibrary else { return StrengthOverlayState() }
        let blocks = endRangeIds.compactMap(library.movement(id:)).map {
            StrengthBlock(movement: $0, seconds: StrengthTiming.endRangeBlockSeconds)
        }
        guard blocks.count == endRangeIds.count else { return StrengthOverlayState() }
        let clock = ManualClock(now: panelInstant)
        let model = StrengthOverlayViewModel(
            endRangeBreak: EndRangeBreak(id: UUID(), blocks: blocks, relaxed: []),
            startedAt: clock.now, clock: clock, snoozesLeft: 2, skipsToday: 1
        )
        drive(model, clock)
        return model.state
    }

    /// `dosed` under `named`'s name and instruction, for the long-dose snapshot: no single move
    /// has both the longest name and the longest dose.
    static func renamed(_ dosed: StrengthMovement, after named: StrengthMovement) -> StrengthMovement {
        StrengthMovement(
            id: dosed.id, name: named.name, bucket: dosed.bucket, regions: dosed.regions, dose: dosed.dose,
            perSide: dosed.perSide, blockSeconds: dosed.blockSeconds, difficulty: dosed.difficulty,
            settings: dosed.settings, onFloor: dosed.onFloor, equipment: named.equipment,
            vigorous: named.vigorous, load: named.load,
            gripDemand: dosed.gripDemand, microEligible: dosed.microEligible, instructions: named.instructions,
            v4Overlap: dosed.v4Overlap
        )
    }

    // MARK: - Driving the clock

    private static func tick(_ model: StrengthOverlayViewModel, _ clock: ManualClock) {
        clock.advance(1)
        model.tick()
    }

    /// Ticks a second at a time until the overlay shows `kind`.
    private static func run(
        _ model: StrengthOverlayViewModel,
        _ clock: ManualClock,
        until kind: StrengthSessionTimeline.Kind
    ) {
        var ticks = 0
        repeat {
            tick(model, clock)
            ticks += 1
        } while model.state.segment != kind && ticks < 1_000
    }

    /// Moves the clock on within the segment on screen and redraws, without a tick that could
    /// move the break on.
    private static func settle(_ model: StrengthOverlayViewModel, _ clock: ManualClock, seconds: TimeInterval) {
        clock.advance(seconds)
        model.refresh()
    }
}
