import Foundation

/// One part of a full break that is done in turn: a movement block, a warm-up, a working set, a
/// cool-down or an end-range block. History records one completion for each part done.
struct BreakPart: Hashable {
    let movementId: String
    let seconds: Int
}

extension PlannedBreak {
    var id: UUID {
        switch self {
        case let .movement(routine): return routine.id
        case let .strength(strengthBreak): return strengthBreak.id
        case let .endRange(endRange): return endRange.id
        }
    }

    /// The parts in the order they run. A strength break's repeated pattern is two parts, one per
    /// set, so both sets are recorded when both are done.
    var parts: [BreakPart] {
        switch self {
        case let .movement(routine):
            return routine.blocks.map { BreakPart(movementId: $0.movement.id, seconds: $0.seconds) }
        case let .strength(strengthBreak):
            let warmUp = BreakPart(movementId: strengthBreak.warmUp.movement.id, seconds: strengthBreak.warmUp.seconds)
            let sets = strengthBreak.sets.map { BreakPart(movementId: $0.movement.id, seconds: $0.plannedSeconds) }
            let coolDown = BreakPart(movementId: strengthBreak.coolDown.movement.id, seconds: strengthBreak.coolDown.seconds)
            return [warmUp] + sets + [coolDown]
        case let .endRange(endRange):
            return endRange.blocks.map { BreakPart(movementId: $0.movement.id, seconds: $0.seconds) }
        }
    }

    /// The movement routine, for the surfaces that so far only know how to show one.
    var routine: Routine? {
        guard case let .movement(routine) = self else { return nil }
        return routine
    }

    var strengthBreak: StrengthBreak? {
        guard case let .strength(strengthBreak) = self else { return nil }
        return strengthBreak
    }

    var endRangeBreak: EndRangeBreak? {
        guard case let .endRange(endRange) = self else { return nil }
        return endRange
    }
}

/// A micro-break, whichever mode built it.
enum PlannedMicro: Hashable {
    case movement(MicroBreak)
    case strength(StrengthMicroBreak)

    var id: UUID {
        switch self {
        case let .movement(micro): return micro.id
        case let .strength(micro): return micro.id
        }
    }

    var movementIds: [String] {
        switch self {
        case let .movement(micro): return micro.movementIds
        case let .strength(micro): return micro.movementIds
        }
    }

    var totalSeconds: Int {
        switch self {
        case let .movement(micro): return micro.totalSeconds
        case let .strength(micro): return micro.totalSeconds
        }
    }

    /// The movement micro-break, when this is one.
    var movementMicro: MicroBreak? {
        guard case let .movement(micro) = self else { return nil }
        return micro
    }

    var strengthMicro: StrengthMicroBreak? {
        guard case let .strength(micro) = self else { return nil }
        return micro
    }

    /// The parts the user got at least halfway through in `seconds` of running time. Both kinds
    /// lay their blocks out the same way, each after a five-second lead-in, so the rule is the one
    /// `MicroBreak.blocksRun` applies.
    func partsRun(seconds: Int) -> [BreakPart] {
        switch self {
        case let .movement(micro):
            return micro.blocksRun(seconds: seconds).map { BreakPart(movementId: $0.movement.id, seconds: $0.seconds) }
        case let .strength(micro):
            var startsAt = 0
            var run: [BreakPart] = []
            for block in micro.blocks {
                startsAt += StrengthTiming.leadInSeconds
                if (seconds - startsAt) * 2 >= block.seconds {
                    run.append(BreakPart(movementId: block.movement.id, seconds: block.seconds))
                }
                startsAt += block.seconds
            }
            return run
        }
    }
}

/// Where the day stands in a mode that plans its day, for the menu: the day's letter and which of
/// the day's planned breaks comes next.
struct ModeDayProgress: Equatable {
    var dayLetter: StrengthDayLetter
    /// The next break's place among the day's strength breaks, 1-based, or nil once they are done.
    var breakNumber: Int?
    var breaksPerDay: Int
}

/// Builds one mode's breaks for the coordinator.
///
/// The coordinator decides nothing about what a break holds: it asks the active mode's builder,
/// found by mode id in a `ModeBuilderTable`, so a further mode is a further builder in the table
/// and not another branch through the coordinator. A builder is handed the coordinator itself
/// because what it reads (history, settings, the day's served ids) all lives there.
@MainActor
protocol ModeBreakBuilding {
    /// What this mode's full break reads beyond what the coordinator keys every preview on, so the
    /// cached preview is rebuilt whenever any of it moves.
    func previewKeyParts(for coordinator: AppCoordinator, at now: Date) -> [String]
    func fullBreak(for coordinator: AppCoordinator, at now: Date) -> PlannedBreak
    /// A micro-break that keeps away from `nextFullBreakIds` where it can.
    func microBreak(for coordinator: AppCoordinator, at now: Date, nextFullBreakIds: Set<String>) -> PlannedMicro
    /// The day's progress for the menu, or nil for a mode that does not plan its day.
    func dayProgress(for coordinator: AppCoordinator, at now: Date) -> ModeDayProgress?
}

/// Which builder serves each mode, by mode id.
///
/// The app uses `standard`; a test adds a builder for a mode of its own to show that a new mode is
/// served by the coordinator's build path through lookup alone.
@MainActor
struct ModeBuilderTable {
    private var builders: [String: any ModeBreakBuilding]

    init(builders: [String: any ModeBreakBuilding]) {
        self.builders = builders
    }

    /// Movement always; Strength when its library loaded.
    static func standard(strengthLibrary: StrengthLibrary?, movementLibrary: MovementLibrary) -> ModeBuilderTable {
        var builders: [String: any ModeBreakBuilding] = [BreakMode.movement.rawValue: MovementModeBuilder()]
        if let strengthLibrary {
            builders[BreakMode.strength.rawValue] = StrengthModeBuilder(
                library: strengthLibrary,
                usage: CrossModeUsage(movementLibrary: movementLibrary, strengthLibrary: strengthLibrary)
            )
        }
        return ModeBuilderTable(builders: builders)
    }

    func adding(_ builder: any ModeBreakBuilding, for id: String) -> ModeBuilderTable {
        var table = self
        table.builders[id] = builder
        return table
    }

    /// The builder for `id`, or the fallback mode's when there is none: a mode whose library did
    /// not load still serves breaks rather than none.
    func builder(for id: String) -> any ModeBreakBuilding {
        if let builder = builders[id] { return builder }
        return builders[BreakMode.fallback.rawValue] ?? MovementModeBuilder()
    }
}
