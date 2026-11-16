import XCTest
@testable import movez

/// The bundled strength library, loaded once for every strength builder test.
enum StrengthTestSupport {
    static let library: StrengthLibrary = {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: RoutineTestSupport.library)
        } catch {
            fatalError("Bundled strength library failed to load: \(error)")
        }
    }()

    static func movement(_ id: String) -> StrengthMovement {
        guard let movement = library.movement(id: id) else { fatalError("no strength movement \(id)") }
        return movement
    }

    /// Everything a user could own, with every difficulty-3 pattern open, so that the rules and
    /// not the settings are what limit the draw.
    static func everythingContext(seed: UInt64) -> StrengthContext {
        var context = StrengthContext()
        context.equipment = Set(StrengthEquipment.allCases)
        context.difficultyCap = 3
        context.unlockedBuckets = Set(StrengthBucket.allCases)
        context.seed = seed
        return context
    }

    /// The set orders a day can produce: the first break, the two later shapes and the arm break
    /// for each letter.
    static var plans: [(letter: StrengthDayLetter, order: [StrengthSetSlot])] {
        StrengthDayLetter.allCases.flatMap { letter in
            StrengthDayPlanner.replay(letter: letter, breaks: 4, priorLead: nil, armIndex: 3).orders.map { (letter, $0) }
        }
    }

    /// A day's arm break, as the planner orders it.
    static func armOrder(_ letter: StrengthDayLetter) -> [StrengthSetSlot] {
        StrengthDayPlanner.replay(letter: letter, breaks: 4, priorLead: nil, armIndex: 3).orders[3]
    }
}

final class StrengthBreakBuilderTests: XCTestCase {
    private var library: StrengthLibrary { StrengthTestSupport.library }
    private var builder: StrengthBreakBuilder { StrengthBreakBuilder(library: library) }

    private func build(
        letter: StrengthDayLetter = .dayA,
        order: [StrengthSetSlot]? = nil,
        seed: UInt64,
        configure: (inout StrengthContext) -> Void = { _ in }
    ) -> StrengthBreak {
        var context = StrengthTestSupport.everythingContext(seed: seed)
        configure(&context)
        let setOrder = order ?? StrengthDayPlanner.replay(letter: letter, breaks: 1, priorLead: nil).orders[0]
        return builder.build(letter: letter, setOrder: setOrder, context: context)
    }

    /// Every plan the planner can produce, built across a spread of seeds.
    private func everyPlan(seeds: Int = 60, configure: (inout StrengthContext) -> Void = { _ in }) -> [StrengthBreak] {
        StrengthTestSupport.plans.flatMap { plan in
            (0..<seeds).map { seed in
                build(letter: plan.letter, order: plan.order, seed: UInt64(seed &* 7_919 &+ 3), configure: configure)
            }
        }
    }

    private func isArmBreak(_ strengthBreak: StrengthBreak) -> Bool {
        strengthBreak.sets.allSatisfy { $0.movement.bucket == strengthBreak.letter.armBucket }
    }

    private func workingMoves(_ strengthBreak: StrengthBreak) -> [StrengthMovement] {
        var seen = Set<String>()
        return strengthBreak.sets.map(\.movement).filter { seen.insert($0.id).inserted }
    }

    // MARK: - Patterns and order

    func testTheADayFirstBreakIsSquatPushCore() {
        for seed in 0..<100 {
            let strengthBreak = build(letter: .dayA, seed: UInt64(seed))
            XCTAssertEqual(strengthBreak.sets.map(\.movement.bucket), [.sqt, .psh, .cor])
            XCTAssertEqual(strengthBreak.sets.map(\.setNumber), [1, 2, 3])
            XCTAssertEqual(strengthBreak.letter, .dayA)
        }
    }

    func testTheBDayFirstBreakIsHingePullCore() {
        for seed in 0..<100 {
            XCTAssertEqual(build(letter: .dayB, seed: UInt64(seed)).sets.map(\.movement.bucket), [.hng, .pul, .cor])
        }
    }

    /// Later breaks follow the planner's order, and the pattern done twice is one move done twice.
    func testLaterBreaksFollowThePlannersOrderAndRepeatTheLeadMove() {
        for letter in StrengthDayLetter.allCases {
            let orders = StrengthDayPlanner.replay(letter: letter, breaks: 4, priorLead: nil).orders
            for order in orders.dropFirst() {
                for seed in 0..<80 {
                    let strengthBreak = build(letter: letter, order: order, seed: UInt64(seed &* 31 &+ 1))
                    XCTAssertEqual(strengthBreak.sets.map(\.movement.bucket), order.map(StrengthBreakBuilder.bucket(for:)))
                    XCTAssertEqual(strengthBreak.sets[0].movement.id, strengthBreak.sets[2].movement.id)
                    XCTAssertNotEqual(strengthBreak.sets[0].movement.id, strengthBreak.sets[1].movement.id)
                }
            }
        }
    }

    // MARK: - Arm break

    /// Two sets of one arm move and a third of a different one, all from the day's arm bucket.
    func testTheArmBreakIsOneArmMoveTwiceThenADifferentOne() {
        for letter in StrengthDayLetter.allCases {
            let order = StrengthTestSupport.armOrder(letter)
            XCTAssertEqual(order, [.arm(letter.armBucket), .arm(letter.armBucket), .armAlternate(letter.armBucket)])
            for kit in [Set<StrengthEquipment>(), [.dumbbells], [.dumbbells, .kettlebell]] {
                for seed in 0..<80 {
                    let strengthBreak = build(letter: letter, order: order, seed: UInt64(seed &* 13 &+ 5)) { $0.equipment = kit }
                    let sets = strengthBreak.sets.map(\.movement)
                    XCTAssertEqual(sets.map(\.bucket), Array(repeating: letter.armBucket, count: 3))
                    XCTAssertEqual(sets[0].id, sets[1].id)
                    XCTAssertNotEqual(sets[0].id, sets[2].id, "\(letter) \(kit): \(sets.map(\.id))")
                    XCTAssertFalse(strengthBreak.relaxed.contains { $0.rule == .vigorous }, "\(sets.map(\.id))")
                }
            }
        }
        XCTAssertEqual(StrengthDayLetter.dayA.armBucket, .tri)
        XCTAssertEqual(StrengthDayLetter.dayB.armBucket, .bic)
    }

    /// A bodyweight-only user still has two different biceps moves for a pull day's arm break.
    func testABodyweightOnlyArmBreakHasTwoDifferentBicepsMoves() {
        var seen = Set<String>()
        for seed in 0..<80 {
            let strengthBreak = build(letter: .dayB, order: StrengthTestSupport.armOrder(.dayB), seed: UInt64(seed)) {
                $0.equipment = []
            }
            let ids = strengthBreak.sets.map(\.movement.id)
            XCTAssertEqual(Set(ids).count, 2, "\(ids)")
            XCTAssertTrue(strengthBreak.sets.allSatisfy { $0.movement.isBodyweight }, "\(ids)")
            XCTAssertEqual(strengthBreak.relaxed, [], "\(ids)")
            seen.formUnion(ids)
        }
        XCTAssertEqual(seen, ["BIC-03", "BIC-06"])
    }

    func testTheArmBreaksWarmUpIsFromThePushOrPullPatternAndItsCoolDownFromTheArmRegions() {
        for letter in StrengthDayLetter.allCases {
            for seed in 0..<80 {
                let strengthBreak = build(letter: letter, order: StrengthTestSupport.armOrder(letter), seed: UInt64(seed))
                XCTAssertEqual(strengthBreak.warmUp.movement.bucket, letter == .dayA ? .psh : .pul)
                XCTAssertTrue(StrengthBreakBuilder.isWarmUpShaped(strengthBreak.warmUp.movement), strengthBreak.warmUp.movement.id)
                XCTAssertFalse(
                    StrengthBreakBuilder.armCoolDownRegions.isDisjoint(with: strengthBreak.coolDown.movement.regions),
                    "\(strengthBreak.coolDown.movement.id) stretches none of the arm break's regions"
                )
                XCTAssertFalse(strengthBreak.relaxed.contains { $0.slot == .coolDown || $0.slot == .warmUp })
            }
        }
        XCTAssertEqual(StrengthBreakBuilder.armCoolDownRegions, [.shoulder, .chest, .arm, .wristForearm])
    }

    // MARK: - Vigorous sets

    /// With any kit, no working set is a light bodyweight move; the warm-ups still are.
    func testWithKitEveryWorkingSetIsVigorous() {
        var lightWarmUps = 0
        for kit in [Set<StrengthEquipment>([.dumbbells]), [.dumbbells, .kettlebell], [.kettlebell]] {
            for strengthBreak in everyPlan(configure: { $0.equipment = kit }) {
                // A kettlebell-only user never gets an arm break, whose buckets have no kettlebell
                // move; the planner keeps them on pattern breaks.
                if kit == [.kettlebell], isArmBreak(strengthBreak) { continue }
                XCTAssertFalse(strengthBreak.relaxed.contains { $0.rule == .vigorous }, "\(kit): \(strengthBreak.movementIds)")
                for set in strengthBreak.sets {
                    XCTAssertTrue(set.movement.vigorous, "\(kit): \(set.movement.id) is a light working set")
                }
                if !strengthBreak.warmUp.movement.vigorous { lightWarmUps += 1 }
            }
        }
        XCTAssertGreaterThan(lightWarmUps, 0, "light bodyweight moves are still warm-ups")
    }

    func testBodyweightOnlyUsersStillDrawLightMovesForWorkingSets() {
        let breaks = everyPlan { $0.equipment = [] }
        XCTAssertTrue(breaks.contains { $0.sets.contains { !$0.movement.vigorous } })
        XCTAssertFalse(breaks.contains { $0.relaxed.contains { $0.rule == .vigorous } })
    }

    /// With only light moves left in a pattern, the rule is let go of and the break says so.
    func testTheVigorousRuleIsLetGoOfWhenNothingVigorousIsLeft() {
        let vigorousTriceps = Set(library.movements(in: .tri).filter(\.vigorous).map(\.id))
        let strengthBreak = build(letter: .dayA, order: StrengthTestSupport.armOrder(.dayA), seed: 3) {
            $0.equipment = [.dumbbells]
            $0.excluded = vigorousTriceps
            $0.usedStrengthIdsToday = vigorousTriceps
        }
        XCTAssertTrue(strengthBreak.relaxed.contains { $0.rule == .vigorous && $0.slot == .set(1) })
        XCTAssertFalse(strengthBreak.relaxed.contains { $0.rule == .excluded }, "light moves come before excluded ones")
        XCTAssertTrue(strengthBreak.sets.allSatisfy { !$0.movement.vigorous })
    }

    // MARK: - Warm-up and cool-down

    func testTheWarmUpIsABodyweightStandingEasyTwoSidedMoveFromTheFirstPattern() {
        for strengthBreak in everyPlan() {
            let warmUp = strengthBreak.warmUp
            let expected = isArmBreak(strengthBreak)
                ? strengthBreak.letter.armWarmUpPattern : strengthBreak.sets[0].movement.bucket
            XCTAssertEqual(warmUp.movement.bucket, expected)
            XCTAssertTrue(warmUp.movement.isBodyweight, "\(warmUp.movement.id) needs kit")
            XCTAssertFalse(warmUp.movement.onFloor, "\(warmUp.movement.id) is on the floor")
            XCTAssertEqual(warmUp.movement.difficulty, 1, "\(warmUp.movement.id)")
            XCTAssertFalse(warmUp.movement.perSide, "\(warmUp.movement.id) is per-side")
            XCTAssertEqual(warmUp.seconds, 30)
            XCTAssertFalse(strengthBreak.sets.map(\.movement.id).contains(warmUp.movement.id))
        }
    }

    func testTheCoolDownIsAnEndMoveStretchingARegionTheSetsWorked() {
        for strengthBreak in everyPlan() {
            let coolDown = strengthBreak.coolDown
            XCTAssertEqual(coolDown.movement.bucket, .end)
            let worked = isArmBreak(strengthBreak) ? StrengthBreakBuilder.armCoolDownRegions : strengthBreak.workedRegions
            XCTAssertFalse(
                worked.isDisjoint(with: coolDown.movement.regions),
                "\(coolDown.movement.id) stretches nothing the sets worked"
            )
            XCTAssertEqual(coolDown.seconds, 30)
            XCTAssertEqual(coolDown.secondsPerSide, coolDown.perSide ? 15 : 30)
        }
    }

    // MARK: - Per-break limits and kit

    func testAtMostOnePerSideOneFloorAndOneGripWorkingMove() {
        for strengthBreak in everyPlan() {
            let moves = workingMoves(strengthBreak)
            let ids = strengthBreak.sets.map(\.movement.id)
            XCTAssertLessThanOrEqual(moves.filter(\.perSide).count, 1, "per-side: \(ids)")
            XCTAssertLessThanOrEqual(moves.filter(\.onFloor).count, 1, "floor: \(ids)")
            XCTAssertLessThanOrEqual(moves.filter(\.gripDemand).count, 1, "grip: \(ids)")
        }
    }

    func testNoWallMoveWithTheWallOff() {
        var sawWall = false
        for strengthBreak in everyPlan() where strengthBreak.movementIds.contains(where: { isWall($0) }) {
            sawWall = true
        }
        XCTAssertTrue(sawWall, "with the wall on, a wall move should come up somewhere")

        for strengthBreak in everyPlan(configure: { $0.solidWallNearby = false }) {
            XCTAssertFalse(strengthBreak.movementIds.contains(where: { isWall($0) }), "\(strengthBreak.movementIds)")
        }
    }

    private func isWall(_ id: String) -> Bool {
        StrengthTestSupport.movement(id).settings.contains(.wall)
    }

    func testKettlebellOnlyWhenOwnedAndListed() {
        for strengthBreak in everyPlan(configure: { $0.equipment = [.kettlebell] }) {
            for id in strengthBreak.movementIds {
                let movement = StrengthTestSupport.movement(id)
                XCTAssertTrue(movement.isBodyweight || movement.equipment.contains(.kettlebell), "\(id) does not list the kettlebell")
            }
        }
        for strengthBreak in everyPlan(configure: { $0.equipment = [.dumbbells] }) {
            for id in strengthBreak.movementIds {
                let movement = StrengthTestSupport.movement(id)
                XCTAssertTrue(movement.isBodyweight || movement.equipment.contains(.dumbbells), "\(id) needs a kettlebell")
            }
        }
    }

    func testNoEquipmentMeansBodyweightOnly() {
        for strengthBreak in everyPlan(configure: { $0.equipment = [] }) {
            for id in strengthBreak.movementIds {
                XCTAssertTrue(StrengthTestSupport.movement(id).isBodyweight, "\(id) needs kit")
            }
        }
    }

    // MARK: - Today, difficulty

    /// A Movement break that served the movement-library twin of a strength move rules that move
    /// out of the day's strength breaks, through `CrossModeUsage`.
    func testAMoveServedInAMovementBreakIsNotDrawn() throws {
        let usage = CrossModeUsage(movementLibrary: RoutineTestSupport.library, strengthLibrary: library)
        let twins = library.movements.filter { $0.v4Overlap?.kind == .same }
        XCTAssertFalse(twins.isEmpty)
        let used = usage.used(movementIds: Set(twins.compactMap { $0.v4Overlap?.id }), strengthIds: [])
        XCTAssertTrue(used.strengthIds.isSuperset(of: twins.map(\.id)))

        for strengthBreak in everyPlan(configure: { $0.usedStrengthIdsToday = used.strengthIds }) {
            XCTAssertFalse(strengthBreak.relaxed.contains { $0.rule == .servedToday }, "\(strengthBreak.movementIds)")
            XCTAssertTrue(used.strengthIds.isDisjoint(with: strengthBreak.movementIds), "\(strengthBreak.movementIds)")
        }
    }

    /// With half of every pattern served today, nothing served comes back unless the break says
    /// it had to let that rule go.
    func testNothingServedTodayIsDrawn() {
        let served = Set(library.movements.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element.id))
        var strict = 0
        for strengthBreak in everyPlan(configure: { $0.usedStrengthIdsToday = served }) {
            let relaxedSlots = Set(strengthBreak.relaxed.filter { $0.rule == .servedToday }.map(\.slot))
            if relaxedSlots.isEmpty { strict += 1 }
            let slots: [(StrengthRelaxation.Slot, String)] = [(.warmUp, strengthBreak.warmUp.movement.id)]
                + strengthBreak.sets.map { (.set($0.setNumber), $0.movement.id) }
                + [(.coolDown, strengthBreak.coolDown.movement.id)]
            for (slot, id) in slots where !relaxedSlots.contains(slot) {
                // A repeated set reuses an earlier set's move, so it is judged by that set's slot.
                let drawnAt = strengthBreak.sets.first { $0.movement.id == id }.map { StrengthRelaxation.Slot.set($0.setNumber) }
                if let drawnAt, drawnAt != slot, relaxedSlots.contains(drawnAt) { continue }
                XCTAssertFalse(served.contains(id), "\(id) in \(slot) was already served today")
            }
        }
        XCTAssertGreaterThan(strict, 0)
    }

    func testDifficultyStaysWithinTheCap() {
        for cap in 1...2 {
            for strengthBreak in everyPlan(configure: { $0.difficultyCap = cap }) {
                for id in strengthBreak.movementIds {
                    XCTAssertLessThanOrEqual(StrengthTestSupport.movement(id).difficulty, cap, "\(id) at cap \(cap)")
                }
            }
        }
    }

    func testDifficultyThreeOnlyInUnlockedPatterns() {
        var sawSquatThree = false
        for strengthBreak in everyPlan(configure: { $0.unlockedBuckets = [.sqt] }) {
            for id in strengthBreak.movementIds where StrengthTestSupport.movement(id).difficulty == 3 {
                XCTAssertEqual(StrengthTestSupport.movement(id).bucket, .sqt, "\(id) is locked")
                sawSquatThree = true
            }
        }
        XCTAssertTrue(sawSquatThree, "an unlocked pattern's difficulty-3 moves should come up")

        for strengthBreak in everyPlan(configure: { $0.unlockedBuckets = [] }) {
            for id in strengthBreak.movementIds {
                XCTAssertLessThan(StrengthTestSupport.movement(id).difficulty, 3, "\(id) is locked")
            }
        }
    }

    // MARK: - Weighting

    /// Measured on the pattern breaks: the arm break's sets are arm moves under any focus, and
    /// where it falls is the planner's part of "More arms".
    func testAFocusRegionIsWeightedUp() {
        func armShare(_ focus: StrengthFocus) -> Double {
            let breaks = everyPlan(seeds: 150) { $0.focus = focus }.filter { !isArmBreak($0) }
            let moves = breaks.flatMap(workingMoves)
            return Double(moves.filter { $0.regions.contains(.arm) }.count) / Double(moves.count)
        }
        XCTAssertGreaterThan(armShare(.moreArms), armShare(.none) * 1.3)
    }

    func testRecentlyServedMovesAreWeightedDown() {
        func squatShare(of id: String, recency: [String: Double]) -> Double {
            let breaks = (0..<600).map { seed in build(letter: .dayA, seed: UInt64(seed)) { $0.recency = recency } }
            return Double(breaks.filter { $0.sets[0].movement.id == id }.count) / Double(breaks.count)
        }
        let fresh = build(letter: .dayA, seed: 1).sets[0].movement.id
        XCTAssertLessThan(squatShare(of: fresh, recency: [fresh: 3]), squatShare(of: fresh, recency: [:]) * 0.5)
    }

    // MARK: - Planned seconds

    func testATwoSidedRepSetIsRepsTimesThreePlusTheGrace() {
        let set = StrengthSet(movement: StrengthTestSupport.movement("PSH-04"), setNumber: 1)
        XCTAssertEqual(set.dose, "12 reps")
        XCTAssertEqual(set.reps, 12)
        XCTAssertEqual(set.plannedSeconds, 41)
    }

    func testAPerSideRepSetCountsBothSidesAndTheSwitchCue() {
        let set = StrengthSet(movement: StrengthTestSupport.movement("SQT-07"), setNumber: 2)
        XCTAssertEqual(set.dose, "10/side")
        XCTAssertEqual(set.reps, 10)
        XCTAssertTrue(set.perSide)
        XCTAssertEqual(set.plannedSeconds, 68)
    }

    func testAHoldDoseAddsTheHoldToEveryRep() {
        let set = StrengthSet(movement: StrengthTestSupport.movement("COR-05"), setNumber: 3)
        XCTAssertEqual(set.dose, "12 reps, alternating, 2 s hold")
        XCTAssertEqual(set.reps, 12)
        XCTAssertEqual(set.holdSeconds, 2)
        XCTAssertEqual(set.plannedSeconds, (3 + 2) * 12 + 5)
    }

    /// The slow multi-part moves, timed holds and seconds doses have no meter and run on the
    /// library's own length.
    func testNoMeterSetsRunOnTheirBlockSeconds() {
        let halfGetUp = StrengthTestSupport.movement("COR-16")
        let set = StrengthSet(movement: halfGetUp, setNumber: 1)
        XCTAssertNil(set.reps)
        XCTAssertEqual(set.plannedSeconds, halfGetUp.blockSeconds)

        for id in ["PUL-01", "HNG-17", "COR-11", "COR-14", "COR-15", "COR-16", "SQT-16", "COR-04", "PUL-04"] {
            let movement = StrengthTestSupport.movement(id)
            let set = StrengthSet(movement: movement, setNumber: 1)
            XCTAssertFalse(set.hasMeter, "\(id) (\(movement.dose)) should have no meter")
            XCTAssertEqual(set.plannedSeconds, movement.blockSeconds, id)
        }
    }

    /// Every other working dose is counted by the meter: the six slow moves are the only rep
    /// doses below the library's working range.
    func testEveryOtherRepDoseHasAMeter() {
        let slow: Set<String> = ["PUL-01", "HNG-17", "COR-11", "COR-14", "COR-15", "COR-16"]
        // The arm buckets' doses too, which the arm break (DECISIONS 70) serves as working sets.
        let working: Set<StrengthBucket> = [.sqt, .hng, .psh, .pul, .bic, .tri, .cor]
        for movement in library.movements where working.contains(movement.bucket) && !slow.contains(movement.id) {
            let isTimed = movement.dose.replacingOccurrences(of: " s hold", with: "").contains(" s")
            XCTAssertEqual(StrengthSet(movement: movement, setNumber: 1).hasMeter, !isTimed, "\(movement.id) \(movement.dose)")
        }
    }

    func testTheWholeBreakIsTheSumOfItsPartsFromTheConstants() {
        for strengthBreak in everyPlan(seeds: 10) {
            let sets = strengthBreak.sets.reduce(0) { $0 + $1.plannedSeconds }
            let expected = StrengthTiming.leadInSeconds + StrengthTiming.warmUpSeconds
                + StrengthTiming.leadInSeconds + sets + 2 * StrengthTiming.restSeconds + StrengthTiming.coolDownSeconds
            XCTAssertEqual(strengthBreak.plannedSeconds, expected)
            XCTAssertEqual(PlannedBreak.strength(strengthBreak).plannedSeconds, expected)
        }
        let constants = [
            StrengthTiming.repPaceSeconds, StrengthTiming.restSeconds, StrengthTiming.warmUpSeconds,
            StrengthTiming.coolDownSeconds, StrengthTiming.leadInSeconds
        ]
        XCTAssertEqual(constants, [3, 45, 30, 30, 5])

        // Two 12-rep sets around a 10-a-side set: 5 + 30 + 5 + (41 + 68 + 41) + 2 × 45 + 30.
        let push = StrengthTestSupport.movement("PSH-04")
        let fixture = StrengthBreak(
            id: UUID(),
            letter: .dayA,
            warmUp: StrengthBlock(movement: StrengthTestSupport.movement("SQT-01"), seconds: StrengthTiming.warmUpSeconds),
            sets: [
                StrengthSet(movement: push, setNumber: 1),
                StrengthSet(movement: StrengthTestSupport.movement("SQT-07"), setNumber: 2),
                StrengthSet(movement: push, setNumber: 3)
            ],
            coolDown: StrengthBlock(movement: StrengthTestSupport.movement("END-26"), seconds: StrengthTiming.coolDownSeconds),
            relaxed: []
        )
        XCTAssertEqual(fixture.plannedSeconds, 310)
        XCTAssertEqual(fixture.movementIds, ["SQT-01", "PSH-04", "SQT-07", "END-26"])
    }

    func testAPlannedBreakReportsItsKindAndIds() {
        let strengthBreak = build(letter: .dayB, seed: 4)
        let planned = PlannedBreak.strength(strengthBreak)
        XCTAssertEqual(planned.kind, .strengthB)
        XCTAssertEqual(planned.movementIds, strengthBreak.movementIds)
        XCTAssertEqual(PlannedBreak.strength(build(letter: .dayA, seed: 4)).kind, .strengthA)
    }

    // MARK: - Determinism and fallback

    func testTheSameContextBuildsTheIdenticalBreak() {
        for plan in StrengthTestSupport.plans {
            for seed in 0..<20 {
                let first = build(letter: plan.letter, order: plan.order, seed: UInt64(seed)) { $0.focus = .moreCore }
                let second = build(letter: plan.letter, order: plan.order, seed: UInt64(seed)) { $0.focus = .moreCore }
                XCTAssertEqual(first, second)
            }
        }
        let ids = Set((0..<40).map { build(seed: UInt64($0)).movementIds })
        XCTAssertGreaterThan(ids.count, 10, "different seeds should build different breaks")
    }

    /// A day that has served and excluded everything still gets a full break, and says which
    /// rules it let go of.
    func testAnExhaustedPoolStillBuildsAFullBreak() {
        let everything = Set(library.movements.map(\.id))
        for plan in StrengthTestSupport.plans {
            let strengthBreak = build(letter: plan.letter, order: plan.order, seed: 9) { context in
                context.usedStrengthIdsToday = everything
                context.excluded = everything
                context.equipment = []
                context.difficultyCap = 1
            }
            XCTAssertEqual(strengthBreak.sets.count, 3)
            XCTAssertEqual(strengthBreak.sets.map(\.movement.bucket), plan.order.map(StrengthBreakBuilder.bucket(for:)))
            XCTAssertEqual(strengthBreak.coolDown.movement.bucket, .end)
            let rules = Set(strengthBreak.relaxed.map(\.rule))
            XCTAssertTrue(rules.contains(.servedToday))
            XCTAssertTrue(rules.contains(.excluded))
            XCTAssertTrue(strengthBreak.relaxed.contains { $0.slot == .warmUp })
            XCTAssertTrue(strengthBreak.relaxed.contains { $0.slot == .coolDown })
        }
    }

    /// A short pool lets the per-break limits go before anything served today comes back.
    func testTheFallbackLetsTheBreakLimitsGoFirst() {
        XCTAssertEqual(StrengthBreakBuilder.workingLadder.first, .breakLimits)
        XCTAssertEqual(
            StrengthBreakBuilder.workingLadder.prefix(3), [.breakLimits, .servedToday, .vigorous],
            "repeating a vigorous move comes before serving a light one"
        )
        XCTAssertEqual(StrengthBreakBuilder.warmUpLadder.first, .warmUpShape)
        XCTAssertEqual(StrengthBreakBuilder.coolDownLadder.first, .coolDownRegion)
        XCTAssertEqual(StrengthBreakBuilder.workingLadder.last, .anything)
    }
}
