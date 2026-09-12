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
    let equipmentOptional: [Equipment]
    let microEligible: Bool
    let counteracts: String
    let instructions: String

    enum CodingKeys: String, CodingKey {
        case id, name, bucket, dose, difficulty, settings, counteracts, instructions, regions
        case bucketName = "bucket_name"
        case perSide = "per_side"
        case blockSeconds = "block_seconds"
        case equipmentOptional = "equipment_optional"
        case microEligible = "micro_eligible"
    }

    /// True when the movement can only be done on the floor, which disqualifies it from micro-breaks.
    var isFloor: Bool { settings == [.floor] }

    /// True when the movement lists optional equipment and therefore needs a peer when the user has none.
    var needsEquipment: Bool { !equipmentOptional.isEmpty }

    /// The regions this movement shares with another.
    func sharedRegions(with other: Movement) -> Set<Region> {
        Set(regions).intersection(other.regions)
    }
}
