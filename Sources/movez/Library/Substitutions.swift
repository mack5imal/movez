import Foundation

/// Bodyweight replacements for the 18 movements that list optional equipment.
///
/// Chaining rule 6 in the library document names three explicit swaps; everything else falls back
/// to "the bodyweight peer with the same Counteracts value". The ladder below adds the two tiers
/// the document leaves implicit so that every equipment movement resolves to something:
///
/// 1. the explicit table
/// 2. same bucket, no equipment, identical `counteracts`, closest `block_seconds`
/// 3. same bucket, no equipment, overlapping region, most overlap then closest `block_seconds`
/// 4. any bucket, no equipment, overlapping region (needed for FLX-38, the only foot-roller
///    movement, which has no equipment-free peer inside FLX)
enum Substitutions {
    /// Chaining rule 6's named swaps, in the order the document lists them.
    static let explicit: [String: [String]] = [
        "STR-17": ["FLX-18", "STR-16"],
        "STR-09": ["STR-04"],
        "CIR-18": ["CIR-12"]
    ]

    /// Every bodyweight movement that can stand in for `movement`, best first. Never empty for a
    /// movement in the shipped library; empty only for a movement that needs no substitute.
    static func bodyweightPeers(for movement: Movement, in library: MovementLibrary) -> [Movement] {
        guard movement.needsEquipment else { return [] }

        if let ids = explicit[movement.id] {
            let resolved = ids.compactMap { library.movement(id: $0) }
            if !resolved.isEmpty { return resolved }
        }

        let sameBucket = library.movements(in: movement.bucket).filter { $0.id != movement.id && !$0.needsEquipment }

        let sameCounteracts = sameBucket.filter { $0.counteracts == movement.counteracts }
        if !sameCounteracts.isEmpty {
            return sameCounteracts.sorted { closer($0, $1, to: movement) }
        }

        let overlappingInBucket = sameBucket.filter { !$0.sharedRegions(with: movement).isEmpty }
        if !overlappingInBucket.isEmpty {
            return overlappingInBucket.sorted { betterRegionMatch($0, $1, for: movement) }
        }

        let overlappingAnywhere = library.movements
            .filter { $0.id != movement.id && !$0.needsEquipment && !$0.sharedRegions(with: movement).isEmpty }
        return overlappingAnywhere.sorted { betterRegionMatch($0, $1, for: movement) }
    }

    /// The single best bodyweight replacement, or nil when the movement needs no substitute.
    static func bodyweightPeer(for movement: Movement, library: MovementLibrary) -> Movement? {
        bodyweightPeers(for: movement, in: library).first
    }

    /// Replaces `movement` when the user owns none of its equipment; otherwise returns it unchanged.
    static func resolve(_ movement: Movement, owned: Set<Equipment>, in library: MovementLibrary) -> Movement {
        guard movement.needsEquipment else { return movement }
        if !owned.isDisjoint(with: movement.equipmentOptional) { return movement }
        return bodyweightPeer(for: movement, library: library) ?? movement
    }

    private static func closer(_ lhs: Movement, _ rhs: Movement, to movement: Movement) -> Bool {
        let left = abs(lhs.blockSeconds - movement.blockSeconds)
        let right = abs(rhs.blockSeconds - movement.blockSeconds)
        if left != right { return left < right }
        return lhs.id < rhs.id
    }

    private static func betterRegionMatch(_ lhs: Movement, _ rhs: Movement, for movement: Movement) -> Bool {
        let left = lhs.sharedRegions(with: movement).count
        let right = rhs.sharedRegions(with: movement).count
        if left != right { return left > right }
        return closer(lhs, rhs, to: movement)
    }
}
