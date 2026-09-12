import Foundation

/// The chimes the app can play.
enum Chime: String, Codable, Equatable, CaseIterable {
    case headsUp
    case transition
    case completion

    var resourceName: String {
        switch self {
        case .headsUp: return "headsup"
        case .transition: return "transition"
        case .completion: return "completion"
        }
    }
}

/// What the heads-up panel needs to render itself.
struct HeadsUpInfo: Equatable {
    var dueAt: Date
    var startsAt: Date
    /// When the current sitting stretch began — the last completed break, or the bout start.
    var sittingSince: Date
    var sittingSeconds: Int
    var snoozesLeft: Int
    var maxSnoozes: Int
    var skipsToday: Int
    var deferred: Bool = false
    var deferredSince: Date?
    var deferredForSeconds: Int?
    /// A break that waited more than half an hour says so, and gets one snooze instead of two.
    var showDeferredBadge: Bool = false
}

/// The scheduler's half of a break. The coordinator attaches the generated routine.
struct BreakPlan: Equatable {
    var startedAt: Date
    var seconds: Int
    var deferred: Bool = false
}

/// How a break finished.
enum BreakOutcome: Equatable {
    case completed(completedBlocks: Int, totalBlocks: Int, elapsed: Int)
    case skipped(completedBlocks: Int)
    case snoozed
    case interrupted
}

/// What the micro-break panel needs.
struct MicroInfo: Equatable {
    var startsAt: Date
    var countInSeconds: Int
    var seconds: Int
}

/// The away toast.
struct ToastInfo: Equatable {
    enum Kind: String, Equatable {
        case creditedFullBreak
        case creditedMicroBreak
    }

    var kind: Kind
    var awaySeconds: Int
    var nextBreakAt: Date?
    var reversal: ToastReversal
    var secondsOnScreen: Int = 6
}

/// Everything the scheduler asks the world to do. The scheduler itself touches nothing.
enum SchedulerEffect: Equatable {
    case showHeadsUp(HeadsUpInfo)
    case hideHeadsUp
    case startFullBreak(BreakPlan)
    case endFullBreak(BreakOutcome)
    case showMicroCountIn(MicroInfo)
    case showMicroRunning
    case hideMicro
    case chime(Chime)
    case showToast(ToastInfo)
    case hideToast
    case persist
    case pollingChanged(Bool)
    case menuRefresh
}

extension SchedulerEffect {
    /// A short, stable label for logs, tests and the debug inspector.
    var name: String { surfaceName ?? sideEffectName }

    /// The effects that put something on screen or take it away.
    private var surfaceName: String? {
        switch self {
        case .showHeadsUp: return "showHeadsUp"
        case .hideHeadsUp: return "hideHeadsUp"
        case .startFullBreak: return "startFullBreak"
        case .endFullBreak: return "endFullBreak"
        case .showMicroCountIn: return "showMicroCountIn"
        case .showMicroRunning: return "showMicroRunning"
        case .hideMicro: return "hideMicro"
        default: return nil
        }
    }

    /// Everything else: sound, toasts and bookkeeping.
    private var sideEffectName: String {
        switch self {
        case .chime(let chime): return "chime(\(chime.rawValue))"
        case .showToast: return "showToast"
        case .hideToast: return "hideToast"
        case .persist: return "persist"
        case .pollingChanged(let enabled): return "pollingChanged(\(enabled))"
        case .menuRefresh: return "menuRefresh"
        default: return "unknown"
        }
    }
}
