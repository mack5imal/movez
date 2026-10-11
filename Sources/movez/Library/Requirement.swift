import Foundation

/// Something a movement cannot be done without. Raw values match the library's `requires` field.
///
/// Only what is required is listed: a wall that steadies a balance pose, or "a stair or a sturdy
/// step" when a desk would do, is not. A user who says they have no wall, no floor they will use, or
/// no stairs is never served a movement that needs one.
enum Requirement: String, Codable, CaseIterable, Hashable {
    case floor
    case wall
    case stairs

    var displayName: String { rawValue }
}
