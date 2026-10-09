import XCTest
@testable import movez

/// The nine worked routines R1–R9 in the library document are the design's reference shapes.
/// They predate the five-block rule — two of them run to six blocks, and their blocks run 45 to
/// 90 s — so the strict validator is not their contract. `allowSampleShapes` is.
final class RoutineFixturesTests: XCTestCase {
    private var library: MovementLibrary { RoutineTestSupport.library }

    private func routine(from template: RoutineTemplate) -> Routine {
        let blocks = template.blocks.compactMap { block -> RoutineBlock? in
            guard let movement = library.movement(id: block.movementId) else { return nil }
            return RoutineBlock(movement: movement, seconds: block.seconds)
        }
        return Routine(id: UUID(), blocks: blocks)
    }

    func testEverySampleRoutineValidatesAsASampleShape() {
        XCTAssertEqual(library.routines.count, 9)
        for template in library.routines {
            let routine = routine(from: template)
            XCTAssertEqual(routine.blocks.count, template.blocks.count, "\(template.id) has a dangling movement id")
            let problems = RoutineValidator.validate(routine, library: library, allowSampleShapes: true)
            XCTAssertEqual(problems, [], "\(template.id) \(template.name): \(problems.joined(separator: "; "))")
        }
    }

    func testNoSampleRoutineMeetsTheStrictContract() {
        for template in library.routines {
            let problems = RoutineValidator.validate(routine(from: template), library: library)
            XCTAssertFalse(problems.isEmpty, "\(template.id) unexpectedly passes the generated-routine contract")
        }
    }

    func testMicroRoutineSamplesAreMicroEligibleAndLastOneMinute() {
        for template in library.microRoutines {
            XCTAssertEqual(template.targetSeconds, 60)
            XCTAssertEqual(template.blocks.reduce(0) { $0 + $1.seconds }, 60, "\(template.id)")
            for block in template.blocks {
                let movement = library.movement(id: block.movementId)
                XCTAssertEqual(movement?.microEligible, true, "\(template.id) uses \(block.movementId)")
            }
        }
    }
}
