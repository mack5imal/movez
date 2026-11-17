import Foundation

/// The full break the coordinator is about to serve, whichever mode built it.
///
/// It lives in `Modes/` because it is where the kinds of break meet: everything outside reads a
/// break through `plannedSeconds`, `movementIds` and `kind` rather than asking which one it holds.
enum PlannedBreak: Hashable {
    case movement(Routine)
    case strength(StrengthBreak)
    case endRange(EndRangeBreak)

    /// How long the break is planned to run, lead-ins included.
    var plannedSeconds: Int {
        switch self {
        case let .movement(routine): return routine.totalSeconds
        case let .strength(strengthBreak): return strengthBreak.plannedSeconds
        case let .endRange(endRange): return endRange.plannedSeconds
        }
    }

    /// The ids served, each in its own library's namespace.
    var movementIds: [String] {
        switch self {
        case let .movement(routine): return routine.movementIds
        case let .strength(strengthBreak): return strengthBreak.movementIds
        case let .endRange(endRange): return endRange.movementIds
        }
    }

    /// What the break is recorded as in history, which `StrengthDayPlanner` replays.
    var kind: BreakKind {
        switch self {
        case .movement: return .movement
        case let .strength(strengthBreak): return strengthBreak.letter.breakKind
        case .endRange: return .endRange
        }
    }
}

/// Which kind of full break a heads-up announces, and the words that kind gets.
///
/// It lives beside `PlannedBreak` so the panel never asks which mode it is showing: the panel takes
/// a title and, unless the break counts its own, a body from here.
enum HeadsUpAnnouncement: Equatable {
    case movement
    case strength
    case endRange

    init(_ planned: PlannedBreak) {
        switch planned {
        case .movement: self = .movement
        case .strength: self = .strength
        case .endRange: self = .endRange
        }
    }

    var title: String {
        switch self {
        case .movement: return "Movement break in a minute"
        case .strength: return "Strength break in a minute"
        case .endRange: return "End-range break in a minute"
        }
    }

    /// A strength break is always three sets and an end-range break four stretches, so their
    /// bodies are the design's fixed sentences. Nil for Movement, whose body counts its own break.
    var fixedBody: String? {
        switch self {
        case .movement: return nil
        case .strength: return "About 5 minutes, three sets. Have your weights nearby."
        case .endRange: return "Four minutes, four stretches. No weights needed."
        }
    }
}
