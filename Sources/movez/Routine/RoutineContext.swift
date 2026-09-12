import Foundation

/// Where a break falls in the working day. Each value selects a routine shape.
enum TimeOfDay: String, Hashable, Codable, CaseIterable {
    case first
    case mid
    case postLunch
    case last
    case normal
}

/// The optional emphasis a user picks in settings.
enum Focus: String, Hashable, Codable, CaseIterable {
    case none
    case moreBalance
    case moreUpperBack
    case moreHips
    case moreNeckShoulders
    case moreHandsEyes

    var displayName: String {
        switch self {
        case .none: return "None"
        case .moreBalance: return "More balance"
        case .moreUpperBack: return "More upper back"
        case .moreHips: return "More hips"
        case .moreNeckShoulders: return "More neck and shoulders"
        case .moreHandsEyes: return "More hands and eyes"
        }
    }

    /// Regions this focus pushes toward, weighted up during selection.
    var boostedRegions: Set<Region> {
        switch self {
        case .none: return []
        case .moreBalance: return []
        case .moreUpperBack: return [.thoracic, .chest, .shoulder]
        case .moreHips: return [.hip, .glute]
        case .moreNeckShoulders: return [.neck, .shoulder]
        case .moreHandsEyes: return [.wristForearm, .eyes]
        }
    }
}

/// Everything the builder needs to assemble one full break. Pure data: the same context always
/// produces the same routine.
struct RoutineContext: Hashable {
    var date: Date = .init()
    var timeOfDay: TimeOfDay = .normal
    var breakIndexToday: Int = 0
    var usedMovementIdsToday: Set<String> = []
    var usedStrRegionsLastBreak: Set<Region> = []
    var balanceServedToday: Bool = false
    var equipment: Set<Equipment> = []
    var excluded: Set<String> = []
    var focus: Focus = .none
    var difficultyCap: Int = 2
    var unlockedDiff3: Set<String> = []
    var rotationIndex: Int = 0
    var seed: UInt64 = 0

    /// Movements the chaining rules allow to recur inside one day.
    static let alwaysRepeatable: Set<String> = ["CIR-01", "EYE-01", "BRE-01"]

    var slot: RotationSlot { RotationSlot.slot(forRotationIndex: rotationIndex) }
}

/// Inputs for one micro-break.
struct MicroContext: Hashable {
    /// circulation → eyes and hands → posture → circulation …
    enum Emphasis: String, CaseIterable, Hashable, Codable {
        case circulation
        case eyesHands
        case posture

        static func emphasis(forIndex index: Int) -> Emphasis {
            let count = allCases.count
            return allCases[((index % count) + count) % count]
        }
    }

    var emphasisIndex: Int = 0
    var lastMicroMovementIds: Set<String> = []
    var nextFullRoutineIds: Set<String> = []
    var isPostLunch: Bool = false
    var excluded: Set<String> = []
    var equipment: Set<Equipment> = []
    var seed: UInt64 = 0

    var emphasis: Emphasis { Emphasis.emphasis(forIndex: emphasisIndex) }
}
