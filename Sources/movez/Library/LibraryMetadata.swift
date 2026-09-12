import Foundation

/// The self-describing header of the library JSON: the field glossary and the vocabularies the
/// enums mirror. Kept decoded so the debug inspector can show what the shipped file claims.
struct LibrarySchema: Codable, Hashable {
    let movement: [String: String]
    let regions: [String]
    let settings: [String]
    let equipment: [String]
}

/// The shape a full break is built to.
struct DesignRules: Codable, Hashable {
    let fullBreakSeconds: Int
    let blocksPerBreak: BlocksPerBreak
    let blockSecondsRange: [Int]
    let microBreakSeconds: Int
    let intensity: String
    let goal: String

    enum CodingKeys: String, CodingKey {
        case intensity, goal
        case fullBreakSeconds = "full_break_seconds"
        case blocksPerBreak = "blocks_per_break"
        case blockSecondsRange = "block_seconds_range"
        case microBreakSeconds = "micro_break_seconds"
    }

    var minBlockSeconds: Int { blockSecondsRange.first ?? 60 }
    var maxBlockSeconds: Int { blockSecondsRange.last ?? 90 }
}

struct BlocksPerBreak: Codable, Hashable {
    let standard: Int
    let min: Int
    let max: Int

    enum CodingKeys: String, CodingKey {
        case standard = "default"
        case min, max
    }
}

/// One documented consequence of prolonged sitting and the buckets that answer it.
struct SittingEffect: Codable, Hashable {
    let effect: String
    let primary: String
    let secondary: String
}

/// A bucket's declared name and movement count, used to cross-check the decoded movements.
struct BucketInfo: Codable, Hashable, Identifiable {
    let id: Bucket
    let name: String
    let count: Int
}

/// The micro-break contract from the library document.
struct MicroBreakSpec: Codable, Hashable {
    let seconds: Int
    let structure: String
    let eligibility: MicroEligibility
    let rules: [String]
}

struct MicroEligibility: Codable, Hashable {
    let maxBlockSeconds: Int
    let noFloor: Bool
    let noEquipment: Bool
    let noWarmup: Bool
    let noSweat: Bool

    enum CodingKeys: String, CodingKey {
        case maxBlockSeconds = "max_block_seconds"
        case noFloor = "no_floor"
        case noEquipment = "no_equipment"
        case noWarmup = "no_warmup"
        case noSweat = "no_sweat"
    }
}
