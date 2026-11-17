import Foundation

/// Assembles an end-range break: four END moves of a minute each, served once the day's strength
/// breaks are done (S22).
///
/// The draw is weighted by recency alone, nothing served today comes back while anything else is
/// left, and the regions the day's strength breaks worked are left alone where another move can
/// take their place: the point of the break is to open up what the sets did not touch.
///
/// Pure and deterministic: the same context and regions always build the same break, id included.
struct EndRangeBreakBuilder {
    let library: StrengthLibrary

    static let blockCount = 4
    static let ladder: [StrengthRelaxation.Rule] = [.servedToday, .excluded, .difficulty, .anything]

    private static let idSalt: UInt64 = 0x454E_4452_414E_4745

    /// `avoidingRegions` is every region the day's strength breaks worked.
    func build(context: StrengthContext, avoidingRegions: Set<Region>) -> EndRangeBreak {
        var state = StrengthDrawState(seed: context.seed)
        let pool = library.movements(in: .end)
        var chosen: [StrengthMovement] = []

        for index in 0..<Self.blockCount {
            let taken = Set(chosen.map(\.id))
            let pick = StrengthDraw.pick(
                slot: .block(index + 1), ladder: Self.ladder, state: &state,
                weight: { StrengthDraw.recencyWeight($0, recency: context.recency) },
                candidates: { letGo in
                    let options = pool.filter { movement in
                        guard !taken.contains(movement.id) else { return false }
                        guard !letGo.contains(.anything) else {
                            return StrengthEligibility.isPossible(movement, equipment: [], solidWallNearby: context.solidWallNearby)
                        }
                        return StrengthBreakBuilder.passesShared(movement, context: context, letGo: letGo)
                    }
                    return StrengthDraw.preferring(options) { avoidingRegions.isDisjoint(with: $0.regions) }
                }
            )
            guard let pick else { break }
            chosen.append(pick)
        }

        return EndRangeBreak(
            id: .seeded(context.seed, salt: Self.idSalt),
            blocks: chosen.map { StrengthBlock(movement: $0, seconds: StrengthTiming.endRangeBlockSeconds) },
            relaxed: state.relaxed
        )
    }
}
