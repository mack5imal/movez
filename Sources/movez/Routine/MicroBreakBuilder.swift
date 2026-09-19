import Foundation

/// Assembles the one-minute micro-break: a single 60 s block, or two 30 s blocks.
///
/// Micro-break rules (library §11): micro-eligible movements only, no floor, no equipment, at
/// least partly upright, never a repeat of the last micro-break and never a movement the next full
/// break is about to use.
///
/// Circulation leads where the emphasis asks for it, but it is no longer in every micro-break.
/// Each emphasis used to draw its first half from one bucket and its second from a list that
/// always included circulation, so all three of them served one of twelve movements every time,
/// and the balance and strength movements marked micro-eligible were never served at all.
struct MicroBreakBuilder {
    static let totalSeconds = 60
    static let halfBlockSeconds = 30

    let library: MovementLibrary

    func build(context: MicroContext) -> MicroBreak {
        var rng = SplitMix64(seed: context.seed)
        let pool = candidates(for: context)

        let order = bucketOrder(for: context.emphasis)
        var blocks: [RoutineBlock] = []
        var used = Set<String>()

        for buckets in order {
            let options = pool.filter {
                buckets.contains($0.bucket)
                    && !used.contains($0.id)
                    && $0.blockSeconds >= Self.halfBlockSeconds
            }
            guard let pick = choose(from: options, context: context, rng: &rng) else { continue }
            used.insert(pick.id)
            blocks.append(block(pick, seconds: Self.halfBlockSeconds))
            if blocks.count == 2 { break }
        }

        if blocks.count == 2 { return MicroBreak(id: UUID(), blocks: blocks, emphasis: context.emphasis) }

        // Not enough variety for two halves — fall back to one full minute.
        let single = pool.filter { $0.blockSeconds >= Self.totalSeconds }
        if let pick = choose(from: single, context: context, rng: &rng) {
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

    /// Which buckets each half-block is drawn from, best first. Each emphasis leads with what it
    /// is named for and follows with everything that sits well beside it.
    private func bucketOrder(for emphasis: MicroContext.Emphasis) -> [[Bucket]] {
        switch emphasis {
        case .circulation: return [[.cir, .bal, .str], [.flx, .bre, .eye, .hwf]]
        case .eyesHands: return [[.eye, .hwf], [.cir, .bal, .flx]]
        case .posture: return [[.flx, .bre], [.cir, .bal, .str]]
        }
    }

    /// Draws the bucket first and then the movement, so the eleven hand movements are not drowned
    /// out by the thirty-eight flexibility ones, and weights the movement by recency.
    private func choose(from options: [Movement], context: MicroContext, rng: inout SplitMix64) -> Movement? {
        guard !options.isEmpty else { return nil }
        let buckets = Bucket.allCases.filter { bucket in options.contains { $0.bucket == bucket } }
        guard let bucketIndex = rng.weightedIndex(in: buckets.map { _ in 1 }) else { return nil }
        let inBucket = options.filter { $0.bucket == buckets[bucketIndex] }.sorted { $0.id < $1.id }
        let weights = inBucket.map { Recency.multiplier(score: context.recency[$0.id] ?? 0) }
        guard let index = rng.weightedIndex(in: weights) else { return inBucket.first }
        return inBucket[index]
    }

    private func block(_ movement: Movement, seconds: Int) -> RoutineBlock {
        RoutineBlock(
            movement: movement,
            seconds: seconds,
            trimmedFrom: movement.blockSeconds == seconds ? nil : movement.blockSeconds
        )
    }
}
