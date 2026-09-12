import Foundation

/// Where a movement can be performed. Raw values match `schema.settings` exactly.
enum MovementSetting: String, Codable, CaseIterable, Hashable {
    case any = "Any"
    case chair = "Chair"
    case desk = "Desk"
    case floor = "Floor"
    case stand = "Stand"
    case wall = "Wall"

    var displayName: String { rawValue }
}
