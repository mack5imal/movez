import XCTest
@testable import movez

final class EndRangeBreakBuilderTests: XCTestCase {
    private var library: StrengthLibrary { StrengthTestSupport.library }
    private var builder: EndRangeBreakBuilder { EndRangeBreakBuilder(library: library) }

    private func build(
        seed: UInt64,
        avoiding regions: Set<Region> = [],
        configure: (inout StrengthContext) -> Void = { _ in }
    ) -> EndRangeBreak {
        var context = StrengthTestSupport.everythingContext(seed: seed)
        configure(&context)
        return builder.build(context: context, avoidingRegions: regions)
    }

    func testFourEndMovesOfAMinuteTotalling260Seconds() {
        for seed in 0..<200 {
            let endRange = build(seed: UInt64(seed &* 13 &+ 5))
            XCTAssertEqual(endRange.blocks.count, 4)
            XCTAssertTrue(endRange.blocks.allSatisfy { $0.movement.bucket == .end }, "\(endRange.movementIds)")
            XCTAssertTrue(endRange.blocks.allSatisfy { $0.seconds == 60 })
            XCTAssertTrue(endRange.blocks.allSatisfy { $0.secondsPerSide == ($0.perSide ? 30 : 60) })
            XCTAssertEqual(Set(endRange.movementIds).count, 4, "a move repeated inside the break")
            XCTAssertEqual(endRange.plannedSeconds, 260)
            XCTAssertEqual(PlannedBreak.endRange(endRange).plannedSeconds, 260)
            XCTAssertEqual(PlannedBreak.endRange(endRange).kind, .endRange)
        }
    }

    func testNothingServedTodayIsDrawn() {
        let end = library.movements(in: .end).map(\.id)
        let served = Set(end.prefix(end.count - 8))
        for seed in 0..<200 {
            let endRange = build(seed: UInt64(seed)) { $0.usedStrengthIdsToday = served }
            XCTAssertTrue(served.isDisjoint(with: endRange.movementIds), "\(endRange.movementIds)")
            XCTAssertEqual(endRange.relaxed, [])
        }
    }

    /// The regions the day's strength breaks worked are left alone while another move will do.
    func testTheDaysWorkedRegionsAreAvoidedWherePossible() {
        let worked: Set<Region> = [.hip, .glute, .quad]
        for seed in 0..<200 {
            let endRange = build(seed: UInt64(seed), avoiding: worked)
            for block in endRange.blocks {
                XCTAssertTrue(worked.isDisjoint(with: block.movement.regions), "\(block.movement.id) works \(block.movement.regions)")
            }
        }
        // Every END move but a handful touches the hips, so avoiding them all leaves too few:
        // the break still has four moves.
        let everything = Set(Region.allCases)
        XCTAssertEqual(build(seed: 1, avoiding: everything).blocks.count, 4)
    }

    func testTheWallAndTheDifficultyRulesHold() {
        for seed in 0..<200 {
            let endRange = build(seed: UInt64(seed)) { context in
                context.solidWallNearby = false
                context.difficultyCap = 2
                context.unlockedBuckets = []
            }
            for block in endRange.blocks {
                XCTAssertFalse(block.movement.settings.contains(.wall), block.movement.id)
                XCTAssertLessThanOrEqual(block.movement.difficulty, 2, block.movement.id)
            }
        }
    }

    func testTheSameContextBuildsTheIdenticalBreak() {
        for seed in 0..<50 {
            XCTAssertEqual(build(seed: UInt64(seed), avoiding: [.shoulder]), build(seed: UInt64(seed), avoiding: [.shoulder]))
        }
        XCTAssertGreaterThan(Set((0..<40).map { build(seed: UInt64($0)).movementIds }).count, 10)
    }

    func testAnExhaustedPoolStillBuildsFourMoves() {
        let everything = Set(library.movements.map(\.id))
        let endRange = build(seed: 3) { context in
            context.usedStrengthIdsToday = everything
            context.excluded = everything
        }
        XCTAssertEqual(endRange.blocks.count, 4)
        XCTAssertTrue(endRange.blocks.allSatisfy { $0.movement.bucket == .end })
        XCTAssertTrue(endRange.relaxed.contains { $0.rule == .servedToday })
        XCTAssertTrue(endRange.relaxed.contains { $0.rule == .excluded })
    }
}
