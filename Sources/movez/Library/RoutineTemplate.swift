import Foundation

/// One block inside a routine template: a movement id and the seconds allotted to it.
struct TemplateBlock: Codable, Hashable {
    let movementId: String
    let seconds: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case seconds, note
        case movementId = "movement_id"
    }
}

/// A worked full-break example from the library (R1…R9).
struct RoutineTemplate: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let focus: String
    let targetSeconds: Int
    let sumOfBlocks: Int
    let blocks: [TemplateBlock]

    enum CodingKeys: String, CodingKey {
        case id, name, focus, blocks
        case targetSeconds = "target_seconds"
        case sumOfBlocks = "sum_of_blocks"
    }
}

/// A worked micro-break example from the library (M1…M8).
struct MicroRoutineTemplate: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let targetSeconds: Int
    let sumOfBlocks: Int
    let blocks: [TemplateBlock]

    enum CodingKeys: String, CodingKey {
        case id, name, blocks
        case targetSeconds = "target_seconds"
        case sumOfBlocks = "sum_of_blocks"
    }
}
