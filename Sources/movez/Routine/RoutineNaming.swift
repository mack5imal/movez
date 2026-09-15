import Foundation

/// How a generated routine is titled in the overlay eyebrow, the menu subtitle and the
/// completion screen.
struct RoutineName: Hashable {
    let name: String
    let focus: String
    let completionTitle: String

    /// "HIP RESET · HIPS AND GLUTES" — the overlay eyebrow.
    var eyebrow: String { "\(name) · \(focus)".uppercased() }

    /// "Hip reset · hips and glutes" — the menu subtitle.
    var subtitle: String { "\(name) · \(focus)" }
}

enum RoutineNaming {
    /// The region-slot table. Time of day overrides it for the first, last and post-lunch breaks.
    static func name(slot: RotationSlot, timeOfDay: TimeOfDay) -> RoutineName {
        if let override = timeOfDayName(timeOfDay) { return override }
        return slotName(slot)
    }

    /// The slot a built routine is named for: the one whose regions its stretch and
    /// strength-or-balance blocks work for the most seconds.
    ///
    /// The rotation slot only weights selection, so the movements often come from elsewhere, and
    /// naming by the planned slot put "Upper back opener" over leg swings and squats. Ties go to
    /// the planned slot. A routine whose working blocks match no slot is named for its warm-up,
    /// and failing that for the plan.
    static func contentSlot(for blocks: [RoutineBlock], planned: RotationSlot) -> RotationSlot {
        let working = blocks.filter { workingBuckets.contains($0.movement.bucket) }
        let warmUp = blocks.filter { $0.movement.bucket == .cir }
        return bestSlot(for: working, planned: planned) ?? bestSlot(for: warmUp, planned: planned) ?? planned
    }

    private static let workingBuckets: Set<Bucket> = [.flx, .str, .bal]

    private static func bestSlot(for blocks: [RoutineBlock], planned: RotationSlot) -> RotationSlot? {
        var best: RotationSlot?
        var bestSeconds = 0
        for slot in RotationSlot.allCases {
            let seconds = blocks
                .filter { !Set($0.movement.regions).isDisjoint(with: slot.regions) }
                .reduce(0) { $0 + $1.seconds }
            if seconds > bestSeconds || (seconds > 0 && seconds == bestSeconds && slot == planned) {
                best = slot
                bestSeconds = seconds
            }
        }
        return best
    }

    static func slotName(_ slot: RotationSlot) -> RoutineName {
        switch slot {
        case .hip:
            return RoutineName(name: "Hip reset", focus: "hips and glutes", completionTitle: "Hips reset")
        case .tSpineChest:
            return RoutineName(name: "Upper back opener", focus: "t-spine and chest", completionTitle: "Upper back opened")
        case .neckShoulder:
            return RoutineName(name: "Neck and shoulders", focus: "forward head", completionTitle: "Neck released")
        case .posteriorChain:
            return RoutineName(name: "Posterior chain", focus: "glutes and hamstrings", completionTitle: "Chain switched on")
        case .core:
            return RoutineName(name: "Core and spine", focus: "trunk and low back", completionTitle: "Core awake")
        case .ankleFoot:
            return RoutineName(name: "Ankles and feet", focus: "balance base", completionTitle: "Feet awake")
        }
    }

    static func timeOfDayName(_ timeOfDay: TimeOfDay) -> RoutineName? {
        switch timeOfDay {
        case .first:
            return RoutineName(name: "Wake-up", focus: "full body", completionTitle: "Awake")
        case .last:
            return RoutineName(name: "Wind-down", focus: "flexibility and breath", completionTitle: "Wound down")
        case .postLunch:
            return RoutineName(name: "Balance and circulation", focus: "post-lunch", completionTitle: "Blood moving")
        case .mid, .normal:
            return nil
        }
    }
}
