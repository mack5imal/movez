import Foundation

/// The strength heads-up and micro-break panel states the snapshots render.
///
/// They reuse the Movement panels' instant and timings, so a strength PNG sits next to its Movement
/// counterpart at the same moment. The END moves are picked here, in fixture code, because a
/// snapshot needs the same moves every time; app code never names one.
@MainActor
extension SnapshotFixtures {
    /// The heads-up before a strength break, or an end-range break, or the deferred variant.
    static func strengthHeadsUp(
        announced: HeadsUpAnnouncement = .strength,
        deferred: Bool = false
    ) -> PanelViewModel {
        let model = headsUp(deferred: deferred)
        model.modeDefinition = .strength
        model.announced = announced
        return model
    }

    /// The count-in before a seated pair, with 0:21 left.
    static func strengthMicroCountIn() -> PanelViewModel {
        let model = microCountIn()
        model.modeDefinition = .strength
        model.micro = strengthMicroPair()
        return model
    }

    /// A running strength micro-break, at the same moments as the Movement micro snapshots.
    static func strengthMicroRunning(
        elapsed: TimeInterval? = nil,
        perSide: Bool = false,
        micro chosen: MicroPanelBreak? = nil
    ) -> PanelViewModel {
        let micro = chosen ?? (perSide ? strengthMicroSide() : strengthMicroPair())
        let model = microRunning(elapsed: elapsed, micro: micro)
        // An unreadable bundle leaves the panel empty rather than showing Movement's fallback.
        model.micro = micro
        model.modeDefinition = .strength
        return model
    }

    /// The longest text a strength micro-break can show: the longest standing END name over the
    /// longest END instruction, on a per-side move, first side.
    static func strengthMicroLongText() -> PanelViewModel {
        strengthMicroRunning(elapsed: microSideElapsed, micro: strengthMicroLong())
    }

    // MARK: - The micro-breaks

    /// Two two-sided seated moves of thirty seconds each: a timed dose and a rep-and-hold dose.
    private static let pairIds = [fixtureId(.end, 31), fixtureId(.end, 37)]
    /// One per-side standing move for the whole minute.
    private static let sideId = fixtureId(.end, 35)

    /// The longest standing END name, and the longest END instruction it is drawn over.
    private static let microLongNameId = fixtureId(.end, 6)
    private static let microLongTextId = fixtureId(.end, 32)

    private static func strengthMicroLong() -> MicroPanelBreak? {
        guard let library = strengthLibrary,
              let named = library.movement(id: microLongNameId),
              let texted = library.movement(id: microLongTextId)
        else { return nil }
        let movement = renamed(texted, after: named)
        let block = StrengthBlock(movement: movement, seconds: StrengthTiming.microHalfSeconds * 2)
        return MicroPanelBreak(StrengthMicroBreak(id: UUID(), blocks: [block], relaxed: []))
    }

    private static func strengthMicroPair() -> MicroPanelBreak? {
        strengthMicro(ids: pairIds, seconds: StrengthTiming.microHalfSeconds)
    }

    private static func strengthMicroSide() -> MicroPanelBreak? {
        strengthMicro(ids: [sideId], seconds: StrengthTiming.microHalfSeconds * 2)
    }

    private static func strengthMicro(ids: [String], seconds: Int) -> MicroPanelBreak? {
        guard let library = strengthLibrary else { return nil }
        let blocks = ids.compactMap(library.movement(id:)).map { StrengthBlock(movement: $0, seconds: seconds) }
        return MicroPanelBreak(StrengthMicroBreak(id: UUID(), blocks: blocks, relaxed: []))
    }
}
