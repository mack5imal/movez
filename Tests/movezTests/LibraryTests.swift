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
        XCTAssertEqual(library.movements.count, 174)
        XCTAssertEqual(library.microEligible.count, 79)
        XCTAssertEqual(library.microBreak.eligibleCount, 79)
        XCTAssertEqual(library.version, "4.2")
    }

    func testBucketCounts() {
        let expected: [Bucket: Int] = [.flx: 44, .cir: 20, .str: 58, .bal: 30, .hwf: 11, .eye: 5, .bre: 6]
        XCTAssertEqual(Bucket.allCases.count, 7)
        for (bucket, count) in expected {
            XCTAssertEqual(library.movements(in: bucket).count, count, "bucket \(bucket.rawValue)")
        }
        XCTAssertEqual(expected.values.reduce(0, +), 174)
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
            XCTAssertTrue(reason.contains("173"), reason)
        }
    }

    // MARK: - Version

    /// A library revision bumps the JSON's `version` and the Markdown's title together, and keeps
    /// the major version the resource is named after; the Settings footer shows whatever the JSON
    /// says, so a forgotten half would show up there as a mismatch.
    func testTheVersionAgreesAcrossTheJSONTheMarkdownAndTheFilename() throws {
        let major = library.version.split(separator: ".").first.map(String.init)
        XCTAssertEqual(LibraryLoader.resourceName, "movement-library-v\(major ?? "")")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdown = try String(contentsOf: root.appendingPathComponent("\(LibraryLoader.resourceName).md"), encoding: .utf8)
        XCTAssertTrue(
            markdown.hasPrefix("# movez — Movement Library v\(library.version)\n"),
            String(markdown.prefix(60))
        )
    }

    // MARK: - What a movement requires

    func testEveryMovementSaysWhatItRequires() {
        XCTAssertEqual(library.movements.filter { $0.requires.contains(.floor) }.count, 39)
        XCTAssertEqual(library.movements.filter { $0.requires.contains(.wall) }.map(\.id).sorted(),
                       ["FLX-16", "FLX-17", "FLX-29", "FLX-42", "STR-11", "STR-31", "STR-37", "STR-54"])
        XCTAssertEqual(library.movements.filter { $0.requires.contains(.stairs) }.map(\.id).sorted(),
                       ["CIR-03", "CIR-17", "STR-07"])
        for movement in library.movements where movement.settings == [.floor] {
            XCTAssertTrue(movement.requiresFloor, "\(movement.id) can only be done on the floor")
        }
    }

    /// Only what is required is listed: a wall for balance, or a choice of surfaces, is not.
    func testOptionalSupportIsNotARequirement() throws {
        XCTAssertEqual(try XCTUnwrap(library.movement(id: "FLX-03")).requires, [.floor], "a wall or a chair will do")
        XCTAssertEqual(try XCTUnwrap(library.movement(id: "BAL-14")).requires, [], "fingertips on a wall are optional")
        XCTAssertEqual(try XCTUnwrap(library.movement(id: "FLX-30")).requires, [], "half-kneel or stand")
        XCTAssertEqual(try XCTUnwrap(library.movement(id: "BAL-16")).requires, [], "desk or wall")
        XCTAssertEqual(try XCTUnwrap(library.movement(id: "STR-03")).requires, [.floor], "sitting on the floor")
    }

    func testNothingThatNeedsTheFloorIsMicro() {
        XCTAssertTrue(library.microEligible.allSatisfy { !$0.requiresFloor })
    }

    func testValidationRejectsAFloorMovementTaggedMicro() throws {
        let url = try XCTUnwrap(LibraryLoader.bundledURL())
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var movements = try XCTUnwrap(json["movements"] as? [[String: Any]])
        let index = try XCTUnwrap(movements.firstIndex { $0["id"] as? String == "STR-39" })
        let previous = try XCTUnwrap(movements.firstIndex { $0["id"] as? String == "STR-48" })
        movements[index]["micro_eligible"] = true
        movements[previous]["micro_eligible"] = false
        json["movements"] = movements

        let library = try JSONDecoder().decode(MovementLibrary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try LibraryLoader.validate(library)) { error in
            XCTAssertEqual(error as? LibraryError, .validation("STR-39 needs the floor but is tagged Micro"))
        }
    }

    // MARK: - Families

    func testEveryFamilyIsDeclaredAndHasAtLeastTwoMembers() {
        let declared = Set(library.families.map(\.id))
        XCTAssertEqual(declared.count, library.families.count, "a family is declared twice")
        for movement in library.movements {
            if let family = movement.family {
                XCTAssertTrue(declared.contains(family), "\(movement.id) names \(family)")
            }
        }
        for family in library.families {
            let members = library.movements.filter { $0.family == family.id }
            XCTAssertGreaterThanOrEqual(members.count, 2, family.id)
            XCTAssertFalse(family.name.isEmpty, family.id)
        }
    }

    /// The two cases that prompted families: a calf raise and its held twin served back to back,
    /// and three hip-flexor stretches in one day.
    func testTheNearDuplicatesThatPromptedFamiliesShareOne() throws {
        let index = FamilyIndex(library: library)
        XCTAssertEqual(index.key(of: "STR-26"), index.key(of: "BAL-13"))
        XCTAssertEqual(index.keys(of: ["FLX-01", "FLX-02", "FLX-03", "BAL-18"]).count, 1)
        XCTAssertEqual(index.key(of: "CIR-01"), "CIR-01", "a movement outside a family is a family of one")
        XCTAssertEqual(index.key(of: "XYZ-99"), "XYZ-99", "an id the library no longer has is a family of one")
    }

    func testFamilyRecencyIsSummedAcrossMembers() {
        let index = FamilyIndex(library: library)
        let scores = index.scores(["FLX-01": 1, "FLX-02": 0.5, "CIR-01": 1])
        XCTAssertEqual(scores[index.key(of: "FLX-03")], 1.5)
        XCTAssertEqual(scores["CIR-01"], 1)
    }

    func testValidationRejectsAnUndeclaredFamily() throws {
        let library = try mutatedLibrary { json in
            var movements = try XCTUnwrap(json["movements"] as? [[String: Any]])
            let index = try XCTUnwrap(movements.firstIndex { $0["id"] as? String == "CIR-01" })
            movements[index]["family"] = "walks"
            json["movements"] = movements
        }
        XCTAssertThrowsError(try LibraryLoader.validate(library)) { error in
            XCTAssertEqual(error as? LibraryError, .validation("CIR-01 names the undeclared family walks"))
        }
    }

    func testValidationRejectsAFamilyOfOne() throws {
        let library = try mutatedLibrary { json in
            var families = try XCTUnwrap(json["families"] as? [[String: Any]])
            families.append(["id": "walks", "name": "Walks"])
            json["families"] = families
            var movements = try XCTUnwrap(json["movements"] as? [[String: Any]])
            let index = try XCTUnwrap(movements.firstIndex { $0["id"] as? String == "CIR-01" })
            movements[index]["family"] = "walks"
            json["movements"] = movements
        }
        XCTAssertThrowsError(try LibraryLoader.validate(library)) { error in
            XCTAssertEqual(error as? LibraryError, .validation("family walks has fewer than two movements"))
        }
    }

    /// The bundled JSON, changed by `mutate` and decoded without validation.
    private func mutatedLibrary(_ mutate: (inout [String: Any]) throws -> Void) throws -> MovementLibrary {
        let url = try XCTUnwrap(LibraryLoader.bundledURL())
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        try mutate(&json)
        return try JSONDecoder().decode(MovementLibrary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Sides

    /// Both hands can circle their thumbs or turn their forearms at the same time, so the minute
    /// is not split.
    func testTheHandMovementsDoneWithBothHandsAtOnceHaveNoSides() throws {
        for id in ["HWF-07", "HWF-08"] {
            XCTAssertFalse(try XCTUnwrap(library.movement(id: id)).perSide, id)
        }
    }

    /// A movement that alternates rep by rep has no left half and right half, so the break never
    /// chimes halfway or says "THEN RIGHT" over instructions that say to alternate.
    func testAlternatingMovementsHaveNoSides() throws {
        let alternating = ["FLX-09", "FLX-27", "CIR-19", "STR-06", "STR-12", "STR-13", "BAL-11", "BAL-12", "BAL-21"]
        for id in alternating {
            XCTAssertFalse(try XCTUnwrap(library.movement(id: id)).perSide, id)
        }
        for movement in library.movements where movement.perSide {
            XCTAssertFalse(movement.instructions.lowercased().contains("alternat"), "\(movement.id) alternates but is split into sides")
        }
    }

    // MARK: - v4.2 additions

    func testTheFifteenNewMovementsFillTheGaps() throws {
        let added = (39...44).map { "FLX-\($0)" } + (51...58).map { "STR-\($0)" } + ["BAL-30"]
        for id in added {
            let movement = try XCTUnwrap(library.movement(id: id), id)
            XCTAssertFalse(movement.needsEquipment, id)
            XCTAssertEqual(movement.blockSeconds, 60, id)
            XCTAssertLessThanOrEqual(movement.difficulty, 2, "\(id) would wait behind the difficulty-3 unlock")
        }
        XCTAssertEqual(library.movements(in: .arm).map(\.id).sorted(), ["FLX-41", "FLX-42", "STR-51", "STR-52", "STR-54"])
        let index = FamilyIndex(library: library)
        XCTAssertEqual(index.key(of: "STR-58"), index.key(of: "FLX-09"), "the lateral lunge is the Cossack squat's strength twin")
        XCTAssertEqual(index.key(of: "FLX-43"), index.key(of: "FLX-23"))
        XCTAssertEqual(index.key(of: "STR-54"), index.key(of: "STR-19"))
    }

    /// Isometrics squeeze with both arms at once; the lateral lunge alternates.
    func testTheNewMovementsThatUseBothSidesTogetherHaveNoSides() throws {
        for id in ["STR-51", "STR-52", "STR-54", "STR-57", "STR-58", "BAL-30"] {
            XCTAssertFalse(try XCTUnwrap(library.movement(id: id)).perSide, id)
        }
    }

    func testEveryRegionHasAPlainWord() {
        for region in Region.allCases {
            XCTAssertNotNil(MicroBreak.plainRegionWords[region], region.rawValue)
        }
    }

    // MARK: - Core

    func testTheCoreMovementsAreStrengthAndWorkTheCore() {
        let core = (39...50).compactMap { library.movement(id: "STR-\($0)") }
        XCTAssertEqual(core.map(\.name), [
            "Crunch", "Sit-up", "Lying leg raise", "Scissor kicks", "Bicycle crunch", "Reverse crunch",
            "Hollow body hold", "Alternating heel taps", "V-up", "Standing oblique crunch", "Desk plank",
            "Seated knee tucks"
        ])
        for movement in core {
            XCTAssertEqual(movement.bucket, .str)
            XCTAssertTrue(movement.regions.contains(.lumbarCore), movement.id)
            XCTAssertFalse(movement.needsEquipment, movement.id)
        }
        XCTAssertEqual(core.filter { !$0.requiresFloor }.map(\.id), ["STR-48", "STR-49", "STR-50"],
                       "core work for anyone who won't get down on the floor")
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
