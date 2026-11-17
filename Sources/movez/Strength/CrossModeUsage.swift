import Foundation

/// What has been used today, as both modes' builders must see it (S8).
///
/// A day can mix modes, and the two libraries describe some exercises twice: a strength move whose
/// `v4_overlap` is `same` is the same exercise as its movement-library id, and that id counts
/// together with its whole family (DECISIONS 45). So a served id is widened to everything it is the
/// same as before either builder reads it. A `similar` overlap is related but different enough to
/// share a day, so it widens nothing.
struct CrossModeUsage: Hashable {
    /// The day's used set, in each library's own ids.
    struct Used: Hashable {
        /// Movement-library ids a movement builder must not serve again today.
        var movementIds: Set<String> = []
        /// Strength-library ids a strength builder must not serve again today.
        var strengthIds: Set<String> = []
    }

    private let families: FamilyIndex
    private let membersByFamily: [String: Set<String>]
    /// Each strength id with a `same` overlap, and the movement-library id it is the same as.
    private let sameMovementByStrength: [String: String]

    init(movementLibrary: MovementLibrary, strengthLibrary: StrengthLibrary) {
        families = FamilyIndex(library: movementLibrary)
        membersByFamily = Dictionary(grouping: movementLibrary.movements, by: \.familyKey)
            .mapValues { Set($0.map(\.id)) }
        var same: [String: String] = [:]
        for movement in strengthLibrary.movements {
            guard let overlap = movement.v4Overlap, overlap.kind == .same else { continue }
            same[movement.id] = overlap.id
        }
        sameMovementByStrength = same
    }

    /// Widens today's served ids from both libraries into the set each builder excludes.
    ///
    /// Every family touched today, whether by a movement served directly or by the `same`
    /// counterpart of a strength move, is used up whole in both libraries: all its movement ids,
    /// and every strength id that is `same` as any of its members.
    func used(movementIds servedMovements: Set<String>, strengthIds servedStrength: Set<String>) -> Used {
        var usedFamilies = families.keys(of: servedMovements)
        for id in servedStrength {
            if let counterpart = sameMovementByStrength[id] { usedFamilies.insert(families.key(of: counterpart)) }
        }

        var used = Used(movementIds: servedMovements, strengthIds: servedStrength)
        for family in usedFamilies {
            // An id the library no longer knows is a family of one, already in the served set.
            used.movementIds.formUnion(membersByFamily[family] ?? [])
        }
        for (strengthId, counterpart) in sameMovementByStrength where usedFamilies.contains(families.key(of: counterpart)) {
            used.strengthIds.insert(strengthId)
        }
        return used
    }
}
