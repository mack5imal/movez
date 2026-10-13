import XCTest
@testable import movez

final class RoutineBuilderTests: XCTestCase {
    private var library: MovementLibrary { RoutineTestSupport.library }

    // MARK: - Validity at scale

    func testOneThousandGeneratedRoutinesValidate() {
        var count = 0
        var problems: [String] = []
        for day in 0..<125 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 8
            options.focus = Focus.allCases[day % Focus.allCases.count]
            options.equipment = day.isMultiple(of: 3) ? [.band, .ball] : []
            for routine in RoutineTestSupport.simulateDay(seed: UInt64(day &* 104_729 &+ 11), options: options) {
                count += 1
                let found = RoutineValidator.validate(routine, library: library)
                if !found.isEmpty {
                    problems.append("day \(day) · \(routine.movementIds): \(found.joined(separator: "; "))")
                }
            }
        }
        XCTAssertEqual(count, 1_000)
        XCTAssertEqual(problems.count, 0, problems.prefix(5).joined(separator: "\n"))
    }

    /// No movement is exempt: walk lap, distance gaze and diaphragmatic breathing used to recur
    /// freely, and were among the most-served movements because of it.
    func testNoMovementRepeatsWithinADay() {
        for day in 0..<40 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 8
            let routines = RoutineTestSupport.simulateDay(seed: UInt64(day &* 7_919 &+ 3), options: options)
            var seen: [String: Int] = [:]
            for id in routines.flatMap(\.movementIds) {
                seen[id, default: 0] += 1
            }
            let repeated = seen.filter { $0.value > 1 }.keys.sorted()
            XCTAssertEqual(repeated, [], "day \(day) repeated \(repeated)")
        }
    }

    // MARK: - Families

    /// A single-leg calf raise hold followed by a single-leg calf raise is the same exercise twice,
    /// whatever buckets they are filed under.
    func testNoBreakHoldsTwoMovementsOfOneFamily() {
        for seed in 0..<1_000 {
            let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 29 &+ 5)) { $0.difficultyCap = 3 }
            let keys = routine.blocks.map(\.movement.familyKey)
            XCTAssertEqual(Set(keys).count, keys.count, "seed \(seed): \(routine.movementIds)")
        }
    }

    func testNoFamilyRepeatsWithinADay() {
        for day in 0..<40 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 8
            let routines = RoutineTestSupport.simulateDay(seed: UInt64(day &* 7_919 &+ 3), options: options)
            var seen: [String: Int] = [:]
            for block in routines.flatMap(\.blocks) {
                seen[block.movement.familyKey, default: 0] += 1
            }
            let repeated = seen.filter { $0.value > 1 }.keys.sorted()
            XCTAssertEqual(repeated, [], "day \(day) repeated \(repeated)")
        }
    }

    /// Served yesterday, one hip-flexor stretch makes the others rarer today too.
    func testAFamilyMemberServedYesterdayMakesItsSiblingsRarer() {
        let hipFlexors: Set<String> = ["FLX-01", "FLX-02", "FLX-03", "BAL-18"]
        func share(recency: [String: Double]) -> Double {
            var hits = 0
            let draws = 2_000
            for seed in 0..<draws {
                let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 41 &+ 9)) { $0.recency = recency }
                if !hipFlexors.isDisjoint(with: routine.movementIds) { hits += 1 }
            }
            return Double(hits) / Double(draws)
        }
        let fresh = share(recency: [:])
        let afterOne = share(recency: ["FLX-01": Recency.weight(daysAgo: 1)])
        XCTAssertLessThan(afterOne, fresh * 0.6, "fresh \(fresh), after FLX-01 yesterday \(afterOne)")
    }

    // MARK: - Shape

    func testEveryRoutineHasTheSameShape() {
        for seed in 0..<200 {
            let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 13 &+ 1))
            let buckets = routine.buckets
            XCTAssertEqual(buckets.count, 5)
            XCTAssertEqual(buckets.first, .cir, "every routine opens on circulation")
            XCTAssertEqual(Set(buckets[1...3]), [.bal, .flx, .str], "seed \(seed): \(buckets)")
            XCTAssertTrue(Routine.closers.contains(buckets[4]), "seed \(seed) closes on \(buckets[4])")
            XCTAssertTrue(routine.blocks.allSatisfy { $0.seconds == 60 })
            XCTAssertEqual(routine.totalSeconds, 325, "five minutes of movement and five lead-ins")
        }
    }

    func testTheWorkingBlocksComeInEveryOrder() {
        var orders = Set<[Bucket]>()
        for seed in 0..<200 {
            orders.insert(Array(RoutineTestSupport.routine(seed: UInt64(seed &* 19 &+ 3)).buckets[1...3]))
        }
        XCTAssertEqual(orders.count, 6, "only \(orders.count) of the six orders appeared")
    }

    /// The closer is one pool, so each closer movement is about as likely as any other, rather
    /// than each of the three buckets taking a third whatever its size.
    func testTheCloserIsDrawnFromOnePool() {
        var counts: [Bucket: Int] = [:]
        let draws = 2_000
        for seed in 0..<draws {
            let closer = RoutineTestSupport.routine(seed: UInt64(seed &* 7 &+ 11)).buckets[4]
            counts[closer, default: 0] += 1
        }
        let pool = RoutineTestSupport.builder.candidates(for: RoutineContext()).filter { Routine.closers.contains($0.bucket) }
        for bucket in Routine.closers {
            let expected = Double(pool.filter { $0.bucket == bucket }.count) / Double(pool.count)
            let observed = Double(counts[bucket] ?? 0) / Double(draws)
            XCTAssertEqual(observed, expected, accuracy: 0.05, "\(bucket.rawValue) closes \(Int(observed * 100))% of breaks")
        }
    }

    func testStrengthRegionsNeverRepeatInConsecutiveBreaks() {
        for day in 0..<25 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 8
            let routines = RoutineTestSupport.simulateDay(seed: UInt64(day &* 31 &+ 5), options: options)
            for (previous, current) in zip(routines, routines.dropFirst()) {
                let overlap = previous.strengthRegions.intersection(current.strengthRegions)
                XCTAssertTrue(
                    overlap.isEmpty,
                    "day \(day): \(previous.movementIds) and \(current.movementIds) share \(overlap.map(\.rawValue))"
                )
            }
        }
    }

    // MARK: - Variety across days

    /// Thirty days of a few breaks a day, with the history threaded forward the way the
    /// coordinator threads it.
    ///
    /// This is the shape of a real week for someone who takes one or two breaks a day, and it is
    /// where the old builder was at its worst: 39 of the 124 eligible movements ever appeared, and
    /// one circulation movement was in 38% of routines, because selection took whichever movement
    /// was closest to an ideal length and broke ties by id.
    private func simulateMonth(breaksPerDay: Int) -> [Routine] {
        var served: [(id: String, day: Int)] = []
        var routines: [Routine] = []

        for day in 0..<30 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = breaksPerDay
            options.difficultyCap = 3
            options.recency = served.reduce(into: [String: Double]()) { scores, entry in
                scores[entry.id, default: 0] += Recency.weight(daysAgo: day - entry.day)
            }

            let today = RoutineTestSupport.simulateDay(seed: UInt64(day &* 104_729 &+ 17), options: options)
            routines += today
            served += today.flatMap(\.movementIds).map { (id: $0, day: day) }
        }
        return routines
    }

    func testAMonthOfBreaksReachesMostOfTheLibrary() {
        let routines = simulateMonth(breaksPerDay: 2)
        let ids = routines.flatMap(\.movementIds)
        var counts: [String: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }

        XCTAssertEqual(routines.count, 60)
        XCTAssertGreaterThanOrEqual(Set(ids).count, 80, "only \(Set(ids).count) distinct movements in a month")

        let topShare = Double(counts.values.max() ?? 0) / Double(routines.count)
        XCTAssertLessThanOrEqual(topShare, 0.15, "one movement is in \(Int(topShare * 100))% of routines")
    }

    /// Circulation, balance, flexibility and strength each take exactly a fifth of the blocks.
    /// Under the old rules strength was 4% of them.
    func testEachWorkingBucketIsAFifthOfAMonth() {
        let buckets = simulateMonth(breaksPerDay: 3).flatMap(\.buckets)
        for bucket in [Bucket.cir, .bal, .flx, .str] {
            let share = Double(buckets.filter { $0 == bucket }.count) / Double(buckets.count)
            XCTAssertEqual(share, 0.2, accuracy: 0.0001, "\(bucket.rawValue) is \(Int(share * 100))% of a month")
        }
    }

    func testNoRoutineIsServedTwiceInAMonth() {
        let routines = simulateMonth(breaksPerDay: 3)
        var seen: [String: Int] = [:]
        for routine in routines { seen[routine.movementIds.joined(separator: ","), default: 0] += 1 }
        let repeated = seen.filter { $0.value > 1 }.keys.sorted()
        XCTAssertEqual(repeated, [], "repeated routines: \(repeated)")
    }

    /// Yesterday's movements are the ones a user notices coming round again.
    func testYesterdaysMovementsAreRarerThanTheRest() {
        var yesterdayCount = 0
        var total = 0

        for day in 0..<40 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 2
            options.difficultyCap = 3
            let yesterday = RoutineTestSupport.simulateDay(seed: UInt64(day &* 7_919 &+ 5), options: options)
            let served = Set(yesterday.flatMap(\.movementIds))

            options.recency = served.reduce(into: [String: Double]()) { $0[$1] = Recency.weight(daysAgo: 1) }
            let today = RoutineTestSupport.simulateDay(seed: UInt64(day &* 7_919 &+ 6), options: options)

            for id in today.flatMap(\.movementIds) {
                total += 1
                if served.contains(id) { yesterdayCount += 1 }
            }
        }

        let share = Double(yesterdayCount) / Double(total)
        XCTAssertLessThan(share, 0.1, "\(Int(share * 100))% of today came from yesterday")
    }

    // MARK: - Equipment, excludes, focus

    func testNoEquipmentMeansNoEquipmentMovements() {
        for seed in 0..<200 {
            let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 3 &+ 1))
            for block in routine.blocks {
                XCTAssertFalse(block.movement.needsEquipment, "\(block.movement.id) needs equipment")
            }
        }
    }

    func testOwnedEquipmentCanAppear() {
        var used = 0
        for seed in 0..<200 {
            let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 5 &+ 2)) { context in
                context.equipment = Set(Equipment.allCases)
            }
            used += routine.blocks.filter(\.movement.needsEquipment).count
        }
        XCTAssertGreaterThanOrEqual(used, 1, "equipment movements never appeared across 200 routines")
    }

    /// With no wall, no floor and no stairs, a month of breaks never serves a movement that needs
    /// one, and every break still has its five movements.
    func testNothingIsServedThatNeedsWhatTheUserLacks() {
        let none: Set<Requirement> = [.wall, .floor, .stairs]
        for day in 0..<22 {
            var options = RoutineTestSupport.DayOptions()
            options.unavailable = none
            options.difficultyCap = 3
            for routine in RoutineTestSupport.simulateDay(seed: UInt64(day &* 31 &+ 5), options: options) {
                XCTAssertEqual(routine.blocks.count, 5, "the pools stay deep enough to fill every slot")
                for block in routine.blocks {
                    XCTAssertTrue(block.movement.requires.isEmpty, "\(block.movement.id) needs \(block.movement.requires)")
                }
            }
        }
    }

    func testOnlyTheMissingThingIsFilteredOut() {
        var served: Set<String> = []
        for day in 0..<22 {
            var options = RoutineTestSupport.DayOptions()
            options.unavailable = [.stairs]
            for routine in RoutineTestSupport.simulateDay(seed: UInt64(day &* 17 &+ 3), options: options) {
                served.formUnion(routine.movementIds)
            }
        }
        let byId = Dictionary(uniqueKeysWithValues: library.movements.map { ($0.id, $0) })
        XCTAssertFalse(served.contains { byId[$0]?.requires.contains(.stairs) == true })
        XCTAssertTrue(served.contains { byId[$0]?.requires.contains(.floor) == true }, "the floor is still on offer")
    }

    func testExcludedMovementsNeverAppear() {
        let excluded: Set<String> = ["CIR-01", "FLX-01", "STR-01", "BAL-01", "EYE-01", "BRE-01", "HWF-01"]
        for seed in 0..<200 {
            let routine = RoutineTestSupport.routine(seed: UInt64(seed &* 7 &+ 4)) { context in
                context.excluded = excluded
            }
            XCTAssertTrue(Set(routine.movementIds).isDisjoint(with: excluded))
            XCTAssertEqual(RoutineValidator.validate(routine, library: library, excluded: excluded), [])
        }
    }

    func testFocusRaisesTheShareItAsksFor() {
        func blocks(focus: Focus) -> [RoutineBlock] {
            (0..<200).flatMap { seed in
                RoutineTestSupport.routine(seed: UInt64(seed &* 11 &+ 6)) { context in
                    context.focus = focus
                }.blocks
            }
        }

        let baseline = blocks(focus: .none)
        let handsEyes = blocks(focus: .moreHandsEyes)
        let upperBack = blocks(focus: .moreUpperBack)

        let handsEyesRegions: Set<Region> = [.wristForearm, .eyes]
        let baselineHandsEyes = baseline.filter { !Set($0.movement.regions).isDisjoint(with: handsEyesRegions) }.count
        let focusedHandsEyes = handsEyes.filter { !Set($0.movement.regions).isDisjoint(with: handsEyesRegions) }.count
        XCTAssertGreaterThan(focusedHandsEyes, baselineHandsEyes, "more hands and eyes did not raise their share")

        let upperRegions: Set<Region> = [.thoracic, .chest, .shoulder]
        let baselineUpper = baseline.filter { !Set($0.movement.regions).isDisjoint(with: upperRegions) }.count
        let focusedUpper = upperBack.filter { !Set($0.movement.regions).isDisjoint(with: upperRegions) }.count
        XCTAssertGreaterThan(focusedUpper, baselineUpper, "more upper back did not raise the T-spine share")

        let core = blocks(focus: .moreCore)
        let baselineCore = baseline.filter { $0.movement.regions.contains(.lumbarCore) }.count
        let focusedCore = core.filter { $0.movement.regions.contains(.lumbarCore) }.count
        XCTAssertGreaterThan(focusedCore, baselineCore, "more core did not raise the core share")

        RoutineTestSupport.write(
            """
            Bucket distribution over 200 generated routines per condition

            focus        blocks   CIR   FLX   STR   BAL   HWF   EYE   BRE
            \(row("none", baseline))
            \(row("moreHandsEyes", handsEyes))
            \(row("moreUpperBack", upperBack))
            \(row("moreCore", core))

            Wrist/eye blocks   none \(baselineHandsEyes)   moreHandsEyes \(focusedHandsEyes)
            T-spine/Chest/Shoulder blocks   none \(baselineUpper)   moreUpperBack \(focusedUpper)
            L-spine/Core blocks   none \(baselineCore)   moreCore \(focusedCore)
            """,
            to: "routine-distribution.txt"
        )
    }

    private func row(_ label: String, _ blocks: [RoutineBlock]) -> String {
        let counts = Bucket.allCases.map { bucket in
            String(blocks.filter { $0.movement.bucket == bucket }.count).padded(to: 6)
        }
        return label.padded(to: 13) + String(blocks.count).padded(to: 9) + counts.joined()
    }

    // MARK: - Difficulty

    func testDifficultyCaps() {
        for seed in 0..<100 {
            let beginner = RoutineTestSupport.routine(seed: UInt64(seed &* 23 &+ 8)) { $0.difficultyCap = 1 }
            XCTAssertTrue(beginner.blocks.allSatisfy { $0.movement.difficulty == 1 })

            let moderate = RoutineTestSupport.routine(seed: UInt64(seed &* 29 &+ 9)) { $0.difficultyCap = 2 }
            XCTAssertTrue(moderate.blocks.allSatisfy { $0.movement.difficulty <= 2 })

            let advanced = RoutineTestSupport.routine(seed: UInt64(seed &* 31 &+ 10)) { $0.difficultyCap = 3 }
            XCTAssertTrue(advanced.blocks.allSatisfy { $0.movement.difficulty <= 2 }, "Diff 3 appeared without an unlock")
        }
    }

    func testUnlockedDifficultyThreeCanAppear() {
        // Narrow the strength block to STR-29 so the unlock is the only variable under test.
        let otherStrength = library.movements
            .filter { $0.bucket == .str && $0.id != "STR-29" }
            .map(\.id)

        let locked = RoutineTestSupport.routine(seed: 99) { context in
            context.difficultyCap = 3
            context.excluded = Set(otherStrength)
        }
        XCTAssertFalse(locked.movementIds.contains("STR-29"), "Diff 3 served while locked")

        let unlocked = RoutineTestSupport.routine(seed: 99) { context in
            context.difficultyCap = 3
            context.excluded = Set(otherStrength)
            context.unlockedDiff3 = ["STR-29"]
        }
        XCTAssertTrue(unlocked.movementIds.contains("STR-29"), "unlocked Diff 3 never appeared")
    }

    // MARK: - Determinism

    func testSameSeedProducesTheSameRoutine() {
        let first = RoutineTestSupport.routine(seed: 4_242)
        let second = RoutineTestSupport.routine(seed: 4_242)
        XCTAssertEqual(first.movementIds, second.movementIds)
        XCTAssertEqual(first.blocks.map(\.seconds), second.blocks.map(\.seconds))

        let different = RoutineTestSupport.routine(seed: 4_243)
        XCTAssertNotEqual(first.movementIds, different.movementIds)
    }

    func testWritesSampleRoutinesForEvidence() {
        var options = RoutineTestSupport.DayOptions()
        options.breaks = 6
        let routines = RoutineTestSupport.simulateDay(seed: 2_026, options: options)
        let samples = [routines[0], routines[1], routines[3]]
        RoutineTestSupport.write(
            "Three routines from one simulated day (seed 2026)\n\n"
                + samples.map(RoutineTestSupport.describe).joined(separator: "\n\n") + "\n",
            to: "sample-routines.txt"
        )
        XCTAssertEqual(samples.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: RoutineTestSupport.evidenceURL("sample-routines.txt").path))
    }
}
