import Foundation

/// The optional emphasis a user picks in settings. Every focus is a set of body regions: what to
/// work, not which kind of movement to do. Balance is already in every break, so "more balance"
/// had nothing left to ask for.
enum Focus: String, Hashable, Codable, CaseIterable {
    case none
    case moreUpperBack
    case moreHips
    case moreNeckShoulders
    case moreHandsEyes
    case moreCore

    var displayName: String {
        switch self {
        case .none: return "None"
        case .moreUpperBack: return "More upper back"
        case .moreHips: return "More hips"
        case .moreNeckShoulders: return "More neck and shoulders"
        case .moreHandsEyes: return "More hands and eyes"
        case .moreCore: return "More core"
        }
    }

    /// Regions this focus pushes toward, weighted up during selection.
    var boostedRegions: Set<Region> {
        switch self {
        case .none: return []
        case .moreUpperBack: return [.thoracic, .chest, .shoulder]
        case .moreHips: return [.hip, .glute]
        case .moreNeckShoulders: return [.neck, .shoulder]
        case .moreHandsEyes: return [.wristForearm, .eyes]
        case .moreCore: return [.lumbarCore]
        }
    }
}

/// Everything the builder needs to assemble one full break. Pure data: the same context always
/// produces the same routine.
struct RoutineContext: Hashable {
    var date: Date = .init()
    /// Everything served today, in full breaks and micro-breaks alike. Nothing is served twice in
    /// a day.
    var usedMovementIdsToday: Set<String> = []
    var usedStrRegionsLastBreak: Set<Region> = []
    var equipment: Set<Equipment> = []
    var excluded: Set<String> = []
    var focus: Focus = .none
    var difficultyCap: Int = 2
    var unlockedDiff3: Set<String> = []
    /// How recently each movement was served, as `Recency` scores it.
    var recency: [String: Double] = [:]
    var seed: UInt64 = 0
}

/// Inputs for one micro-break.
struct MicroContext: Hashable {
    /// Everything served today, in full breaks and micro-breaks alike.
    var usedMovementIdsToday: Set<String> = []
    var lastMicroMovementIds: Set<String> = []
    var nextFullRoutineIds: Set<String> = []
    var excluded: Set<String> = []
    var equipment: Set<Equipment> = []
    /// How recently each movement was served, as `Recency` scores it.
    var recency: [String: Double] = [:]
    var seed: UInt64 = 0
}
