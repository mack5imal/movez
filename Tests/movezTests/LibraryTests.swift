import XCTest
@testable import movez

final class LibraryTests: XCTestCase {
    private static let library: MovementLibrary = {
        do {
            return try LibraryLoader.loadBundled()
        } catch {
            fatalError("Bundled movement library failed to load: \(error)")
        }
    }()

    private var library: MovementLibrary { Self.library }

    func testDecodesEveryMovement() {
        XCTAssertEqual(library.movements.count, 147)
        XCTAssertEqual(library.microEligible.count, 65)
        XCTAssertEqual(library.version, "4")
    }

    func testBucketCounts() {
        let expected: [Bucket: Int] = [.flx: 38, .cir: 20, .str: 38, .bal: 29, .hwf: 11, .eye: 5, .bre: 6]
        XCTAssertEqual(Bucket.allCases.count, 7)
        for (bucket, count) in expected {
            XCTAssertEqual(library.movements(in: bucket).count, count, "bucket \(bucket.rawValue)")
        }
        XCTAssertEqual(expected.values.reduce(0, +), 147)
        for info in library.buckets {
            XCTAssertEqual(info.count, expected[info.id], "declared count for \(info.id.rawValue)")
        }
    }

    func testRoutinesDecodeAndResolve() {
        XCTAssertEqual(library.routines.count, 9)
        XCTAssertEqual(library.microRoutines.count, 8)
        for routine in library.routines {
            XCTAssertEqual(routine.sumOfBlocks, routine.targetSeconds, "routine \(routine.id)")
            XCTAssertEqual(routine.blocks.reduce(0) { $0 + $1.seconds }, routine.targetSeconds, "routine \(routine.id)")
            XCTAssertNotNil(library.resolve(routine), "routine \(routine.id) has a dangling movement id")
        }
        for routine in library.microRoutines {
            XCTAssertEqual(routine.sumOfBlocks, routine.targetSeconds, "micro routine \(routine.id)")
            XCTAssertEqual(routine.targetSeconds, 60)
            for block in routine.blocks {
                XCTAssertNotNil(library.movement(id: block.movementId), "micro routine \(routine.id)")
            }
        }
    }

    func testPresets() {
        XCTAssertEqual(library.presets.count, 3)

        let fiftyFive = library.preset(id: .fiftyFiveFive)
        XCTAssertEqual(fiftyFive?.isDefault, true)
        XCTAssertEqual(fiftyFive?.microBreaksAtMinutes, [30])
        XCTAssertEqual(fiftyFive?.sitMinutes, 55)
        XCTAssertEqual(fiftyFive?.breakMinutes, 5)
        XCTAssertEqual(library.defaultPreset?.id, .fiftyFiveFive)

        XCTAssertEqual(library.preset(id: .eightyFiveFive)?.microBreaksAtMinutes, [30, 60])
        XCTAssertEqual(library.preset(id: .twentyFiveFive)?.microBreaksAtMinutes, [])
        XCTAssertEqual(library.preset(id: .twentyFiveFive)?.microDefaultOn, false)
        XCTAssertEqual(library.preset(id: .twentyFiveFive)?.isDefault, false)
    }

    func testEquipmentEnum() {
        XCTAssertEqual(Equipment.allCases.count, 4)
        XCTAssertEqual(
            Set(Equipment.allCases.map(\.rawValue)),
            ["band", "kettlebell_or_dumbbell", "foam_roller", "ball"]
        )
        XCTAssertEqual(library.movements.filter(\.needsEquipment).count, 18)
        XCTAssertEqual(Equipment.foamRoller.displayName, "Roller")
        XCTAssertEqual(Equipment.kettlebellOrDumbbell.displayName, "Kettlebell or dumbbell")
    }

    func testFLX01DecodesExactly() throws {
        let movement = try XCTUnwrap(library.movement(id: "FLX-01"))
        XCTAssertEqual(movement.name, "Standing hip flexor stretch")
        XCTAssertEqual(movement.blockSeconds, 60)
        XCTAssertTrue(movement.microEligible)
        XCTAssertTrue(movement.perSide)
        XCTAssertEqual(movement.regions, [.hip])
        XCTAssertEqual(movement.bucket, .flx)
        XCTAssertEqual(movement.bucketName, "Flexibility & mobility")
        XCTAssertEqual(movement.settings, [.stand])
        XCTAssertEqual(movement.difficulty, 1)
        XCTAssertTrue(movement.equipmentOptional.isEmpty)
        XCTAssertEqual(movement.counteracts, "hip flexor shortening")
        XCTAssertFalse(movement.instructions.isEmpty)
    }

    func testSTR17DecodesWithBand() throws {
        let movement = try XCTUnwrap(library.movement(id: "STR-17"))
        XCTAssertEqual(movement.equipmentOptional, [.band])
        XCTAssertTrue(movement.needsEquipment)
        XCTAssertEqual(movement.regions, [.shoulder])
        XCTAssertEqual(movement.bucket, .str)
    }

    func testRegionsAndSettingsCoverTheSchema() {
        XCTAssertEqual(Set(Region.allCases.map(\.rawValue)), Set(library.schema.regions))
        XCTAssertEqual(Set(MovementSetting.allCases.map(\.rawValue)), Set(library.schema.settings))
        XCTAssertEqual(Set(Equipment.allCases.map(\.rawValue)), Set(library.schema.equipment))
    }

    func testDesignRulesAndMicroSpec() {
        XCTAssertEqual(library.designRules.fullBreakSeconds, 300)
        XCTAssertEqual(library.designRules.blocksPerBreak.standard, 4)
        XCTAssertEqual(library.designRules.blocksPerBreak.min, 3)
        XCTAssertEqual(library.designRules.blocksPerBreak.max, 5)
        XCTAssertEqual(library.designRules.blockSecondsRange, [60, 90])
        XCTAssertEqual(library.microBreak.seconds, 60)
        XCTAssertTrue(library.microBreak.eligibility.noFloor)
        XCTAssertTrue(library.microBreak.eligibility.noEquipment)
        XCTAssertEqual(library.microBreak.eligibility.maxBlockSeconds, 60)
        XCTAssertEqual(library.chainingRules.count, 8)
        XCTAssertEqual(library.balanceProgression.count, 6)
        XCTAssertEqual(library.sittingEffects.count, 9)
    }

    func testValidationRejectsATruncatedLibrary() throws {
        let url = try XCTUnwrap(LibraryLoader.bundledURL())
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var movements = try XCTUnwrap(json["movements"] as? [Any])
        movements.removeLast()
        json["movements"] = movements

        let corrupted = try JSONSerialization.data(withJSONObject: json)
        let library = try JSONDecoder().decode(MovementLibrary.self, from: corrupted)
        XCTAssertThrowsError(try LibraryLoader.validate(library)) { error in
            guard case LibraryError.validation(let reason)? = error as? LibraryError else {
                return XCTFail("expected a validation error, got \(error)")
            }
            XCTAssertTrue(reason.contains("146"), reason)
        }
    }

    func testMissingResourceSurfacesAnError() {
        let url = URL(fileURLWithPath: "/nonexistent/movement-library-v4.json")
        XCTAssertThrowsError(try LibraryLoader.load(from: url)) { error in
            guard case LibraryError.unreadable? = error as? LibraryError else {
                return XCTFail("expected an unreadable error, got \(error)")
            }
        }
    }
}
