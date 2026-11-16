import Foundation

/// Everything the strength-break and end-range builders need for one break. Pure data: the same
/// context always builds the same break.
struct StrengthContext: Hashable {
    /// Strength ids already served today in either mode, widened through `CrossModeUsage` so that a
    /// `same` overlap served in a Movement break counts here too (S8).
    var usedStrengthIdsToday: Set<String> = []
    var equipment: Set<StrengthEquipment> = []
    var solidWallNearby = true
    var difficultyCap = SettingsStore.strengthDifficultyDefault
    /// Patterns whose difficulty-3 moves are unlocked (`StrengthUnlock`).
    var unlockedBuckets: Set<StrengthBucket> = []
    var focus: StrengthFocus = .none
    /// How recently each strength move was served, as `Recency` scores it.
    var recency: [String: Double] = [:]
    var excluded: Set<String> = []
    var seed: UInt64 = 0
}

/// Inputs for one strength micro-break.
struct StrengthMicroContext: Hashable {
    /// Strength ids already served today in either mode, widened through `CrossModeUsage`.
    var usedStrengthIdsToday: Set<String> = []
    /// The previous micro-break's moves, whose regions this one leaves alone.
    var lastMicroMovementIds: Set<String> = []
    /// The previous micro-break's regions where its ids are another library's: a Movement
    /// micro-break just before a switch to Strength. Left alone with the strength ids' regions.
    var lastMicroRegions: Set<Region> = []
    /// The next full break's moves, whose regions are avoided when an alternative exists.
    var nextFullBreakIds: Set<String> = []
    var solidWallNearby = true
    var difficultyCap = SettingsStore.strengthDifficultyDefault
    var unlockedBuckets: Set<StrengthBucket> = []
    var recency: [String: Double] = [:]
    var excluded: Set<String> = []
    var seed: UInt64 = 0
}

extension StrengthFocus {
    /// The regions this focus weights up, ×3, in every draw of a strength break: the warm-up and
    /// the cool-down as well as the working sets (DECISIONS 63).
    var boostedRegions: Set<Region> {
        switch self {
        case .none: return []
        case .moreLegsAndGlutes: return [.quad, .glute, .hamstring, .adductor]
        case .moreBackAndShoulders: return [.thoracic, .shoulder]
        case .moreCore: return [.lumbarCore]
        case .moreArms: return [.arm, .wristForearm]
        }
    }
}

/// How a strength move is done, for keeping a micro-break's second move in the first one's
/// position. Floor moves never reach a micro-break, so standing and seated are all there is.
enum StrengthPosture: Hashable {
    case standing
    case seated

    init(_ movement: StrengthMovement) {
        self = movement.settings.contains(.chair) ? .seated : .standing
    }
}

/// The filters every strength builder shares.
enum StrengthEligibility {
    /// What the user can physically do: bodyweight, or a move one of whose listed pieces of kit
    /// they own (so the kettlebell only where a move lists it), and nothing set against a wall when
    /// they have said there is none. Never relaxed short of the last rung.
    static func isPossible(
        _ movement: StrengthMovement,
        equipment: Set<StrengthEquipment>,
        solidWallNearby: Bool
    ) -> Bool {
        if !movement.isBodyweight, equipment.isDisjoint(with: movement.equipment) { return false }
        if !solidWallNearby, movement.settings.contains(.wall) { return false }
        return true
    }

    /// Difficulty within the cap, and difficulty 3 only in a pattern the user has unlocked.
    static func isWithinDifficulty(_ movement: StrengthMovement, cap: Int, unlocked: Set<StrengthBucket>) -> Bool {
        if movement.difficulty > cap { return false }
        if movement.difficulty >= 3, !unlocked.contains(movement.bucket) { return false }
        return true
    }
}

/// The seeded generator and the record of relaxed rules, carried through every draw of one break.
struct StrengthDrawState {
    var rng: SplitMix64
    var relaxed: [StrengthRelaxation] = []
    /// The rules the last draw left let go of, for a draw that takes a second move from the same
    /// pool (a micro-break's partner).
    var letGo: Set<StrengthRelaxation.Rule> = []

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }
}

/// A weighted draw whose rules are let go of one rung at a time, in a fixed order, until the pool
/// has something in it, so a break is never short of a move.
enum StrengthDraw {
    /// Draws one move for `slot`. `candidates` returns the pool with the given rules relaxed;
    /// `ladder` is the order they are relaxed in. Each rung still let go of when the draw is made
    /// is recorded in the state.
    ///
    /// Letting a rule go only makes room; it is no licence to break it. So once the pool has
    /// something in it, each rule let go of before the last is taken back, the most important
    /// first, wherever the pool still has a move that keeps it. Without this a long day that runs
    /// out of unserved moves would also stop keeping the warm-up's shape or the break's one floor
    /// move, rules that moves already served today could still have kept
    /// (`docs/strength-simulation.md`).
    static func pick(
        slot: StrengthRelaxation.Slot,
        ladder: [StrengthRelaxation.Rule],
        state: inout StrengthDrawState,
        weight: (StrengthMovement) -> Double,
        candidates: (Set<StrengthRelaxation.Rule>) -> [StrengthMovement]
    ) -> StrengthMovement? {
        var letGo = Set<StrengthRelaxation.Rule>()
        var order: [StrengthRelaxation.Rule] = []
        var pool = candidates(letGo)
        for rule in ladder where pool.isEmpty {
            letGo.insert(rule)
            order.append(rule)
            pool = candidates(letGo)
        }
        for rule in order.dropLast().reversed() {
            let kept = letGo.subtracting([rule])
            let narrower = candidates(kept)
            if !narrower.isEmpty {
                letGo = kept
                pool = narrower
            }
        }
        for rule in order where letGo.contains(rule) {
            state.relaxed.append(StrengthRelaxation(slot: slot, rule: rule))
        }
        state.letGo = letGo
        return weighted(pool, rng: &state.rng, weight: weight)
    }

    /// One move in proportion to `weight`, from a pool sorted by id so that the draw depends on
    /// the seed alone and not on how the pool was assembled.
    static func weighted(
        _ pool: [StrengthMovement],
        rng: inout SplitMix64,
        weight: (StrengthMovement) -> Double
    ) -> StrengthMovement? {
        guard !pool.isEmpty else { return nil }
        let sorted = pool.sorted { $0.id < $1.id }
        guard let index = rng.weightedIndex(in: sorted.map(weight)) else { return sorted.first }
        return sorted[index]
    }

    /// `preferred` when it leaves anything, else `options`: how a rule that only applies "where
    /// possible" is applied.
    static func preferring(_ options: [StrengthMovement], _ preferred: (StrengthMovement) -> Bool) -> [StrengthMovement] {
        let fresh = options.filter(preferred)
        return fresh.isEmpty ? options : fresh
    }

    /// The recency multiplier, one serving yesterday leaving a third of the weight.
    static func recencyWeight(_ movement: StrengthMovement, recency: [String: Double]) -> Double {
        Recency.multiplier(score: recency[movement.id] ?? 0)
    }
}
