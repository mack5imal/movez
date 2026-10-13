import Foundation

/// One movement from `movement-library-v4.json`.
struct Movement: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bucket: Bucket
    let bucketName: String
    let regions: [Region]
    let dose: String
    let perSide: Bool
    let blockSeconds: Int
    let difficulty: Int
    let settings: [MovementSetting]
    /// What it cannot be done without. Required in the JSON, so an untagged movement fails to load
    /// rather than slipping through as needing nothing.
    let requires: [Requirement]
    /// The family of near-duplicates it belongs to, if any (see `FamilyIndex`).
    let family: String?
    let equipmentOptional: [Equipment]
    let microEligible: Bool
    let counteracts: String
    let instructions: String

    enum CodingKeys: String, CodingKey {
        case id, name, bucket, dose, difficulty, settings, requires, family, counteracts, instructions, regions
        case bucketName = "bucket_name"
        case perSide = "per_side"
        case blockSeconds = "block_seconds"
        case equipmentOptional = "equipment_optional"
        case microEligible = "micro_eligible"
    }

    /// True when the movement needs the floor, which disqualifies it from micro-breaks whatever the
    /// user has to hand.
    var requiresFloor: Bool { requires.contains(.floor) }

    /// True when the movement needs something in `unavailable`.
    func needsAny(of unavailable: Set<Requirement>) -> Bool {
        !unavailable.isDisjoint(with: requires)
    }

    /// What the builders compare to keep near-duplicates apart: the family, or the movement itself
    /// when it has none.
    var familyKey: String { family ?? id }

    /// True when the movement lists optional equipment and therefore needs a peer when the user has none.
    var needsEquipment: Bool { !equipmentOptional.isEmpty }

    /// The regions this movement shares with another.
    func sharedRegions(with other: Movement) -> Set<Region> {
        Set(regions).intersection(other.regions)
    }
}
