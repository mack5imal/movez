import Foundation

/// The chimes the app can play.
enum Chime: String, Codable, Equatable, CaseIterable {
    case headsUp
    case transition
    case completion
    /// One soft note as the away toast appears, so a toast that lands while the user is still
    /// turning back to the screen is not missed.
    case toast

    var resourceName: String {
        switch self {
        case .headsUp: return "headsup"
        case .transition: return "transition"
        case .completion: return "completion"
        case .toast: return "toast"
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
    var deferredReason: SuppressionReason?
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

    /// How long the credit stays reversible, which is how long the toast stays on screen.
    ///
    /// Fifteen, not the handoff's six: the toast usually lands the moment a display wakes, and six
    /// seconds had gone before a hand reached the trackpad (`docs/DECISIONS.md` 23a).
    static let defaultSecondsOnScreen = 15

    var kind: Kind
    var awaySeconds: Int
    var nextBreakAt: Date?
    var reversal: ToastReversal
    var secondsOnScreen: Int = ToastInfo.defaultSecondsOnScreen
}

/// What became of a break that was never started, so the coordinator can write it down.
///
/// A heads-up that is snoozed or skipped leaves nothing on screen to end, so `hideHeadsUp` is all
/// the coordinator used to see — and that same effect is sent by sleep, idle and a pause. The
/// outcome has to be named, or the day's snoozes and skips are the overlay's only.
enum HeadsUpOutcome: String, Equatable {
    case snoozed
    case skipped
}

/// Everything the scheduler asks the world to do. The scheduler itself touches nothing.
enum SchedulerEffect: Equatable {
    case showHeadsUp(HeadsUpInfo)
    case hideHeadsUp
    case recordHeadsUpOutcome(HeadsUpOutcome)
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
    ///
    /// One exhaustive switch, so adding an effect fails to build rather than quietly reporting
    /// itself as "unknown" in every test that reads this.
    var name: String {
        switch self {
        case .showHeadsUp: return "showHeadsUp"
        case .hideHeadsUp: return "hideHeadsUp"
        case .recordHeadsUpOutcome(let outcome): return "recordHeadsUpOutcome(\(outcome.rawValue))"
        case .startFullBreak: return "startFullBreak"
        case .endFullBreak: return "endFullBreak"
        case .showMicroCountIn: return "showMicroCountIn"
        case .showMicroRunning: return "showMicroRunning"
        case .hideMicro: return "hideMicro"
        case .chime(let chime): return "chime(\(chime.rawValue))"
        case .showToast: return "showToast"
        case .hideToast: return "hideToast"
        case .persist: return "persist"
        case .pollingChanged(let enabled): return "pollingChanged(\(enabled))"
        case .menuRefresh: return "menuRefresh"
        }
    }

}
