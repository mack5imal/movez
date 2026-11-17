import Foundation

/// The optional emphasis for strength breaks. Separate from the movement `Focus` because the two
/// modes ask different questions: movement focus is about mobility regions, strength focus about
/// which muscles get the extra sets. The raw value is what `SettingsStore` persists.
enum StrengthFocus: String, Hashable, Codable, CaseIterable {
    case none
    case moreLegsAndGlutes
    case moreBackAndShoulders
    case moreCore
    case moreArms

    var displayName: String {
        switch self {
        case .none: return "None"
        case .moreLegsAndGlutes: return "More legs and glutes"
        case .moreBackAndShoulders: return "More back and shoulders"
        case .moreCore: return "More core"
        case .moreArms: return "More arms"
        }
    }
}

extension StrengthEquipment {
    var displayName: String {
        switch self {
        case .dumbbells: return "Dumbbells"
        case .kettlebell: return "Kettlebell"
        }
    }
}

/// What the first-switch setup asks for, saved together when the user confirms it.
struct StrengthSetupChoices: Equatable {
    /// May be empty: a bodyweight-only setup is allowed (the spec overrides the design here).
    var equipment: Set<StrengthEquipment> = []
    var solidWallNearby = true
    var breaksPerDay = SettingsStore.strengthBreaksDefault
    var difficultyCap = SettingsStore.strengthDifficultyDefault
}
