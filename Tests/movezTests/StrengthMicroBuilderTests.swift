import XCTest
@testable import movez

final class StrengthMicroBuilderTests: XCTestCase {
    private var library: StrengthLibrary { StrengthTestSupport.library }
    private var builder: StrengthMicroBuilder { StrengthMicroBuilder(library: library) }

    private func micro(seed: UInt64, configure: (inout StrengthMicroContext) -> Void = { _ in }) -> StrengthMicroBreak {
        var context = StrengthMicroContext()
        context.difficultyCap = 3
        context.unlockedBuckets = Set(StrengthBucket.allCases)
        context.seed = seed
        configure(&context)
        return builder.build(context: context)
    }

    private func regions(_ micro: StrengthMicroBreak) -> Set<Region> {
        Set(micro.blocks.flatMap(\.movement.regions))
    }

    func testOnlyEndMovesAndNeverTheFloor() {
        for seed in 0..<300 {
            for block in micro(seed: UInt64(seed &* 17 &+ 2)).blocks {
                XCTAssertEqual(block.movement.bucket, .end, block.movement.id)
                XCTAssertFalse(block.movement.onFloor, "\(block.movement.id) is on the floor")
            }
        }
    }

    /// One per-side move for the minute, or two two-sided moves of thirty seconds.
    func testOnePerSideMoveAloneOrTwoTwoSidedMoves() {
        var singles = 0
        var pairs = 0
        for seed in 0..<300 {
            let micro = micro(seed: UInt64(seed &* 13 &+ 1))
            switch micro.blocks.count {
            case 1:
                singles += 1
                XCTAssertTrue(micro.blocks[0].perSide, "\(micro.blocks[0].movement.id) ran alone but is two-sided")
                XCTAssertEqual(micro.blocks[0].seconds, 60)
                XCTAssertEqual(micro.blocks[0].secondsPerSide, 30)
                XCTAssertEqual(micro.totalSeconds, 65)
            case 2:
                pairs += 1
                XCTAssertTrue(micro.blocks.allSatisfy { !$0.perSide }, "a pair held \(micro.movementIds)")
                XCTAssertTrue(micro.blocks.allSatisfy { $0.seconds == 30 })
                XCTAssertEqual(micro.totalSeconds, 70)
            default:
                XCTFail("micro-break with \(micro.blocks.count) blocks")
            }
            XCTAssertEqual(micro.relaxed, [])
        }
        XCTAssertGreaterThan(singles, 0)
        XCTAssertGreaterThan(pairs, 0)
    }

    func testTheSecondMoveKeepsTheFirstOnesPosture() {
        var sawSeated = false
        for seed in 0..<400 {
            let micro = micro(seed: UInt64(seed &* 29 &+ 4))
            guard micro.blocks.count == 2 else { continue }
            let postures = micro.blocks.map { StrengthPosture($0.movement) }
            XCTAssertEqual(postures[0], postures[1], "\(micro.movementIds)")
            if postures[0] == .seated { sawSeated = true }
        }
        XCTAssertTrue(sawSeated, "seated pairs should come up")
    }

    func testNoRegionIsSharedWithThePreviousMicroBreak() {
        for seed in 0..<300 {
            let previous = micro(seed: UInt64(seed))
            let next = micro(seed: UInt64(seed) &+ 1_000) { $0.lastMicroMovementIds = Set(previous.movementIds) }
            XCTAssertTrue(regions(previous).isDisjoint(with: regions(next)), "\(previous.movementIds) then \(next.movementIds)")
        }
    }

    /// The next full break's regions are avoided while another move will do.
    func testTheNextFullBreaksRegionsAreAvoidedWhenPossible() {
        let nextFull: Set<String> = ["END-24", "END-30"]
        let nextRegions = Set(nextFull.compactMap { library.movement(id: $0) }.flatMap(\.regions))
        for seed in 0..<300 {
            let micro = micro(seed: UInt64(seed)) { $0.nextFullBreakIds = nextFull }
            XCTAssertTrue(nextRegions.isDisjoint(with: regions(micro)), "\(micro.movementIds)")
        }
    }

    func testNoMoveIsRepeatedInADayWhileThePoolAllows() {
        var servedToday = Set<String>()
        var last = Set<String>()
        for index in 0..<6 {
            let micro = micro(seed: UInt64(index)) { context in
                context.usedStrengthIdsToday = servedToday
                context.lastMicroMovementIds = last
            }
            XCTAssertFalse(micro.relaxed.contains { $0.rule == .servedToday })
            XCTAssertTrue(servedToday.isDisjoint(with: micro.movementIds), "\(micro.movementIds) repeats \(servedToday)")
            servedToday.formUnion(micro.movementIds)
            last = Set(micro.movementIds)
        }
    }

    func testTheSameContextBuildsTheIdenticalMicroBreak() {
        for seed in 0..<50 {
            let configure: (inout StrengthMicroContext) -> Void = { $0.lastMicroMovementIds = ["END-07"] }
            XCTAssertEqual(micro(seed: UInt64(seed), configure: configure), micro(seed: UInt64(seed), configure: configure))
        }
        XCTAssertGreaterThan(Set((0..<40).map { micro(seed: UInt64($0)).movementIds }).count, 10)
    }

    func testAnExhaustedPoolStillFillsThePanel() {
        let everything = Set(library.movements.map(\.id))
        let micro = micro(seed: 5) { context in
            context.usedStrengthIdsToday = everything
            context.excluded = everything
            context.lastMicroMovementIds = Set(self.library.movements(in: .end).map(\.id))
        }
        XCTAssertFalse(micro.blocks.isEmpty)
        XCTAssertTrue(micro.blocks.allSatisfy { $0.movement.bucket == .end && !$0.movement.onFloor })
        XCTAssertTrue(micro.relaxed.contains { $0.rule == .servedToday })
        XCTAssertTrue(micro.relaxed.contains { $0.rule == .previousMicroRegion })
    }
}
