import XCTest
@testable import movez

final class StrengthLibraryTests: XCTestCase {
    private static let movementLibrary: MovementLibrary = {
        do {
            return try LibraryLoader.loadBundled()
        } catch {
            fatalError("Bundled movement library failed to load: \(error)")
        }
    }()

    private static let library: StrengthLibrary = {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: movementLibrary)
        } catch {
            fatalError("Bundled strength library failed to load: \(error)")
        }
    }()

    private var library: StrengthLibrary { Self.library }

    func testDecodesEveryMovement() {
        XCTAssertEqual(library.movements.count, 145)
        XCTAssertEqual(library.mode, "strength")
        XCTAssertEqual(library.version, "1")
    }

    func testBucketCounts() {
        let expected: [StrengthBucket: Int] = [.sqt: 16, .hng: 18, .psh: 18, .pul: 23, .cor: 18, .acc: 11, .end: 41]
        XCTAssertEqual(StrengthBucket.allCases.count, 7)
        XCTAssertEqual(library.buckets.count, 7)
        for (bucket, count) in expected {
            XCTAssertEqual(library.movements(in: bucket).count, count, "bucket \(bucket.rawValue)")
        }
        XCTAssertEqual(expected.values.reduce(0, +), 145)
        for info in library.buckets {
            XCTAssertEqual(info.count, expected[info.id], "declared count for \(info.id.rawValue)")
        }
    }

    func testTheMicroPoolIsEveryEndMovement() {
        XCTAssertEqual(library.microEligible.count, 41)
        XCTAssertTrue(library.microEligible.allSatisfy { $0.bucket == .end })
        XCTAssertEqual(Set(library.microEligible.map(\.id)), Set(library.movements(in: .end).map(\.id)))
    }

    func testEveryOverlapResolvesToAMovementLibraryMovement() {
        let overlaps = library.movements.compactMap(\.v4Overlap)
        XCTAssertFalse(overlaps.isEmpty)
        for overlap in overlaps {
            XCTAssertNotNil(Self.movementLibrary.movement(id: overlap.id), overlap.id)
        }
    }

    func testTheFieldsTheBuildersNeedAreDecoded() {
        XCTAssertTrue(library.movements.contains { $0.regions.contains(.arm) })
        XCTAssertTrue(library.movements.contains { $0.load != nil })
        XCTAssertTrue(library.movements.contains(where: \.gripDemand))
        XCTAssertTrue(library.movements.contains(where: \.onFloor))
        XCTAssertTrue(library.movements.contains { $0.equipment.contains(.kettlebell) })
        XCTAssertTrue(library.movements.contains { $0.v4Overlap?.kind == .same })
        XCTAssertEqual(Set(library.movements.map(\.blockSeconds)), [30, 60])
        for movement in library.movements {
            XCTAssertFalse(movement.dose.isEmpty, movement.id)
            XCTAssertFalse(movement.instructions.isEmpty, movement.id)
            XCTAssertFalse(movement.settings.isEmpty, movement.id)
            XCTAssertTrue((1...3).contains(movement.difficulty), movement.id)
            XCTAssertEqual(movement.isBodyweight, movement.load == nil, "\(movement.id) load agrees with its equipment")
        }
    }

    // MARK: - Malformed files

    func testATruncatedFileThrows() throws {
        let data = try Data(contentsOf: try XCTUnwrap(StrengthLibraryLoader.bundledURL()))
        let url = try write(data.prefix(data.count / 2))
        XCTAssertThrowsError(try StrengthLibraryLoader.load(from: url, movementLibrary: Self.movementLibrary)) { error in
            guard case LibraryError.decoding? = error as? LibraryError else {
                return XCTFail("expected a decoding error, got \(error)")
            }
        }
    }

    func testADuplicateIdThrows() throws {
        let url = try mutatedCopy { json in
            var movements = try XCTUnwrap(json["movements"] as? [[String: Any]])
            let first = try XCTUnwrap(movements.first?["id"] as? String)
            movements[1]["id"] = first
            json["movements"] = movements
        }
        XCTAssertThrowsError(try StrengthLibraryLoader.load(from: url, movementLibrary: Self.movementLibrary)) { error in
            guard case LibraryError.validation(let reason)? = error as? LibraryError else {
                return XCTFail("expected a validation error, got \(error)")
            }
            XCTAssertTrue(reason.hasPrefix("duplicate strength movement ids"), reason)
        }
    }

    func testAnUnknownOverlapThrows() throws {
        let url = try mutatedCopy { json in
            var movements = try XCTUnwrap(json["movements"] as? [[String: Any]])
            movements[0]["v4_overlap"] = ["id": "XYZ-99", "kind": "same"]
            json["movements"] = movements
        }
        XCTAssertThrowsError(try StrengthLibraryLoader.load(from: url, movementLibrary: Self.movementLibrary)) { error in
            guard case LibraryError.validation(let reason)? = error as? LibraryError else {
                return XCTFail("expected a validation error, got \(error)")
            }
            XCTAssertTrue(reason.hasSuffix("overlaps the unknown movement XYZ-99"), reason)
        }
    }

    func testMissingResourceSurfacesAnError() {
        let url = URL(fileURLWithPath: "/nonexistent/strength-library-v1.json")
        XCTAssertThrowsError(try StrengthLibraryLoader.load(from: url, movementLibrary: Self.movementLibrary)) { error in
            guard case LibraryError.unreadable? = error as? LibraryError else {
                return XCTFail("expected an unreadable error, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// The bundled JSON, changed by `mutate` and written to a scratch file.
    private func mutatedCopy(_ mutate: (inout [String: Any]) throws -> Void) throws -> URL {
        let source = try XCTUnwrap(StrengthLibraryLoader.bundledURL())
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        try mutate(&json)
        return try write(JSONSerialization.data(withJSONObject: json))
    }

    /// Writes `data` to a fresh temporary directory that is removed when the test ends.
    private func write(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrengthLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("strength-library-v1.json")
        try data.write(to: url)
        return url
    }
}
