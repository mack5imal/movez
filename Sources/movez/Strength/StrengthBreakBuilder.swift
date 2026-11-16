import Foundation

/// Assembles one strength break from the strength library (S6).
///
/// `StrengthDayPlanner` decides the day's letter and the order of the three working sets; this
/// decides which move fills each. The warm-up is drawn first, from the first set's pattern (an arm
/// break's from the day's push or pull), then each slot's move, then the cool-down from END against
/// the regions the sets worked. A slot that appears twice (X · Y · X, or an arm break's arm · arm)
/// is drawn once and served both times, so the second set repeats the first one's move rather than
/// spending another from a pool that has to last the day; an arm break's alternate slot is a
/// different slot, so it draws a different move from the same arm bucket.
///
/// With any kit selected, every working set must be a vigorous move, so the kit does the work and
/// the light bodyweight moves are left to the warm-ups. Bodyweight-only users have no such rule.
///
/// Within a pattern the draw is weighted by recency and by the user's focus, ×3 for a move in a
/// focus region. When the rules leave a slot with nothing, they are let go of one rung at a time,
/// in a fixed order per slot, and the rung is recorded on the break.
///
/// Pure and deterministic: the same context and plan always build the same break, id included.
struct StrengthBreakBuilder {
    let library: StrengthLibrary

    /// The order each slot lets its rules go. The per-break limits are planner judgement, so they
    /// go before anything already served today is allowed back. The vigorous rule goes after that,
    /// because repeating a vigorous move does the user more good than serving a light one.
    static let workingLadder: [StrengthRelaxation.Rule] = [
        .breakLimits, .servedToday, .vigorous, .excluded, .difficulty, .anything
    ]
    static let warmUpLadder: [StrengthRelaxation.Rule] = [.warmUpShape, .servedToday, .excluded, .difficulty, .anything]
    static let coolDownLadder: [StrengthRelaxation.Rule] = [.coolDownRegion, .servedToday, .excluded, .difficulty, .anything]

    /// Keeps a strength break's id apart from an end-range or micro-break built from the same seed.
    private static let idSalt: UInt64 = 0x5354_5245_4E47_5448

    /// One slot to fill: where it sits, which pattern it draws from, how its rules relax and which
    /// moves this break already holds.
    private struct SlotRequest {
        let slot: StrengthRelaxation.Slot
        let bucket: StrengthBucket
        let ladder: [StrengthRelaxation.Rule]
        let taken: Set<String>
    }

    /// The regions an arm break's cool-down may stretch. No END move stretches the arm itself, so
    /// the cool-down takes the joints around it that the arm sets load.
    static let armCoolDownRegions: Set<Region> = [.shoulder, .chest, .arm, .wristForearm]

    /// The bucket a slot draws from; the day's first break carries a core set in its third slot.
    static func bucket(for slot: StrengthSetSlot) -> StrengthBucket {
        switch slot {
        case let .pattern(bucket), let .arm(bucket), let .armAlternate(bucket): return bucket
        case .core: return .cor
        }
    }

    /// The bucket a break's warm-up draws from: the first set's pattern, or for an arm break the
    /// day's push or pull, since the arm buckets keep their moves for the sets.
    static func warmUpBucket(letter: StrengthDayLetter, setOrder: [StrengthSetSlot]) -> StrengthBucket {
        guard let first = setOrder.first else { return letter.patterns.first }
        return first.isArm ? letter.armWarmUpPattern : bucket(for: first)
    }

    func build(letter: StrengthDayLetter, setOrder: [StrengthSetSlot], context: StrengthContext) -> StrengthBreak {
        var state = StrengthDrawState(seed: context.seed)
        let isArmBreak = setOrder.contains(where: \.isArm)
        let warmUpBucket = Self.warmUpBucket(letter: letter, setOrder: setOrder)

        let warmUpRequest = SlotRequest(slot: .warmUp, bucket: warmUpBucket, ladder: Self.warmUpLadder, taken: [])
        let warmUp = draw(warmUpRequest, context: context, state: &state) { movement, letGo in
            letGo.contains(.warmUpShape) ? movement.isBodyweight : Self.isWarmUpShaped(movement)
        }

        // Keyed by slot, in draw order, so the moves already in the break are a stable list.
        var drawn: [(slot: StrengthSetSlot, movement: StrengthMovement)] = []
        var working: [StrengthMovement] = []
        for (index, setSlot) in setOrder.enumerated() {
            if let repeated = drawn.first(where: { $0.slot == setSlot }) {
                working.append(repeated.movement)
                continue
            }
            let distinct = drawn.map(\.movement)
            let request = SlotRequest(
                slot: .set(index + 1), bucket: Self.bucket(for: setSlot), ladder: Self.workingLadder,
                taken: Set(distinct.map(\.id)).union([warmUp.id])
            )
            let pick = draw(
                request, context: context, state: &state,
                narrow: { pool, letGo in
                    // Let go of as a group, the limits are still kept one by one wherever the pool
                    // allows, so a break short of a move that keeps all three keeps as many as it can.
                    guard letGo.contains(.breakLimits) else { return pool }
                    return BreakLimit.allCases.reduce(pool) { kept, limit in
                        StrengthDraw.preferring(kept) { limit.allows($0, alongside: distinct) }
                    }
                },
                slotRule: { movement, letGo in
                    (letGo.contains(.breakLimits) || Self.fitsBreakLimits(movement, alongside: distinct))
                        && (letGo.contains(.vigorous) || Self.isVigorousEnough(movement, equipment: context.equipment))
                }
            )
            drawn.append((setSlot, pick))
            working.append(pick)
        }

        let worked = isArmBreak ? Self.armCoolDownRegions : Set(working.flatMap(\.regions))
        let coolDownRequest = SlotRequest(
            slot: .coolDown, bucket: .end, ladder: Self.coolDownLadder,
            taken: Set(working.map(\.id)).union([warmUp.id])
        )
        let coolDown = draw(coolDownRequest, context: context, state: &state) { movement, letGo in
            letGo.contains(.coolDownRegion) || !worked.isDisjoint(with: movement.regions)
        }

        return StrengthBreak(
            id: .seeded(context.seed, salt: Self.idSalt),
            letter: letter,
            warmUp: StrengthBlock(movement: warmUp, seconds: StrengthTiming.warmUpSeconds),
            sets: working.enumerated().map { StrengthSet(movement: $1, setNumber: $0 + 1) },
            coolDown: StrengthBlock(movement: coolDown, seconds: StrengthTiming.coolDownSeconds),
            relaxed: state.relaxed
        )
    }

    // MARK: - Rules

    /// One bodyweight, non-floor, difficulty-1, two-sided move: something anyone can start cold.
    static func isWarmUpShaped(_ movement: StrengthMovement) -> Bool {
        movement.isBodyweight && !movement.onFloor && movement.difficulty == 1 && !movement.perSide
    }

    /// Whether a move may be a working set for a user with this kit: with any kit selected only a
    /// vigorous move may, so the light bodyweight moves don't take sets the kit could load.
    static func isVigorousEnough(_ movement: StrengthMovement, equipment: Set<StrengthEquipment>) -> Bool {
        equipment.isEmpty || movement.vigorous
    }

    /// At most one per-side, one floor and one grip move among a break's distinct working moves:
    /// one get-down is plenty in office clothes, two per-side moves would stretch the break, and
    /// two grip-heavy moves tire the forearms before the pattern does.
    static func fitsBreakLimits(_ movement: StrengthMovement, alongside chosen: [StrengthMovement]) -> Bool {
        BreakLimit.allCases.allSatisfy { $0.allows(movement, alongside: chosen) }
    }

    /// The three per-break limits, in the order a short pool keeps them.
    enum BreakLimit: CaseIterable {
        case perSide
        case floor
        case grip

        func allows(_ movement: StrengthMovement, alongside chosen: [StrengthMovement]) -> Bool {
            switch self {
            case .perSide: return !(movement.perSide && chosen.contains(where: \.perSide))
            case .floor: return !(movement.onFloor && chosen.contains(where: \.onFloor))
            case .grip: return !(movement.gripDemand && chosen.contains(where: \.gripDemand))
            }
        }
    }

    /// The filters every slot shares: what the user can do, nothing served today, nothing
    /// excluded, and the difficulty cap and unlock.
    static func passesShared(_ movement: StrengthMovement, context: StrengthContext, letGo: Set<StrengthRelaxation.Rule>) -> Bool {
        guard StrengthEligibility.isPossible(
            movement, equipment: context.equipment, solidWallNearby: context.solidWallNearby
        ) else { return false }
        if !letGo.contains(.servedToday), context.usedStrengthIdsToday.contains(movement.id) { return false }
        if !letGo.contains(.excluded), context.excluded.contains(movement.id) { return false }
        if !letGo.contains(.difficulty),
           !StrengthEligibility.isWithinDifficulty(movement, cap: context.difficultyCap, unlocked: context.unlockedBuckets) {
            return false
        }
        return true
    }

    // MARK: - Drawing

    /// Draws one move for `request` that passes `slotRule` and the shared filters, letting go of
    /// rules in the request's ladder order until something is left. `narrow` may then prefer part
    /// of each pool.
    private func draw(
        _ request: SlotRequest,
        context: StrengthContext,
        state: inout StrengthDrawState,
        narrow: ([StrengthMovement], Set<StrengthRelaxation.Rule>) -> [StrengthMovement] = { pool, _ in pool },
        slotRule: (StrengthMovement, Set<StrengthRelaxation.Rule>) -> Bool
    ) -> StrengthMovement {
        let inBucket = library.movements(in: request.bucket)
        let boosted = context.focus.boostedRegions
        let pick = StrengthDraw.pick(
            slot: request.slot, ladder: request.ladder, state: &state,
            weight: { movement in
                let focus = boosted.isDisjoint(with: movement.regions) ? 1.0 : 3.0
                return focus * StrengthDraw.recencyWeight(movement, recency: context.recency)
            },
            candidates: { letGo in
                let pool = inBucket.filter { movement in
                    guard !request.taken.contains(movement.id) else { return false }
                    guard !letGo.contains(.anything) else {
                        return StrengthEligibility.isPossible(
                            movement, equipment: context.equipment, solidWallNearby: context.solidWallNearby
                        )
                    }
                    return Self.passesShared(movement, context: context, letGo: letGo) && slotRule(movement, letGo)
                }
                return narrow(pool, letGo)
            }
        )
        // Only a pattern with nothing the user can do gets here, since the last rung keeps every
        // move they can; any move is still better than a hole in the break.
        return pick ?? inBucket.first ?? library.movements[0]
    }
}
