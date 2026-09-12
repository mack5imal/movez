import Foundation

/// Optional equipment. Every movement tagged with equipment has a bodyweight peer — see `Substitutions`.
enum Equipment: String, Codable, CaseIterable, Hashable {
    case band
    case kettlebellOrDumbbell = "kettlebell_or_dumbbell"
    case foamRoller = "foam_roller"
    case ball

    var displayName: String {
        switch self {
        case .band: return "Band"
        case .kettlebellOrDumbbell: return "Kettlebell or dumbbell"
        case .foamRoller: return "Roller"
        case .ball: return "Ball"
        }
    }
}
