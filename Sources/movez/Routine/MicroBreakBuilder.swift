import Foundation

/// Assembles the one-minute micro-break: a single 60 s block, or two 30 s blocks.
///
/// Micro-break rules (library §11): micro-eligible movements only, no floor, no equipment, at
/// least partly upright, circulation first where possible, never a repeat of the last micro-break
/// and never a movement the next full break is about to use.
struct MicroBreakBuilder {
    static let totalSeconds = 60
    static let halfBlockSeconds = 30
    /// Post-lunch wants blood moving, so it is a single standing circulation minute.
    static let postLunchPreference = ["CIR-02", "CIR-01", "CIR-05", "CIR-06"]

    let library: MovementLibrary

    func build(context: MicroContext) -> MicroBreak {
        var rng = SplitMix64(seed: context.seed)
        let pool = candidates(for: context)

        if context.isPostLunch, let block = postLunchBlock(from: pool, rng: &rng) {
            return MicroBreak(id: UUID(), blocks: [block], emphasis: context.emphasis)
        }

        let order = bucketOrder(for: context.emphasis)
        var blocks: [RoutineBlock] = []
        var used = Set<String>()

        for buckets in order {
            let options = pool.filter {
                buckets.contains($0.bucket)
                    && !used.contains($0.id)
                    && $0.blockSeconds >= Self.halfBlockSeconds
            }
            guard let pick = choose(from: options, rng: &rng) else { continue }
            used.insert(pick.id)
            blocks.append(block(pick, seconds: Self.halfBlockSeconds))
            if blocks.count == 2 { break }
        }

        if blocks.count == 2 { return MicroBreak(id: UUID(), blocks: blocks, emphasis: context.emphasis) }

        // Not enough variety for two halves — fall back to one full minute.
        let single = pool.filter { $0.blockSeconds >= Self.totalSeconds }
        if let pick = choose(from: single, rng: &rng) {
            return MicroBreak(id: UUID(), blocks: [block(pick, seconds: Self.totalSeconds)], emphasis: context.emphasis)
        }
        return MicroBreak(id: UUID(), blocks: blocks, emphasis: context.emphasis)
    }

    /// Micro-eligible movements the user may be served right now.
    func candidates(for context: MicroContext) -> [Movement] {
        library.microEligible.filter { movement in
            !movement.needsEquipment
                && !movement.isFloor
                && !context.excluded.contains(movement.id)
                && !context.lastMicroMovementIds.contains(movement.id)
                && !context.nextFullRoutineIds.contains(movement.id)
        }
    }

    /// Which buckets each half-block is drawn from, best first.
    private func bucketOrder(for emphasis: MicroContext.Emphasis) -> [[Bucket]] {
        switch emphasis {
        case .circulation: return [[.cir], [.eye, .hwf, .flx, .bre]]
        case .eyesHands: return [[.eye, .hwf], [.cir]]
        case .posture: return [[.flx, .bre], [.cir]]
        }
    }

    private func postLunchBlock(from pool: [Movement], rng: inout SplitMix64) -> RoutineBlock? {
        let circulation = pool.filter { $0.bucket == .cir && $0.blockSeconds >= Self.totalSeconds }
        let preferred = circulation.filter { Self.postLunchPreference.contains($0.id) }
        let options = preferred.isEmpty ? circulation : preferred
        guard let pick = choose(from: options, rng: &rng) else { return nil }
        return block(pick, seconds: Self.totalSeconds)
    }

    private func choose(from options: [Movement], rng: inout SplitMix64) -> Movement? {
        guard !options.isEmpty else { return nil }
        let sorted = options.sorted { $0.id < $1.id }
        return sorted[Int(rng.next() % UInt64(sorted.count))]
    }

    private func block(_ movement: Movement, seconds: Int) -> RoutineBlock {
        RoutineBlock(
            movement: movement,
            seconds: seconds,
            trimmedFrom: movement.blockSeconds == seconds ? nil : movement.blockSeconds
        )
    }
}
