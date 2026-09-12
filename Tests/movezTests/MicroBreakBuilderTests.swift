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

    func testAlwaysLastsOneMinute() {
        for seed in 0..<200 {
            let micro = micro(seed: UInt64(seed &* 13 &+ 1)) { $0.emphasisIndex = seed }
            XCTAssertEqual(micro.totalSeconds, 60, "emphasis \(micro.emphasis)")
            XCTAssertTrue((1...2).contains(micro.blocks.count))
            if micro.blocks.count == 2 {
                XCTAssertTrue(micro.blocks.allSatisfy { $0.seconds == 30 })
            }
        }
    }

    func testOnlyServesMicroEligibleMovements() {
        for seed in 0..<200 {
            let micro = micro(seed: UInt64(seed &* 17 &+ 2)) { $0.emphasisIndex = seed }
            for block in micro.blocks {
                XCTAssertTrue(block.movement.microEligible, "\(block.movement.id) is not micro-eligible")
                XCTAssertFalse(block.movement.needsEquipment)
                XCTAssertFalse(block.movement.isFloor)
                XCTAssertLessThanOrEqual(block.seconds, block.movement.blockSeconds)
            }
        }
    }

    func testCirculationEmphasisLeadsWithCirculation() {
        for seed in 0..<100 {
            let micro = micro(seed: UInt64(seed &* 19 &+ 3)) { $0.emphasisIndex = 0 }
            XCTAssertEqual(micro.emphasis, .circulation)
            XCTAssertEqual(micro.blocks.first?.movement.bucket, .cir)
        }
    }

    func testEyesHandsAndPostureEmphasesLeadWithTheirBuckets() {
        for seed in 0..<100 {
            let eyesHands = micro(seed: UInt64(seed &* 23 &+ 4)) { $0.emphasisIndex = 1 }
            XCTAssertEqual(eyesHands.emphasis, .eyesHands)
            XCTAssertTrue([.eye, .hwf].contains(eyesHands.blocks[0].movement.bucket))
            XCTAssertEqual(eyesHands.blocks.last?.movement.bucket, .cir, "circulation belongs in the second half")

            let posture = micro(seed: UInt64(seed &* 29 &+ 5)) { $0.emphasisIndex = 2 }
            XCTAssertEqual(posture.emphasis, .posture)
            XCTAssertTrue([.flx, .bre].contains(posture.blocks[0].movement.bucket))
        }
    }

    func testNeverRepeatsTheLastMicroOrTheNextFullBreak() {
        let forbidden: Set<String> = ["CIR-04", "CIR-02", "EYE-01", "EYE-02"]
        let upcoming: Set<String> = ["CIR-01", "FLX-01", "HWF-06"]
        for seed in 0..<200 {
            let micro = micro(seed: UInt64(seed &* 31 &+ 6)) { context in
                context.emphasisIndex = seed
                context.lastMicroMovementIds = forbidden
                context.nextFullRoutineIds = upcoming
            }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: forbidden))
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: upcoming))
        }
    }

    func testConsecutiveMicrosDoNotRepeat() {
        var previous: Set<String> = []
        for index in 0..<24 {
            let micro = micro(seed: UInt64(index &* 37 &+ 7)) { context in
                context.emphasisIndex = index
                context.lastMicroMovementIds = previous
            }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: previous), "micro \(index) repeated a movement")
            previous = Set(micro.movementIds)
        }
    }

    func testPostLunchIsASingleCirculationMinute() {
        for seed in 0..<100 {
            let micro = micro(seed: UInt64(seed &* 41 &+ 8)) { context in
                context.isPostLunch = true
                context.emphasisIndex = seed
            }
            XCTAssertEqual(micro.blocks.count, 1)
            XCTAssertEqual(micro.blocks[0].seconds, 60)
            XCTAssertEqual(micro.blocks[0].movement.bucket, .cir)
            XCTAssertTrue(
                MicroBreakBuilder.postLunchPreference.contains(micro.blocks[0].movement.id),
                "post-lunch served \(micro.blocks[0].movement.id)"
            )
        }
    }

    func testExcludedMovementsNeverAppear() {
        let excluded = Set(library.microEligible.filter { $0.bucket == .cir }.map(\.id))
        for seed in 0..<100 {
            let micro = micro(seed: UInt64(seed &* 43 &+ 9)) { context in
                context.excluded = excluded
                context.emphasisIndex = 0
            }
            XCTAssertTrue(Set(micro.movementIds).isDisjoint(with: excluded))
            XCTAssertEqual(micro.totalSeconds, 60)
        }
    }

    func testEyebrowUsesThePlainRegionWord() {
        let micro = micro(seed: 11) { $0.emphasisIndex = 0 }
        XCTAssertTrue(micro.eyebrow.hasPrefix("MICRO-BREAK · "))
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
        let first = micro(seed: 5_150) { $0.emphasisIndex = 1 }
        let second = micro(seed: 5_150) { $0.emphasisIndex = 1 }
        XCTAssertEqual(first.movementIds, second.movementIds)
    }
}
