import XCTest
@testable import movez

final class MicroBreakBuilderTests: XCTestCase {
    private var library: MovementLibrary { RoutineTestSupport.library }
    private var builder: MicroBreakBuilder { RoutineTestSupport.microBuilder }

    private func micro(seed: UInt64, configure: (inout MicroContext) -> Void = { _ in }) -> MicroBreak {
        var context = MicroContext()
        context.seed = seed
        configure(&context)
        return builder.build(context: context)
    }

    /// One per-side movement for the whole minute, or two one-sided movements of thirty seconds.
    func testAPerSideMovementRunsAloneAndTheRestComeInPairs() {
        var singles = 0
        var pairs = 0
        for seed in 0..<300 {
            let micro = micro(seed: UInt64(seed &* 13 &+ 1))
            switch micro.blocks.count {
            case 1:
                singles += 1
                XCTAssertTrue(micro.blocks[0].perSide, "\(micro.blocks[0].movement.id) ran alone but is one-sided")
                XCTAssertEqual(micro.blocks[0].seconds, 60)
                XCTAssertEqual(micro.blocks[0].secondsPerSide, 30)
                XCTAssertEqual(micro.totalSeconds, 65, "the minute and its lead-in")
            case 2:
                pairs += 1
                XCTAssertTrue(micro.blocks.allSatisfy { !$0.perSide }, "a pair held \(micro.movementIds)")
                XCTAssertTrue(micro.blocks.allSatisfy { $0.seconds == 30 })
                XCTAssertEqual(micro.totalSeconds, 70, "two halves, each after its lead-in")
            default:
                XCTFail("micro-break with \(micro.blocks.count) blocks")
            }
        }
        XCTAssertGreaterThan(singles, 0)
        XCTAssertGreaterThan(pairs, singles, "a third of the pool is per-side, so pairs should dominate")
    }

    func testOnlyServesMicroEligibleMovements() {
        for seed in 0..<200 {
            let micro = micro(seed: UInt64(seed &* 17 &+ 2))
            for block in micro.blocks {
                XCTAssertTrue(block.movement.microEligible, "\(block.movement.id) is not micro-eligible")
                XCTAssertFalse(block.movement.needsEquipment)
                XCTAssertFalse(block.movement.isFloor)
            }
        }
    }

    /// The movement is drawn from the whole pool, so a bucket comes up in proportion to how many
    /// movements it has. Drawing the bucket first gave the eight eye and breathing movements the
    /// odds of the sixteen stretches.
    func testBucketsComeUpInProportionToTheirSize() {
        let pool = builder.candidates(for: MicroContext())
        var served: [Bucket: Int] = [:]
        var total = 0
        for seed in 0..<3_000 {
            for block in micro(seed: UInt64(seed &* 31 &+ 6)).blocks {
                served[block.movement.bucket, default: 0] += 1
                total += 1
            }
        }
        let eyeBreath = Double((served[.eye] ?? 0) + (served[.bre] ?? 0)) / Double(total)
        let eyeBreathPool = Double(pool.filter { $0.bucket == .eye || $0.bucket == .bre }.count) / Double(pool.count)
        // Pairs are one-sided, and every eye and breathing movement is one-sided, so they run a
        // little above their share of the pool. They used to run at more than twice it.
        XCTAssertEqual(eyeBreath, eyeBreathPool, accuracy: 0.05, "eye and breathing are \(Int(eyeBreath * 100))% of micro movements")
        XCTAssertEqual(Set(served.keys), Set(Bucket.allCases), "missing \(Set(Bucket.allCases).subtracting(served.keys))")
    }

    func testNeverRepeatsTheLastMicroTheNextFullBreakOrAnythingFromToday() {
        let forbidden: Set<String> = ["CIR-04", "CIR-02", "EYE-01", "EYE-02"]
        let upcoming: Set<String> = ["CIR-01", "FLX-01", "HWF-06"]
        let today: Set<String> = ["BRE-01", "BAL-01", "STR-11", "CIR-12"]
        for seed in 0..<200 {
            let micro = micro(seed: UInt64(seed &* 31 &+ 6)) { context in
                context.lastMicroMovementIds = forbidden
                context.nextFullRoutineIds = upcoming
                context.usedMovementIdsToday = today
            }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: forbidden))
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: upcoming))
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: today))
        }
    }

    /// A day long enough to use up the pool still gets a micro-break, rather than an empty panel.
    func testAnExhaustedDayStillServesSomething() {
        let everything = Set(library.microEligible.map(\.id))
        let micro = micro(seed: 3) { $0.usedMovementIdsToday = everything }
        XCTAssertFalse(micro.blocks.isEmpty)
    }

    func testConsecutiveMicrosDoNotRepeat() {
        var previous: Set<String> = []
        for index in 0..<24 {
            let micro = micro(seed: UInt64(index &* 37 &+ 7)) { context in
                context.lastMicroMovementIds = previous
            }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: previous), "micro \(index) repeated a movement")
            previous = Set(micro.movementIds)
        }
    }

    func testExcludedMovementsNeverAppear() {
        let excluded = Set(library.microEligible.filter { $0.bucket == .cir }.map(\.id))
        for seed in 0..<100 {
            let micro = micro(seed: UInt64(seed &* 43 &+ 9)) { $0.excluded = excluded }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: excluded))
        }
    }

    func testEyebrowUsesThePlainRegionWordOfTheBlockOnScreen() {
        let micro = micro(seed: 11)
        XCTAssertTrue(MicroBreak.eyebrow(for: micro.blocks.first).hasPrefix("MICRO-BREAK · "))
        XCTAssertEqual(MicroBreak.eyebrow(for: nil), "MICRO-BREAK · MOVEMENT")
        XCTAssertEqual(MicroBreak.regionWord(for: .shoulder), "shoulders")
        XCTAssertEqual(MicroBreak.regionWord(for: .calfAnkle), "calves")
        XCTAssertEqual(MicroBreak.regionWord(for: .wristForearm), "hands")
        XCTAssertEqual(MicroBreak.regionWord(for: .thoracic), "upper back")
        XCTAssertEqual(MicroBreak.regionWord(for: .breath), "breathing")
        XCTAssertEqual(MicroBreak.regionWord(for: .full), "whole body")
        XCTAssertEqual(MicroBreak.regionWord(for: .eyes), "eyes")
        XCTAssertEqual(MicroBreak.regionWord(for: .hip), "hips")
        XCTAssertEqual(MicroBreak.regionWord(for: .neck), "neck")
        XCTAssertEqual(MicroBreak.regionWord(for: .glute), "glutes")
    }

    func testDeterministicForTheSameSeed() {
        let first = micro(seed: 5_150)
        let second = micro(seed: 5_150)
        XCTAssertEqual(first.movementIds, second.movementIds)
    }
}
