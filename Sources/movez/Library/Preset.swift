import Foundation

/// The identifiers of the shipped cadence presets, plus the user-defined one.
enum PresetId: String, Codable, CaseIterable, Hashable {
    case twentyFiveFive = "25/5"
    case fiftyFiveFive = "55/5"
    case eightyFiveFive = "85/5"
    case custom
}

/// A sit/break cadence from the library.
struct Preset: Codable, Identifiable, Hashable {
    let id: PresetId
    let sitMinutes: Int
    let breakMinutes: Int
    let cycleMinutes: Int
    let microBreaksAtMinutes: [Int]
    let microDefaultOn: Bool
    let label: String
    let summary: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, label
        case sitMinutes = "sit_minutes"
        case breakMinutes = "break_minutes"
        case cycleMinutes = "cycle_minutes"
        case microBreaksAtMinutes = "micro_breaks_at_minutes"
        case microDefaultOn = "micro_default_on"
        case summary = "description"
        case isDefault = "default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PresetId.self, forKey: .id)
        sitMinutes = try container.decode(Int.self, forKey: .sitMinutes)
        breakMinutes = try container.decode(Int.self, forKey: .breakMinutes)
        cycleMinutes = try container.decode(Int.self, forKey: .cycleMinutes)
        microBreaksAtMinutes = try container.decode([Int].self, forKey: .microBreaksAtMinutes)
        microDefaultOn = try container.decode(Bool.self, forKey: .microDefaultOn)
        label = try container.decode(String.self, forKey: .label)
        summary = try container.decode(String.self, forKey: .summary)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    init(
        id: PresetId,
        sitMinutes: Int,
        breakMinutes: Int,
        cycleMinutes: Int,
        microBreaksAtMinutes: [Int],
        microDefaultOn: Bool,
        label: String,
        summary: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.sitMinutes = sitMinutes
        self.breakMinutes = breakMinutes
        self.cycleMinutes = cycleMinutes
        self.microBreaksAtMinutes = microBreaksAtMinutes
        self.microDefaultOn = microDefaultOn
        self.label = label
        self.summary = summary
        self.isDefault = isDefault
    }
}
