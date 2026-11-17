import Foundation

/// The strength library's seven movement patterns. Raw values are the id prefixes used in
/// `strength-library-v1.json`; they are distinct from `Bucket` so both libraries can load together.
enum StrengthBucket: String, Codable, CaseIterable, Hashable {
    case sqt = "SQT"
    case hng = "HNG"
    case psh = "PSH"
    case pul = "PUL"
    case cor = "COR"
    case acc = "ACC"
    case end = "END"
}

/// Equipment a strength movement can be loaded with. Unlike v4's optional equipment, a strength
/// movement that lists any needs one of them; a bodyweight movement lists none.
enum StrengthEquipment: String, Codable, CaseIterable, Hashable {
    case dumbbells
    case kettlebell
}

/// How heavy the weight should feel on a loaded movement.
enum StrengthLoad: String, Codable, CaseIterable, Hashable {
    case light
    case moderate
    case heavy
}

/// Where a strength movement repeats, or nearly repeats, a movement-library movement.
struct StrengthOverlap: Codable, Hashable {
    /// "Same" is the same exercise, so no-repeat rules treat the two ids as one when modes are mixed
    /// in a day; "similar" is related but different enough to share a day.
    enum Kind: String, Codable, Hashable {
        case same
        case similar
    }

    let id: String
    let kind: Kind
}

/// One movement from `strength-library-v1.json`.
///
/// Kept separate from `Movement` so that movement mode's builders and golden picks cannot change
/// behaviour because a strength field was added; the two share only `Region` and `MovementSetting`,
/// whose raw values both libraries use verbatim.
struct StrengthMovement: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bucket: StrengthBucket
    let regions: [Region]
    /// Display text only, usually a rep target; `blockSeconds` is what the timer runs.
    let dose: String
    let perSide: Bool
    let blockSeconds: Int
    let difficulty: Int
    let settings: [MovementSetting]
    let onFloor: Bool
    let equipment: [StrengthEquipment]
    let load: StrengthLoad?
    let gripDemand: Bool
    let microEligible: Bool
    let instructions: String
    let v4Overlap: StrengthOverlap?

    enum CodingKeys: String, CodingKey {
        case id, name, bucket, regions, dose, difficulty, settings, equipment, load, instructions
        case perSide = "per_side"
        case blockSeconds = "block_seconds"
        case onFloor = "on_floor"
        case gripDemand = "grip_demand"
        case microEligible = "micro_eligible"
        case v4Overlap = "v4_overlap"
    }

    /// True when the movement can be done with no equipment at all.
    var isBodyweight: Bool { equipment.isEmpty }
}

/// A bucket as the strength library declares it, with the count the loader checks against.
struct StrengthBucketInfo: Codable, Hashable {
    let id: StrengthBucket
    let name: String
    let count: Int
}
