import Foundation

/// Assembles the micro-break: one per-side movement for the whole minute, thirty seconds a side,
/// or two one-sided movements of thirty seconds each.
///
/// Micro-break rules (library §11): micro-eligible movements only, no floor, no equipment, nothing
/// that needs what the user has said they do not have, and nothing above the difficulty cap. Never a
/// repeat of the last micro-break, never a movement the next full break is about to use, and
/// never anything already served today. Each of those is judged by family (`FamilyIndex`), so a
/// near-duplicate counts as the movement itself, and the two halves of a pair are never one family.
///
/// The movement is drawn straight from the whole pool, weighted only by recency. It used to draw a
/// category first, from lists that rotated with an emphasis, which gave the five eye and three
/// breathing movements the same odds as sixteen stretches: they were served three times as often
/// as anything else.
struct MicroBreakBuilder {
    /// One movement on each side, or one each for two movements.
    static let halfSeconds = 30

    let library: MovementLibrary
    let families: FamilyIndex

    init(library: MovementLibrary) {
        self.library = library
        self.families = FamilyIndex(library: library)
    }

    func build(context: MicroContext) -> MicroBreak {
        var rng = SplitMix64(seed: context.seed)
        let pool = relaxedPool(for: context)

        guard let first = choose(from: pool, context: context, rng: &rng) else {
            return MicroBreak(id: UUID(), blocks: [])
        }
        if first.perSide {
            return MicroBreak(id: UUID(), blocks: [block(first, seconds: Self.halfSeconds * 2)])
        }

        // The second half has to be one-sided: a per-side movement does not fit in thirty seconds.
        let rest = pool.filter { !$0.perSide && $0.familyKey != first.familyKey }
        guard let second = choose(from: rest, context: context, rng: &rng) else {
            return MicroBreak(id: UUID(), blocks: [block(first, seconds: Self.halfSeconds * 2)])
        }
        return MicroBreak(
            id: UUID(),
            blocks: [block(first, seconds: Self.halfSeconds), block(second, seconds: Self.halfSeconds)]
        )
    }

    /// The candidates, with the day's rules let go one at a time until something is left. An empty
    /// micro-break would still be put on screen, with no name in its count-in and two chimes
    /// around nothing, so a repeat or an excluded movement beats it.
    ///
    /// A long day can use up the sixty-odd micro movements, so today goes first. Then the last
    /// micro-break and the next full break, which only a user who has excluded nearly everything
    /// can exhaust. The exclusions go last, as in `RoutineBuilder.relaxedCandidates`. What the
    /// user lacks and the difficulty cap are never let go: plenty of difficulty-1 micro movements
    /// need nothing at all.
    func relaxedPool(for context: MicroContext) -> [Movement] {
        var relaxed = context
        var pool = candidates(for: relaxed)
        if !pool.isEmpty { return pool }

        relaxed.usedMovementIdsToday = []
        pool = candidates(for: relaxed)
        if !pool.isEmpty { return pool }

        relaxed.lastMicroMovementIds = []
        relaxed.nextFullRoutineIds = []
        pool = candidates(for: relaxed)
        if !pool.isEmpty { return pool }

        relaxed.excluded = []
        return candidates(for: relaxed)
    }

    /// Micro-eligible movements the user may be served right now.
    func candidates(for context: MicroContext) -> [Movement] {
        let taken = families.keys(
            of: context.lastMicroMovementIds
                .union(context.nextFullRoutineIds)
                .union(context.usedMovementIdsToday)
        )
        return library.microEligible.filter { movement in
            !movement.needsEquipment
                && !movement.requiresFloor
                && !movement.needsAny(of: context.unavailable)
                && !context.excluded.contains(movement.id)
                && !taken.contains(movement.familyKey)
                && movement.difficulty <= context.difficultyCap
                && (movement.difficulty < 3 || context.unlockedDiff3.contains(movement.id))
        }
    }

    private func choose(from options: [Movement], context: MicroContext, rng: inout SplitMix64) -> Movement? {
        guard !options.isEmpty else { return nil }
        let sorted = options.sorted { $0.id < $1.id }
        let recency = families.scores(context.recency)
        let weights = sorted.map { Recency.multiplier(score: recency[$0.familyKey] ?? 0) }
        guard let index = rng.weightedIndex(in: weights) else { return sorted.first }
        return sorted[index]
    }

    private func block(_ movement: Movement, seconds: Int) -> RoutineBlock {
        RoutineBlock(movement: movement, seconds: seconds)
    }
}
