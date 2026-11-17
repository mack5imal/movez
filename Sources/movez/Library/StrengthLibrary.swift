import Foundation

/// The decoded contents of `strength-library-v1.json`.
///
/// Only what the builders read is decoded. The file also carries prose and derived figures
/// (`design_notes`, `coverage`, `overlap_with_movement_library` and so on) for the people editing
/// it; those keys are ignored rather than modelled, so revising them never breaks loading.
struct StrengthLibrary: Codable, Hashable {
    let library: String
    let mode: String
    let version: String
    let buckets: [StrengthBucketInfo]
    let movements: [StrengthMovement]

    // MARK: - Lookups

    func movement(id: String) -> StrengthMovement? {
        movements.first { $0.id == id }
    }

    func movements(in bucket: StrengthBucket) -> [StrengthMovement] {
        movements.filter { $0.bucket == bucket }
    }

    /// The micro-break pool.
    var microEligible: [StrengthMovement] {
        movements.filter(\.microEligible)
    }
}

/// Loads and validates the bundled strength library, failing with the same loud `LibraryError`
/// the movement library uses.
enum StrengthLibraryLoader {
    static let resourceName = "strength-library-v1"
    static let resourceExtension = "json"

    /// The totals the strength builders are written against. Per-bucket counts the JSON declares
    /// for itself, but the total and the micro pool are fixed here so that a file which silently
    /// lost movements, while keeping its own declarations consistent, still fails to load.
    enum Expected {
        static let movements = 145
        static let microEligible = 41
        static let mode = "strength"
    }

    /// Loads and validates the library bundled with the app, checking its overlaps against the
    /// movement library already loaded.
    static func loadBundled(movementLibrary: MovementLibrary) throws -> StrengthLibrary {
        guard let url = bundledURL() else {
            throw LibraryError.resourceMissing("\(resourceName).\(resourceExtension)")
        }
        return try load(from: url, movementLibrary: movementLibrary)
    }

    /// Loads and validates a strength library from an arbitrary URL.
    static func load(from url: URL, movementLibrary: MovementLibrary) throws -> StrengthLibrary {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LibraryError.unreadable(error.localizedDescription)
        }

        let library: StrengthLibrary
        do {
            library = try JSONDecoder().decode(StrengthLibrary.self, from: data)
        } catch {
            throw LibraryError.decoding(String(describing: error))
        }

        try validate(library, movementLibrary: movementLibrary)
        return library
    }

    /// The bundled strength library, searched the same way as the movement library.
    static func bundledURL() -> URL? {
        if let url = MovezBundle.resources.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }

    /// Throws `LibraryError.validation` on the first structural problem found.
    static func validate(_ library: StrengthLibrary, movementLibrary: MovementLibrary) throws {
        guard library.mode == Expected.mode else {
            throw LibraryError.validation("the strength library declares mode \(library.mode)")
        }
        try validateMovements(library)
        try validateMicroPool(library)
        try validateOverlaps(library, movementLibrary: movementLibrary)
    }

    private static func validateMovements(_ library: StrengthLibrary) throws {
        let movements = library.movements
        guard movements.count == Expected.movements else {
            throw LibraryError.validation(
                "expected \(Expected.movements) strength movements, found \(movements.count)"
            )
        }

        let ids = Set(movements.map(\.id))
        guard ids.count == movements.count else {
            let duplicates = Dictionary(grouping: movements, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
            throw LibraryError.validation("duplicate strength movement ids: \(duplicates.joined(separator: ", "))")
        }

        let declaredBuckets = library.buckets.map(\.id)
        guard Set(declaredBuckets) == Set(StrengthBucket.allCases), declaredBuckets.count == StrengthBucket.allCases.count else {
            throw LibraryError.validation("the strength library must declare each of its seven buckets once")
        }
        for info in library.buckets {
            let actual = library.movements(in: info.id).count
            guard actual == info.count else {
                throw LibraryError.validation(
                    "strength bucket \(info.id.rawValue) declares \(info.count) movements, found \(actual)"
                )
            }
        }

        // The id prefix is what keeps the two libraries apart when both are loaded, so a movement
        // filed under the wrong bucket would collide with the wrong pattern's no-repeat rules.
        if let misfiled = movements.first(where: { !$0.id.hasPrefix($0.bucket.rawValue + "-") }) {
            throw LibraryError.validation("\(misfiled.id) is filed under \(misfiled.bucket.rawValue)")
        }
    }

    /// Strength micro-breaks draw from END alone, so a micro-eligible movement anywhere else, or a
    /// pool of the wrong size, means the file and the builders disagree.
    private static func validateMicroPool(_ library: StrengthLibrary) throws {
        if let stray = library.microEligible.first(where: { $0.bucket != .end }) {
            throw LibraryError.validation("\(stray.id) is micro-eligible outside END")
        }
        let count = library.microEligible.count
        guard count == Expected.microEligible else {
            throw LibraryError.validation(
                "expected \(Expected.microEligible) micro-eligible END movements, found \(count)"
            )
        }
    }

    /// An overlap names the movement-library twin the no-repeat rules merge with, so it must exist.
    private static func validateOverlaps(_ library: StrengthLibrary, movementLibrary: MovementLibrary) throws {
        let known = Set(movementLibrary.movements.map(\.id))
        for movement in library.movements {
            guard let overlap = movement.v4Overlap, !known.contains(overlap.id) else { continue }
            throw LibraryError.validation("\(movement.id) overlaps the unknown movement \(overlap.id)")
        }
    }
}
