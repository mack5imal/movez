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
                    problems.append("day \(day) · \(routine.name): \(found.joined(separator: "; "))")
                }
            }
        }
        XCTAssertEqual(count, 1_000)
        XCTAssertEqual(problems.count, 0, problems.prefix(5).joined(separator: "\n"))
    }

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
            XCTAssertTrue(
                repeated.allSatisfy(RoutineContext.alwaysRepeatable.contains),
                "day \(day) repeated \(repeated)"
            )
        }
    }

    // MARK: - Rotation

    func testRotationVisitsEverySlotInOrder() {
        var options = RoutineTestSupport.DayOptions()
        options.breaks = 6
        let routines = RoutineTestSupport.simulateDay(seed: 42, options: options)
        XCTAssertEqual(
            routines.map(\.slot),
            [.hip, .tSpineChest, .neckShoulder, .posteriorChain, .core, .ankleFoot]
        )
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
                    "day \(day): \(previous.name) and \(current.name) share \(overlap.map(\.rawValue))"
                )
            }
        }
    }

    // MARK: - Time of day

    func testTimeOfDayShapes() {
        for seed in 0..<50 {
            let normal = RoutineTestSupport.routine(seed: UInt64(seed &* 13 &+ 1), timeOfDay: .normal)
            XCTAssertEqual(normal.buckets.first, .cir, "every routine opens on circulation")

            let last = RoutineTestSupport.routine(seed: UInt64(seed &* 17 &+ 2), timeOfDay: .last)
            XCTAssertGreaterThanOrEqual(last.buckets.filter { $0 == .flx }.count, 2, "wind-down needs two FLX blocks")
            XCTAssertEqual(last.buckets.last, .bre, "wind-down must close on breath")
        }
    }

    // MARK: - Variety across days

    /// Thirty days of two breaks a day, with the history threaded forward the way the coordinator
    /// threads it, and the rotation carrying on across days.
    ///
    /// This is the shape of a real week for someone who takes one or two breaks a day, and it is
    /// where the old builder was at its worst: 39 of the 124 eligible movements ever appeared, and
    /// one circulation movement was in 38% of routines, because selection took whichever movement
    /// was closest to an ideal length and broke ties by id.
    private func simulateMonth(breaksPerDay: Int) -> [Routine] {
        var served: [(id: String, day: Int)] = []
        var cursor = 0
        var routines: [Routine] = []

        for day in 0..<30 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = breaksPerDay
            options.difficultyCap = 3
            options.rotationCursor = cursor
            options.recency = served.reduce(into: [String: Double]()) { scores, entry in
                scores[entry.id, default: 0] += Recency.weight(daysAgo: day - entry.day)
            }

            let today = RoutineTestSupport.simulateDay(seed: UInt64(day &* 104_729 &+ 17), options: options)
            routines += today
            cursor += today.count
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
        XCTAssertLessThanOrEqual(topShare, 0.2, "one movement is in \(Int(topShare * 100))% of routines")
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
            options.rotationCursor = yesterday.count
            let today = RoutineTestSupport.simulateDay(seed: UInt64(day &* 7_919 &+ 6), options: options)

            for id in today.flatMap(\.movementIds) {
                total += 1
                if served.contains(id) { yesterdayCount += 1 }
            }
        }

        let share = Double(yesterdayCount) / Double(total)
        XCTAssertLessThan(share, 0.1, "\(Int(share * 100))% of today came from yesterday")
    }

    func testBalanceIsServedEveryDay() {
        for day in 0..<30 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 6
            let routines = RoutineTestSupport.simulateDay(seed: UInt64(day &* 977 &+ 7), options: options)
            let balanceBlocks = routines.flatMap(\.buckets).filter { $0 == .bal }.count
            XCTAssertGreaterThanOrEqual(balanceBlocks, 1, "day \(day) served no balance")
        }
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
                    context.balanceServedToday = true
                }.blocks
            }
        }

        let baseline = blocks(focus: .none)
        let balance = blocks(focus: .moreBalance)
        let upperBack = blocks(focus: .moreUpperBack)

        let baselineBalance = baseline.filter { $0.movement.bucket == .bal }.count
        let focusedBalance = balance.filter { $0.movement.bucket == .bal }.count
        XCTAssertGreaterThan(focusedBalance, baselineBalance, "more balance did not raise the BAL share")

        let upperRegions: Set<Region> = [.thoracic, .chest, .shoulder]
        let baselineUpper = baseline.filter { !Set($0.movement.regions).isDisjoint(with: upperRegions) }.count
        let focusedUpper = upperBack.filter { !Set($0.movement.regions).isDisjoint(with: upperRegions) }.count
        XCTAssertGreaterThan(focusedUpper, baselineUpper, "more upper back did not raise the T-spine share")

        RoutineTestSupport.write(
            """
            Bucket distribution over 200 generated routines per condition

            focus        blocks   CIR   FLX   STR   BAL   HWF   EYE   BRE
            \(row("none", baseline))
            \(row("moreBalance", balance))
            \(row("moreUpperBack", upperBack))

            BAL blocks       none \(baselineBalance)   moreBalance \(focusedBalance)
            T-spine/Chest/Shoulder blocks   none \(baselineUpper)   moreUpperBack \(focusedUpper)
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
        // Narrow the strength slot to STR-29 so the unlock is the only variable under test.
        let otherStrength = library.movements
            .filter { ($0.bucket == .str && $0.id != "STR-29") || $0.bucket == .bal }
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

    // MARK: - Determinism and naming

    /// The slot only weights selection, so naming by slot once put "Upper back opener" over leg
    /// swings and squats. Every ordinary routine must now work the regions its name claims.
    func testARoutineIsNamedForTheRegionsItActuallyWorks() {
        var renamed = 0
        for day in 0..<30 {
            var options = RoutineTestSupport.DayOptions()
            options.breaks = 8
            for routine in RoutineTestSupport.simulateDay(seed: UInt64(day &* 613 &+ 17), options: options)
            where RoutineNaming.timeOfDayName(routine.timeOfDay) == nil {
                guard let named = RotationSlot.allCases.first(where: { RoutineNaming.slotName($0).name == routine.name }) else {
                    XCTFail("day \(day): \(routine.name) is not a slot name")
                    continue
                }
                if named != routine.slot { renamed += 1 }
                let worked = Set(routine.blocks.flatMap(\.movement.regions))
                XCTAssertFalse(
                    worked.isDisjoint(with: named.regions),
                    "day \(day): \(routine.name) works \(worked.map(\.rawValue).sorted())"
                )
            }
        }
        XCTAssertGreaterThan(renamed, 0, "the sweep should include routines the old naming got wrong")
    }

    func testSameSeedProducesTheSameRoutine() {
        let first = RoutineTestSupport.routine(seed: 4_242)
        let second = RoutineTestSupport.routine(seed: 4_242)
        XCTAssertEqual(first.movementIds, second.movementIds)
        XCTAssertEqual(first.blocks.map(\.seconds), second.blocks.map(\.seconds))

        let different = RoutineTestSupport.routine(seed: 4_243)
        XCTAssertNotEqual(first.movementIds, different.movementIds)
    }

    func testNamingTable() {
        let hip = RoutineNaming.name(slot: .hip, timeOfDay: .normal)
        XCTAssertEqual(hip.name, "Hip reset")
        XCTAssertEqual(hip.focus, "hips and glutes")
        XCTAssertEqual(hip.completionTitle, "Hips reset")
        XCTAssertEqual(hip.eyebrow, "HIP RESET · HIPS AND GLUTES")
        XCTAssertEqual(hip.subtitle, "Hip reset · hips and glutes")

        XCTAssertEqual(RoutineNaming.name(slot: .hip, timeOfDay: .last).completionTitle, "Wound down")
        XCTAssertEqual(RoutineNaming.slotName(.ankleFoot).completionTitle, "Feet awake")

        let routine = RoutineTestSupport.routine(seed: 7, rotationIndex: 0)
        XCTAssertEqual(routine.subtitle, "Hip reset · hips and glutes")
        XCTAssertEqual(routine.eyebrow, "HIP RESET · HIPS AND GLUTES")
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
