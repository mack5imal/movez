import Foundation

/// A group of near-duplicate movements, declared in the library's `families` list: done back to
/// back, its members would feel like the same exercise twice.
struct FamilyInfo: Codable, Hashable {
    let id: String
    let name: String
}

/// Which family each movement belongs to, so the routine builders can treat a family as one
/// movement: never two of it in a break or a day, and a serving of one weights down the rest.
///
/// The builders only ever stopped the same id from repeating, so a single-leg calf raise hold and
/// a single-leg calf raise, filed under balance and strength, could run back to back in one break.
/// A movement outside any family is a family of one, keyed by its own id, which keeps the old
/// per-movement rules exactly as they were.
struct FamilyIndex: Hashable {
    private let keyById: [String: String]

    init(library: MovementLibrary) {
        keyById = Dictionary(uniqueKeysWithValues: library.movements.map { ($0.id, $0.familyKey) })
    }

    /// The family of `id`. An id this library does not know, such as one a later library revision
    /// retired but history still remembers, is a family of one.
    func key(of id: String) -> String {
        keyById[id] ?? id
    }

    func keys<S: Sequence>(of ids: S) -> Set<String> where S.Element == String {
        Set(ids.map(key(of:)))
    }

    /// Recency scores summed per family, so serving one member yesterday counts against all of them.
    func scores(_ recency: [String: Double]) -> [String: Double] {
        recency.reduce(into: [:]) { result, entry in
            result[key(of: entry.key), default: 0] += entry.value
        }
    }
}
