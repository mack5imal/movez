import Foundation

/// Assembles a strength micro-break from END (S7): one per-side move for the minute, thirty
/// seconds a side, or two two-sided moves of thirty seconds each.
///
/// Never a floor move, since a micro-break is taken in work clothes at the desk. The second move
/// keeps the first one's posture, standing or seated, so the user is not up and down inside a
/// minute. No region is shared with the previous micro-break, the next full break's regions are
/// avoided when another move will do, and nothing served today comes back while the pool allows.
///
/// When the rules leave nothing they are let go of in a fixed order, recorded on the micro-break;
/// a two-sided move left with no partner runs the minute alone rather than leaving the panel empty.
struct StrengthMicroBuilder {
    let library: StrengthLibrary

    static let ladder: [StrengthRelaxation.Rule] = [.servedToday, .previousMicroRegion, .excluded, .difficulty, .anything]

    private static let idSalt: UInt64 = 0x4D49_4352_4F42_524B

    func build(context: StrengthMicroContext) -> StrengthMicroBreak {
        var state = StrengthDrawState(seed: context.seed)
        let previousRegions = regions(of: context.lastMicroMovementIds)
        let nextRegions = regions(of: context.nextFullBreakIds)
        let weight: (StrengthMovement) -> Double = { StrengthDraw.recencyWeight($0, recency: context.recency) }

        let first = StrengthDraw.pick(slot: .block(1), ladder: Self.ladder, state: &state, weight: weight) { letGo in
            let pool = candidates(context: context, previousRegions: previousRegions, letGo: letGo)
            let openers = pool.filter { $0.perSide || Self.hasPartner($0, in: pool) }
            return StrengthDraw.preferring(openers) { nextRegions.isDisjoint(with: $0.regions) }
        }
        // The pool the first move was drawn from, under the rules the draw ended up keeping.
        let finalPool = candidates(context: context, previousRegions: previousRegions, letGo: state.letGo)

        guard let first = first ?? StrengthDraw.weighted(finalPool, rng: &state.rng, weight: weight) else {
            return StrengthMicroBreak(id: id(context), blocks: [], relaxed: state.relaxed)
        }
        let whole = StrengthTiming.microHalfSeconds * 2
        if first.perSide {
            return StrengthMicroBreak(id: id(context), blocks: [StrengthBlock(movement: first, seconds: whole)], relaxed: state.relaxed)
        }

        // The partner keeps every rule the first draw let go of wherever a partner can, the most
        // important first, so a day short of unserved moves does not also repeat one needlessly.
        var partners = finalPool.filter { Self.isPartner($0, of: first) }
        var letGo = state.letGo
        for rule in Self.ladder.reversed() where letGo.contains(rule) {
            let kept = letGo.subtracting([rule])
            let stricter = Set(candidates(context: context, previousRegions: previousRegions, letGo: kept).map(\.id))
            let narrower = partners.filter { stricter.contains($0.id) }
            if !narrower.isEmpty {
                partners = narrower
                letGo = kept
            }
        }
        partners = StrengthDraw.preferring(partners) { nextRegions.isDisjoint(with: $0.regions) }
        guard let second = StrengthDraw.weighted(partners, rng: &state.rng, weight: weight) else {
            state.relaxed.append(StrengthRelaxation(slot: .block(2), rule: .microShape))
            return StrengthMicroBreak(id: id(context), blocks: [StrengthBlock(movement: first, seconds: whole)], relaxed: state.relaxed)
        }
        return StrengthMicroBreak(
            id: id(context),
            blocks: [
                StrengthBlock(movement: first, seconds: StrengthTiming.microHalfSeconds),
                StrengthBlock(movement: second, seconds: StrengthTiming.microHalfSeconds)
            ],
            relaxed: state.relaxed
        )
    }

    /// Non-floor END moves passing the rules not yet let go of. The floor rule and END itself are
    /// never let go of.
    func candidates(
        context: StrengthMicroContext,
        previousRegions: Set<Region>,
        letGo: Set<StrengthRelaxation.Rule>
    ) -> [StrengthMovement] {
        library.microEligible.filter { movement in
            guard movement.bucket == .end, !movement.onFloor else { return false }
            guard StrengthEligibility.isPossible(movement, equipment: [], solidWallNearby: context.solidWallNearby) else {
                return false
            }
            if letGo.contains(.anything) { return true }
            if !letGo.contains(.servedToday), context.usedStrengthIdsToday.contains(movement.id) { return false }
            if !letGo.contains(.previousMicroRegion), !previousRegions.isDisjoint(with: movement.regions) { return false }
            if !letGo.contains(.excluded), context.excluded.contains(movement.id) { return false }
            if !letGo.contains(.difficulty),
               !StrengthEligibility.isWithinDifficulty(movement, cap: context.difficultyCap, unlocked: context.unlockedBuckets) {
                return false
            }
            return true
        }
    }

    /// A second half for `first`: another two-sided move done in the same posture.
    static func isPartner(_ candidate: StrengthMovement, of first: StrengthMovement) -> Bool {
        candidate.id != first.id && !candidate.perSide && StrengthPosture(candidate) == StrengthPosture(first)
    }

    private static func hasPartner(_ movement: StrengthMovement, in pool: [StrengthMovement]) -> Bool {
        pool.contains { isPartner($0, of: movement) }
    }

    private func regions(of ids: Set<String>) -> Set<Region> {
        Set(ids.compactMap { library.movement(id: $0) }.flatMap(\.regions))
    }

    private func id(_ context: StrengthMicroContext) -> UUID {
        .seeded(context.seed, salt: Self.idSalt)
    }
}
