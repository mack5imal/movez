import Foundation

/// Assembles one full break from the library.
///
/// Every break has the same five blocks: a circulation warm-up, then balance, flexibility and
/// strength in a random order, then a closer drawn from the hand, eye and breathing movements as
/// one pool. Each block runs for a minute. Within a block the draw is weighted only by how recently
/// a movement was served and by the user's region focus.
///
/// Near-duplicates are one movement as far as all of this is concerned: a family (`FamilyIndex`)
/// never has two members in a break or a day, and its members share their recency.
///
/// It used to be far more involved — a shape per time of day, a six-slot region rotation, a
/// strength-or-balance slot that balance claimed first every day, a category draw before the
/// movement draw, and a repair pass to fit the movements' own lengths into five minutes — and
/// those rules between them served strength in 4% of blocks and eye and breathing movements three
/// times as often as anything else (docs/rule-changes-2026-10.md).
///
/// Pure and deterministic: the same `RoutineContext` always yields the same routine, which is
/// what lets the coordinator regenerate today's break after a relaunch.
struct RoutineBuilder {
    let library: MovementLibrary
    let families: FamilyIndex

    init(library: MovementLibrary) {
        self.library = library
        self.families = FamilyIndex(library: library)
    }

    /// The three working blocks between the warm-up and the closer, in an order drawn per break.
    static let workingBuckets: [Bucket] = [.bal, .flx, .str]

    func build(context: RoutineContext) -> Routine {
        var pool = candidates(for: context)
        if pool.isEmpty { pool = relaxedCandidates(for: context) }

        var rng = SplitMix64(seed: context.seed)
        let recency = families.scores(context.recency)
        let positions: [Set<Bucket>] = [[.cir]] + rng.shuffled(Self.workingBuckets).map { [$0] } + [Routine.closers]

        var chosen: [Movement] = []
        var repeatsToday: [Movement]?
        for allowed in positions {
            let taken = Set(chosen.map(\.familyKey))
            var options = pool.filter { allowed.contains($0.bucket) && !taken.contains($0.familyKey) }
            if options.isEmpty {
                // A long day can use up a bucket's families, most easily strength with no floor or
                // wall, since its standing movements share families with circulation and balance.
                // Something already served today beats a break one movement short.
                repeatsToday = repeatsToday ?? candidates(for: context.forgettingToday)
                options = (repeatsToday ?? []).filter { allowed.contains($0.bucket) && !taken.contains($0.familyKey) }
            }
            if allowed == [.str] { options = avoidingLastStrength(options, context: context) }
            // A bucket the user has excluded entirely leaves its position out rather than
            // borrowing from another one.
            guard let pick = pick(from: options, context: context, recency: recency, rng: &rng) else { continue }
            chosen.append(pick)
        }

        return Routine(
            id: UUID(),
            blocks: chosen.map { RoutineBlock(movement: $0, seconds: Routine.blockSeconds) }
        )
    }

    // MARK: - Candidate pool

    /// Every movement the user may be served right now: excludes applied, anything from a family
    /// already used today removed, difficulty capped, and equipment movements swapped for a
    /// bodyweight peer when the user does not own the kit.
    func candidates(for context: RoutineContext) -> [Movement] {
        let usedFamilies = families.keys(of: context.usedMovementIdsToday)
        var seen = Set<String>()
        var result: [Movement] = []
        for movement in library.movements {
            let resolved = Substitutions.resolve(movement, owned: context.equipment, in: library)
            guard usable(resolved, context: context, usedFamilies: usedFamilies) else { continue }
            guard seen.insert(resolved.id).inserted else { continue }
            result.append(resolved)
        }
        return result
    }

    /// The last resort, when the filters between them leave nothing at all: a day that has
    /// already served every movement, or a user who has excluded the entire library. A repeat is
    /// always better than a break with nothing in it.
    func relaxedCandidates(for context: RoutineContext) -> [Movement] {
        var relaxed = context.forgettingToday
        var pool = candidates(for: relaxed)
        if !pool.isEmpty { return pool }

        relaxed.excluded = []
        pool = candidates(for: relaxed)
        if !pool.isEmpty { return pool }

        // Everything off: the cap raised *and* the difficulty-3 gate opened with it, or the last
        // rung would filter out exactly what it was reaching for.
        relaxed.difficultyCap = 3
        relaxed.unlockedDiff3 = Set(library.movements.map(\.id))
        relaxed.equipment = []
        return candidates(for: relaxed)
    }

    private func usable(_ movement: Movement, context: RoutineContext, usedFamilies: Set<String>) -> Bool {
        if movement.needsEquipment, context.equipment.isDisjoint(with: movement.equipmentOptional) { return false }
        if movement.needsAny(of: context.unavailable) { return false }
        if context.excluded.contains(movement.id) { return false }
        if usedFamilies.contains(movement.familyKey) { return false }
        if movement.difficulty > context.difficultyCap { return false }
        if movement.difficulty >= 3, !context.unlockedDiff3.contains(movement.id) { return false }
        return true
    }

    // MARK: - Selection

    /// Do not load the same region with strength two breaks running. Balance and stretching are
    /// gentle enough to repeat a region; strength is the one that tires it.
    private func avoidingLastStrength(_ options: [Movement], context: RoutineContext) -> [Movement] {
        guard !context.usedStrRegionsLastBreak.isEmpty else { return options }
        let fresh = options.filter { Set($0.regions).isDisjoint(with: context.usedStrRegionsLastBreak) }
        return fresh.isEmpty ? options : fresh
    }

    /// Draws one movement, weighted by the user's region focus and how recently it was served.
    private func pick(
        from options: [Movement],
        context: RoutineContext,
        recency: [String: Double],
        rng: inout SplitMix64
    ) -> Movement? {
        guard !options.isEmpty else { return nil }
        let weights = options.map { weight(for: $0, context: context, recency: recency) }
        guard let index = rng.weightedIndex(in: weights) else { return options.first }
        return options[index]
    }

    /// `recency` is summed per family, so a sibling served yesterday counts as this one served.
    private func weight(for movement: Movement, context: RoutineContext, recency: [String: Double]) -> Double {
        var weight = 1.0
        if !Set(movement.regions).isDisjoint(with: context.focus.boostedRegions) { weight *= 3 }
        return weight * Recency.multiplier(score: recency[movement.familyKey] ?? 0)
    }
}

private extension RoutineContext {
    /// The same context with nothing served yet today.
    var forgettingToday: RoutineContext {
        var context = self
        context.usedMovementIdsToday = []
        return context
    }
}
