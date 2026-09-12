import Foundation

/// The seven movement families in the library. Raw values are the id prefixes used in the JSON.
enum Bucket: String, Codable, CaseIterable, Hashable {
    case flx = "FLX"
    case cir = "CIR"
    case str = "STR"
    case bal = "BAL"
    case hwf = "HWF"
    case eye = "EYE"
    case bre = "BRE"

    var displayName: String {
        switch self {
        case .flx: return "Flexibility & mobility"
        case .cir: return "Circulation & metabolic"
        case .str: return "Strength"
        case .bal: return "Balance & proprioception"
        case .hwf: return "Hands, wrists & forearms"
        case .eye: return "Eyes"
        case .bre: return "Breath & posture"
        }
    }
}
