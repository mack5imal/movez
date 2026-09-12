import Foundation

/// Everything that can go wrong between the bundled JSON and a validated `MovementLibrary`.
///
/// Nothing here is ever swallowed: a corrupt or missing library is a loud, user-visible failure
/// rather than a silently empty app.
enum LibraryError: LocalizedError, Equatable {
    case resourceMissing(String)
    case unreadable(String)
    case decoding(String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "The movement library \(name) is missing from the app bundle."
        case .unreadable(let reason): return "The movement library could not be read: \(reason)"
        case .decoding(let reason): return "The movement library could not be decoded: \(reason)"
        case .validation(let reason): return "The movement library failed validation: \(reason)"
        }
    }
}

enum LibraryLoader {
    static let resourceName = "movement-library-v4"
    static let resourceExtension = "json"

    /// Counts the shipped v4 library is expected to have. A mismatch means the bundled JSON and
    /// the code have drifted apart, which would silently change every generated routine.
    enum Expected {
        static let movements = 147
        static let microEligible = 65
        static let routines = 9
        static let microRoutines = 8
        static let presets = 3
    }

    /// Loads and validates the library bundled with the app.
    static func loadBundled() throws -> MovementLibrary {
        guard let url = bundledURL() else {
            throw LibraryError.resourceMissing("\(resourceName).\(resourceExtension)")
        }
        return try load(from: url)
    }

    /// Loads and validates a library from an arbitrary URL.
    static func load(from url: URL) throws -> MovementLibrary {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LibraryError.unreadable(error.localizedDescription)
        }

        let library: MovementLibrary
        do {
            library = try JSONDecoder().decode(MovementLibrary.self, from: data)
        } catch {
            throw LibraryError.decoding(String(describing: error))
        }

        try validate(library)
        return library
    }

    /// The bundled library, searched in the app bundle and — for offscreen tooling run from the
    /// source tree — next to the repository root.
    static func bundledURL() -> URL? {
        if let url = MovezBundle.resources.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }

    /// Throws `LibraryError.validation` on the first structural problem found.
    static func validate(_ library: MovementLibrary) throws {
        try validateMovements(library)
        try validateCollections(library)
        try validateRoutines(library)
    }

    private static func validateMovements(_ library: MovementLibrary) throws {
        let movements = library.movements

        guard movements.count == Expected.movements else {
            throw LibraryError.validation("expected \(Expected.movements) movements, found \(movements.count)")
        }

        let ids = Set(movements.map(\.id))
        guard ids.count == movements.count else {
            let duplicates = Dictionary(grouping: movements, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
            throw LibraryError.validation("duplicate movement ids: \(duplicates.joined(separator: ", "))")
        }

        let microCount = movements.filter(\.microEligible).count
        guard microCount == Expected.microEligible else {
            throw LibraryError.validation("expected \(Expected.microEligible) micro-eligible movements, found \(microCount)")
        }

        for info in library.buckets {
            let actual = library.movements(in: info.id).count
            guard actual == info.count else {
                throw LibraryError.validation("bucket \(info.id.rawValue) declares \(info.count) movements, found \(actual)")
            }
        }
    }

    private static func validateCollections(_ library: MovementLibrary) throws {
        guard library.routines.count == Expected.routines else {
            throw LibraryError.validation("expected \(Expected.routines) routines, found \(library.routines.count)")
        }
        guard library.microRoutines.count == Expected.microRoutines else {
            throw LibraryError.validation(
                "expected \(Expected.microRoutines) micro-routines, found \(library.microRoutines.count)"
            )
        }
        guard library.presets.count == Expected.presets else {
            throw LibraryError.validation("expected \(Expected.presets) presets, found \(library.presets.count)")
        }
        guard library.presets.contains(where: \.isDefault) else {
            throw LibraryError.validation("no preset is marked default")
        }
    }

    private static func validateRoutines(_ library: MovementLibrary) throws {
        let ids = Set(library.movements.map(\.id))
        for routine in library.routines {
            try validateBlocks(
                routine.blocks,
                id: routine.id,
                target: routine.targetSeconds,
                sum: routine.sumOfBlocks,
                ids: ids
            )
        }
        for routine in library.microRoutines {
            try validateBlocks(
                routine.blocks,
                id: routine.id,
                target: routine.targetSeconds,
                sum: routine.sumOfBlocks,
                ids: ids
            )
        }
    }

    private static func validateBlocks(
        _ blocks: [TemplateBlock],
        id: String,
        target: Int,
        sum: Int,
        ids: Set<String>
    ) throws {
        for block in blocks where !ids.contains(block.movementId) {
            throw LibraryError.validation("routine \(id) references unknown movement \(block.movementId)")
        }
        guard sum == target else {
            throw LibraryError.validation("routine \(id) sums to \(sum) but targets \(target)")
        }
        let actual = blocks.reduce(0) { $0 + $1.seconds }
        guard actual == sum else {
            throw LibraryError.validation("routine \(id) blocks total \(actual) but sum_of_blocks says \(sum)")
        }
    }
}
