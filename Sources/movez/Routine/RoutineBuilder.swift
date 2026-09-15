import Foundation

/// Assembles one full break from the library by the chaining rules.
///
/// Pure and deterministic: the same `RoutineContext` always yields the same routine, which is
/// what lets the coordinator regenerate today's break after a relaunch.
struct RoutineBuilder {
    /// The routine aims for five minutes including the transitions between blocks.
    static let targetTotalSeconds = 300
    static let minTotalSeconds = 270
    static let maxTotalSeconds = 330
    /// The smallest a block may be trimmed to, for movements whose natural block is longer.
    static let trimFloorSeconds = 60
    private static let shortlistSize = 8
    private static let maxRepairPasses = 6

    let library: MovementLibrary

    /// The per-build state the selection helpers read: the shape being filled, the movements
    /// still available, and the context that weights them.
    private struct Selection {
        let shape: RoutineShape
        let pool: [Movement]
        let context: RoutineContext
    }

    func build(context: RoutineContext) -> Routine {
        let shape = RoutineShape.shape(for: context.timeOfDay)
        var pool = candidates(for: context)
        if pool.isEmpty { pool = relaxedCandidates(for: context) }

        let selection = Selection(shape: shape, pool: pool, context: context)
        var blocks = assemble(count: 4, in: selection)
        if total(of: blocks) < Self.minTotalSeconds {
            blocks = assemble(count: 5, in: selection)
        }
        blocks = repairShortfall(blocks, in: selection)
        blocks = trimToFit(blocks)

        // Named for what it works, not for the slot that biased it; `slot` stays the planned one,
        // because that is what the rotation walks.
        let named = RoutineNaming.contentSlot(for: blocks, planned: context.slot)
        let naming = RoutineNaming.name(slot: named, timeOfDay: context.timeOfDay)
        return Routine(
            id: UUID(),
            name: naming.name,
            focus: naming.focus,
            completionTitle: naming.completionTitle,
            slot: context.slot,
            shape: shape,
            timeOfDay: context.timeOfDay,
            blocks: blocks
        )
    }

    // MARK: - Candidate pool

    /// Every movement the user may be served right now: excludes applied, movements already used
    /// today removed, difficulty capped, and equipment movements swapped for a bodyweight peer
    /// when the user does not own the kit.
    func candidates(for context: RoutineContext) -> [Movement] {
        var seen = Set<String>()
        var result: [Movement] = []
        for movement in library.movements {
            let resolved = Substitutions.resolve(movement, owned: context.equipment, in: library)
            guard usable(resolved, context: context) else { continue }
            guard seen.insert(resolved.id).inserted else { continue }
            result.append(resolved)
        }
        return result
    }

    /// The last resort, when the filters between them leave nothing at all: a day that has
    /// already served every movement, or a user who has excluded the entire library. A repeat is
    /// always better than a break with nothing in it.
    func relaxedCandidates(for context: RoutineContext) -> [Movement] {
        var relaxed = context
        relaxed.usedMovementIdsToday = []
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

    private func usable(_ movement: Movement, context: RoutineContext) -> Bool {
        if movement.needsEquipment, context.equipment.isDisjoint(with: movement.equipmentOptional) { return false }
        if context.excluded.contains(movement.id) { return false }
        if context.usedMovementIdsToday.contains(movement.id),
           !RoutineContext.alwaysRepeatable.contains(movement.id) { return false }
        if movement.difficulty > context.difficultyCap { return false }
        if movement.difficulty >= 3, !context.unlockedDiff3.contains(movement.id) { return false }
        return true
    }

    // MARK: - Assembly

    private func assemble(count: Int, in selection: Selection) -> [RoutineBlock] {
        let context = selection.context
        var rng = SplitMix64(seed: context.seed &+ UInt64(count))
        let plan = positionPlan(shape: selection.shape, count: count, context: context)
        var chosen: [Movement] = []
        var budget = Self.targetTotalSeconds - Routine.transitionSeconds * (count - 1)

        for position in plan.indices {
            let remaining = plan.count - position
            let ideal = max(20, budget / max(1, remaining))
            let allowed = plan[position]
            let available = options(at: position, allowed: allowed, chosen: chosen, in: selection)
            // The bucket is drawn first so that a short bucket — a 30 s eye break — is not
            // crowded out by a longer one every time the budget is consulted.
            let bucket = chooseBucket(allowed, among: available, context: context, rng: &rng)
            let options = available.filter { bucket == nil || $0.bucket == bucket }
            guard let pick = pick(from: options, ideal: ideal, context: context, rng: &rng) else { continue }
            chosen.append(pick)
            budget -= pick.blockSeconds
        }

        return chosen.map { RoutineBlock(movement: $0, seconds: $0.blockSeconds, trimmedFrom: nil) }
    }

    /// The allowed buckets per position, with the strength slot resolved to STR or BAL.
    private func positionPlan(shape: RoutineShape, count: Int, context: RoutineContext) -> [[Bucket]] {
        var plan = shape.plan(count: count)
        guard shape == .standard, plan.indices.contains(shape.strengthPosition) else { return plan }
        // Balance is served every day, and the "more balance" focus asks for it every break.
        if !context.balanceServedToday || context.focus == .moreBalance {
            plan[shape.strengthPosition] = [.bal]
        }
        return plan
    }

    private func options(
        at position: Int,
        allowed: [Bucket],
        chosen: [Movement],
        in selection: Selection
    ) -> [Movement] {
        let context = selection.context
        let takenIds = Set(chosen.map(\.id))
        let allowedSet = Set(allowed)
        let base = selection.pool.filter { allowedSet.contains($0.bucket) && !takenIds.contains($0.id) }

        guard position == selection.shape.strengthPosition,
              !context.usedStrRegionsLastBreak.isEmpty else { return base }
        // Chaining rule: do not load the same region two breaks running.
        let fresh = base.filter { Set($0.regions).isDisjoint(with: context.usedStrRegionsLastBreak) }
        return fresh.isEmpty ? base : fresh
    }

    /// Draws a weighted shortlist, then takes the entry closest to the seconds the budget wants.
    private func pick(
        from options: [Movement],
        ideal: Int,
        context: RoutineContext,
        rng: inout SplitMix64
    ) -> Movement? {
        guard !options.isEmpty else { return nil }

        var remaining = options
        var weights = remaining.map { weight(for: $0, context: context) }
        var shortlist: [Movement] = []
        let size = min(Self.shortlistSize, remaining.count)

        while shortlist.count < size {
            let total = weights.reduce(0, +)
            guard total > 0 else { break }
            var ticket = Int(rng.next() % UInt64(total))
            var index = 0
            for (offset, weight) in weights.enumerated() {
                ticket -= weight
                if ticket < 0 { index = offset; break }
            }
            shortlist.append(remaining.remove(at: index))
            weights.remove(at: index)
        }

        guard !shortlist.isEmpty else { return options.first }
        return shortlist.min { lhs, rhs in
            let left = abs(lhs.blockSeconds - ideal)
            let right = abs(rhs.blockSeconds - ideal)
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    /// Draws one bucket from the position's allowed set, weighted by the user's focus.
    /// Returns nil when the position allows a single bucket or none of them have candidates.
    private func chooseBucket(
        _ allowed: [Bucket],
        among options: [Movement],
        context: RoutineContext,
        rng: inout SplitMix64
    ) -> Bucket? {
        guard allowed.count > 1 else { return allowed.first }
        let present = allowed.filter { bucket in options.contains { $0.bucket == bucket } }
        guard present.count > 1 else { return present.first }

        let weights = present.map { bucketWeight($0, context: context) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return present.first }
        var ticket = Int(rng.next() % UInt64(total))
        for (index, weight) in weights.enumerated() {
            ticket -= weight
            if ticket < 0 { return present[index] }
        }
        return present.last
    }

    private func bucketWeight(_ bucket: Bucket, context: RoutineContext) -> Int {
        switch context.focus {
        case .moreBalance where bucket == .bal: return 3
        case .moreHandsEyes where bucket == .hwf || bucket == .eye: return 3
        default: return 1
        }
    }

    /// Region rotation and the user's focus both bias selection without ever forcing it.
    private func weight(for movement: Movement, context: RoutineContext) -> Int {
        var weight = 1
        let regions = Set(movement.regions)
        if !regions.isDisjoint(with: context.slot.regions) { weight *= 3 }
        if !context.focus.boostedRegions.isEmpty, !regions.isDisjoint(with: context.focus.boostedRegions) {
            weight *= 3
        }
        if context.focus == .moreHandsEyes, movement.bucket == .hwf || movement.bucket == .eye { weight *= 3 }
        if context.focus == .moreBalance, movement.bucket == .bal { weight *= 3 }
        return weight
    }

    // MARK: - Duration fitting

    private func total(of blocks: [RoutineBlock]) -> Int {
        blocks.reduce(0) { $0 + $1.seconds } + Routine.transitionSeconds * max(0, blocks.count - 1)
    }

    /// Swaps short blocks for the longest available alternative until the routine clears 270 s.
    private func repairShortfall(_ blocks: [RoutineBlock], in selection: Selection) -> [RoutineBlock] {
        var blocks = lengthen(blocks, in: selection, keepBucket: true)
        if total(of: blocks) < Self.minTotalSeconds {
            blocks = lengthen(blocks, in: selection, keepBucket: false)
        }
        return blocks
    }

    /// Swaps the shortest block for a longer alternative, either within the same bucket or
    /// anywhere the position allows.
    private func lengthen(_ blocks: [RoutineBlock], in selection: Selection, keepBucket: Bool) -> [RoutineBlock] {
        var blocks = blocks
        guard !blocks.isEmpty else { return blocks }
        let plan = positionPlan(shape: selection.shape, count: blocks.count, context: selection.context)

        for _ in 0..<Self.maxRepairPasses {
            guard total(of: blocks) < Self.minTotalSeconds else { break }
            var improved = false
            let order = blocks.indices.sorted { blocks[$0].seconds < blocks[$1].seconds }
            for index in order where plan.indices.contains(index) {
                let chosen = blocks.enumerated().filter { $0.offset != index }.map(\.element.movement)
                let allowed = keepBucket ? [blocks[index].movement.bucket] : plan[index]
                let options = options(at: index, allowed: allowed, chosen: chosen, in: selection)
                guard let longest = options.max(by: { ($0.blockSeconds, $1.id) < ($1.blockSeconds, $0.id) }),
                      longest.blockSeconds > blocks[index].seconds else { continue }
                blocks[index] = RoutineBlock(movement: longest, seconds: longest.blockSeconds, trimmedFrom: nil)
                improved = true
                break
            }
            if !improved { break }
        }
        return blocks
    }

    /// Trims the longest blocks toward 60 s until the routine fits under 330 s.
    private func trimToFit(_ blocks: [RoutineBlock]) -> [RoutineBlock] {
        var blocks = blocks
        while total(of: blocks) > Self.maxTotalSeconds {
            let trimmable = blocks.indices.filter { blocks[$0].seconds > Self.trimFloorSeconds }
            guard let index = trimmable.max(by: { blocks[$0].seconds < blocks[$1].seconds }) else { break }
            let overshoot = total(of: blocks) - Self.maxTotalSeconds
            let block = blocks[index]
            let seconds = max(Self.trimFloorSeconds, block.seconds - overshoot)
            blocks[index] = RoutineBlock(
                movement: block.movement,
                seconds: seconds,
                trimmedFrom: block.trimmedFrom ?? block.movement.blockSeconds
            )
        }
        return blocks
    }
}
