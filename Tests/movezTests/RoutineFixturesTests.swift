import XCTest
@testable import movez

/// The nine worked routines R1–R9 in the library document are the design's reference shapes.
/// They predate the four-block default — two of them run to six blocks — so the strict validator
/// is not their contract. `allowSampleShapes` is.
final class RoutineFixturesTests: XCTestCase {
    private var library: MovementLibrary { RoutineTestSupport.library }

    private func routine(from template: RoutineTemplate, shape: RoutineShape) -> Routine {
        let blocks = template.blocks.compactMap { block -> RoutineBlock? in
            guard let movement = library.movement(id: block.movementId) else { return nil }
            return RoutineBlock(
                movement: movement,
                seconds: block.seconds,
                trimmedFrom: block.seconds == movement.blockSeconds ? nil : movement.blockSeconds
            )
        }
        return Routine(
            id: UUID(),
            name: template.name,
            focus: template.focus,
            completionTitle: template.name,
            slot: .hip,
            shape: shape,
            timeOfDay: .normal,
            blocks: blocks
        )
    }

    func testEverySampleRoutineValidatesAsASampleShape() {
        XCTAssertEqual(library.routines.count, 9)
        for template in library.routines {
            let routine = routine(from: template, shape: .standard)
            XCTAssertEqual(routine.blocks.count, template.blocks.count, "\(template.id) has a dangling movement id")
            let problems = RoutineValidator.validate(routine, library: library, allowSampleShapes: true)
            XCTAssertEqual(problems, [], "\(template.id) \(template.name): \(problems.joined(separator: "; "))")
        }
    }

    /// Every way R1–R9 depart from the strict generated-routine contract, frozen so that a change
    /// to the validator or to the library shows up here rather than silently.
    ///
    /// Two kinds of deviation appear, both deliberate in the source document:
    /// - **count and order** — R2 and R5 run to six blocks, and several samples put the closer
    ///   before an extra FLX rather than last.
    /// - **trim floor** — a few samples trim a 60 s or 90 s movement to 45 s, below the 60 s floor
    ///   the generator holds itself to.
    static let knownStrictDeviations: [String: (shape: RoutineShape, problems: [String])] = [
        "R1": (.standard, [
            "block 3 is FLX, expected STR|BAL",
            "block 4 is STR, expected FLX"
        ]),
        "R2": (.standard, [
            "block count 6 is outside 3…5",
            "shape standard has no plan for 6 blocks"
        ]),
        "R3": (.standard, [
            "block 3 is CIR, expected STR|BAL",
            "block 4 is STR, expected FLX",
            "block 5 is CIR, expected HWF|EYE|BRE"
        ]),
        "R4": (.standard, [
            "block 4 is STR, expected FLX",
            "block 5 is FLX, expected HWF|EYE|BRE"
        ]),
        "R5": (.standard, [
            "block count 6 is outside 3…5",
            "shape standard has no plan for 6 blocks",
            "BRE-03 runs 45 s, below the 60 s floor"
        ]),
        "R6": (.standard, ["block 4 is STR, expected FLX"]),
        "R7": (.standard, [
            "block 3 is FLX, expected STR|BAL",
            "block 4 is STR, expected FLX",
            "block 5 is FLX, expected HWF|EYE|BRE",
            "FLX-37 runs 45 s, below the 60 s floor"
        ]),
        "R8": (.windDown, ["BRE-01 runs 45 s, below the 60 s floor"]),
        "R9": (.standard, [
            "block 4 is BAL, expected FLX",
            "block 5 is BAL, expected HWF|EYE|BRE",
            "FLX-26 runs 45 s, below the 60 s floor"
        ])
    ]

    func testSampleRoutineStrictDeviationsAreTheKnownOnes() {
        var report: [String] = ["Strict validation of the library's worked routines R1-R9", ""]

        for template in library.routines {
            let known = Self.knownStrictDeviations[template.id]
            XCTAssertNotNil(known, "\(template.id) has no recorded expectation")
            guard let known else { continue }

            let routine = routine(from: template, shape: known.shape)
            let problems = RoutineValidator.validate(routine, library: library)
            XCTAssertEqual(problems, known.problems, "\(template.id) \(template.name)")

            let summary = problems.isEmpty ? "strictly valid as \(known.shape.rawValue)" : problems.joined(separator: "; ")
            report.append("\(template.id) \(template.name.padded(to: 22))\(routine.blocks.count) blocks, "
                + "\(routine.totalSeconds) s, best shape \(known.shape.rawValue) — \(summary)")
        }

        let strictlyValid = Self.knownStrictDeviations.filter { $0.value.problems.isEmpty }.keys.sorted()
        XCTAssertEqual(strictlyValid, [], "no sample is expected to pass the strict generated contract as written")

        let sixBlock = library.routines.filter { $0.blocks.count > 5 }.map(\.id)
        XCTAssertEqual(sixBlock, ["R2", "R5"], "only R2 and R5 exceed five blocks")
        RoutineTestSupport.write(report.joined(separator: "\n") + "\n", to: "sample-routine-validation.txt")
    }

    func testWindDownSampleDeviatesOnlyByItsTrimmedBreathBlock() throws {
        let template = try XCTUnwrap(library.routines.first { $0.id == "R8" })
        let routine = routine(from: template, shape: .windDown)
        XCTAssertEqual(routine.buckets, [.cir, .flx, .flx, .flx, .bre])
        XCTAssertEqual(
            RoutineValidator.validate(routine, library: library),
            ["BRE-01 runs 45 s, below the 60 s floor"]
        )
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
