import Foundation

/// Where the scheduler resumes after a grace period ends.
enum GraceResume: Codable, Equatable {
    case sitting
    case pendingFull
    /// A wake or unlock: apply the idle table to the gap the machine was away for.
    case applyGap(seconds: Int)
    /// A call or screen share ended: serve the deferred break, or go back to sitting.
    case afterSuppression
}

/// Every state the scheduler can be in (research §5).
///
/// `away`, `suppressed`, `paused`, `offHours` and `postBreakGrace` are declared here so the
/// persisted shape is stable from the first release; their transitions arrive with the
/// interruption rules.
enum SchedulerState: Codable, Equatable {
    case offHours
    case paused(until: Date?)
    case sitting
    case away(since: Date)
    case suppressed(since: Date, deferredFullDue: Date?)
    case pendingFull(since: Date)
    case headsUp(startedAt: Date, deferredSince: Date?)
    case snoozed(until: Date)
    case microCountIn(startedAt: Date)
    case microRunning(startedAt: Date)
    case fullBreak(startedAt: Date)
    case postBreakGrace(until: Date, resumeTo: GraceResume)

    /// A short, stable label for the transition log and the debug inspector.
    var name: String {
        switch self {
        case .offHours: return "off_hours"
        case .paused: return "paused"
        case .sitting: return "sitting"
        case .away: return "away"
        case .suppressed: return "suppressed"
        case .pendingFull: return "pending_full"
        case .headsUp: return "heads_up"
        case .snoozed: return "snoozed"
        case .microCountIn: return "micro_count_in"
        case .microRunning: return "micro_running"
        case .fullBreak: return "full_break"
        case .postBreakGrace: return "post_break_grace"
        }
    }

    /// True while a full break is on screen in any form.
    var isBreakSurfaceVisible: Bool {
        switch self {
        case .headsUp, .fullBreak, .microCountIn, .microRunning: return true
        default: return false
        }
    }

    /// The states an idle stretch may interrupt. A running full break is not one of them: the
    /// user standing still during a stretch is the point.
    var interruptibleByIdle: Bool {
        switch self {
        case .sitting, .pendingFull, .headsUp, .microCountIn, .microRunning: return true
        default: return false
        }
    }

    /// The sitting countdown only runs in these states.
    var countdownRuns: Bool {
        switch self {
        case .sitting, .suppressed, .pendingFull, .microCountIn, .microRunning: return true
        default: return false
        }
    }
}
