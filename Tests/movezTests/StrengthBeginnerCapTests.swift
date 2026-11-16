import XCTest
@testable import movez

/// What the strength builder does where the default Beginner cap leaves a pattern short: the cap
/// is kept, and the rule that has to give is recorded on the break (DECISIONS 71, 83).
final class StrengthBeginnerCapTests: XCTestCase {
    private var library: StrengthLibrary { StrengthTestSupport.library }
    private var builder: StrengthBreakBuilder { StrengthBreakBuilder(library: library) }

    /// At the default Beginner cap no squat or lunge is vigorous, so with kit the vigorous rule is
    /// let go for those sets and the cap is kept: a light bodyweight squat, never a loaded one
    /// above the cap (DECISIONS 71, LIB-2).
    func testWithKitAtTheBeginnerCapTheCapWinsOverTheVigorousRule() {
        XCTAssertEqual(SettingsStore.strengthDifficultyDefault, 1)
        let order = StrengthTestSupport.plans[0].order
        XCTAssertEqual(order.first, .pattern(.sqt))
        for seed in 0..<100 {
            var context = StrengthContext()
            context.equipment = [.dumbbells]
            context.seed = UInt64(seed)
            let built = builder.build(letter: .dayA, setOrder: order, context: context)
            XCTAssertTrue(built.sets.allSatisfy { $0.movement.difficulty <= 1 }, "\(built.movementIds)")
            XCTAssertFalse(built.relaxed.contains { $0.rule == .difficulty }, "\(built.movementIds)")
            let squat = built.sets[0].movement
            XCTAssertFalse(squat.vigorous, "\(squat.id): no vigorous squat is difficulty 1")
            XCTAssertTrue(built.relaxed.contains(StrengthRelaxation(slot: .set(1), rule: .vigorous)))
        }
    }

    /// The Beginner bodyweight triceps bucket has one difficulty-1 move, so an arm break repeats it
    /// for the third set rather than serving a move above the cap (DECISIONS 83, TST-3).
    func testAOneMoveArmBucketRepeatsItsMoveBeforeTheCapIsLetGo() {
        let beginnerTriceps = library.movements(in: .tri).filter { $0.isBodyweight && $0.difficulty == 1 }
        XCTAssertEqual(beginnerTriceps.map(\.id), ["TRI-05"])
        for seed in 0..<50 {
            var context = StrengthContext()
            context.seed = UInt64(seed)
            let built = builder.build(letter: .dayA, setOrder: StrengthTestSupport.armOrder(.dayA), context: context)
            XCTAssertEqual(built.sets.map(\.movement.id), ["TRI-05", "TRI-05", "TRI-05"])
            XCTAssertEqual(built.relaxed.filter { $0.slot == .set(3) }.map(\.rule), [.armAlternate])
        }
        // With a second move inside the cap, the third set is still a different one.
        for seed in 0..<50 {
            var context = StrengthTestSupport.everythingContext(seed: UInt64(seed))
            context.difficultyCap = 2
            let built = builder.build(letter: .dayA, setOrder: StrengthTestSupport.armOrder(.dayA), context: context)
            XCTAssertNotEqual(built.sets[2].movement.id, built.sets[0].movement.id)
            XCTAssertFalse(built.relaxed.contains { $0.rule == .armAlternate })
        }
    }
}
