import Foundation

/// The whole of the scheduler's mutable state, persisted on every transition so a crash, a
/// relaunch or a reboot resumes exactly where it left off.
struct SchedulerSnapshot: Codable, Equatable {
    var state: SchedulerState = .sitting
    var boutStartedAt: Date
    var lastCompletedBreakAt: Date?
    var nextFullDueAt: Date?
    var nextMicroDueAt: Date?

    var snoozesUsedThisBreak: Int = 0
    var snoozeAllowanceThisBreak: Int?
    var microSnoozeUsed: Bool = false
    var microAnchorAt: Date?

    var skipsToday: Int = 0
    var doneToday: Int = 0
    var snoozedToday: Int = 0
    var longestBoutSeconds: Int = 0
    var dayKey: String = ""

    /// The countdown as it stood when the user walked away or paused, so it can be handed back
    /// untouched rather than restarted.
    var remainingAtAwaySeconds: Int?
    var dueAtAway: Date?
    /// The largest input age seen since the user went away. Idle time only grows until something
    /// is touched, so a reading below it is the evidence of a return. Optional so older state
    /// files still decode.
    var awayInputAge: Int?
    var remainingAtPauseSeconds: Int?
    var pauseIsFocusInitiated: Bool = false
    var interruptedBreak: InterruptedBreak?
    var deferredFullDueAt: Date?
    var deferredReason: SuppressionReason?
    var creditRestore: CreditRestore?
    var adHocSession: Bool = false
    var adHocSessionStartedAt: Date?
    var postLunchPending: Bool = false

    var pendingInputWaitStartedAt: Date?
    /// When the file this snapshot came from was written — the app's proof of life, so a relaunch
    /// can tell whether it was gone for two minutes or two days.
    ///
    /// Optional, and it must stay Optional: the synthesized decoder uses `decodeIfPresent` for
    /// Optionals, so a `state.json` written before this field existed still loads. It is stamped
    /// on the way to disk and cleared on the way back, so it is nil in memory by design — which
    /// also means two snapshots that differ only in `savedAt` are not `==`.
    var savedAt: Date?
    var microEmphasisIndex: Int = 0
    var configHash: UInt64 = 0
    var transitions = TransitionLog()

    init(now: Date, dayKey: String = "") {
        boutStartedAt = now
        self.dayKey = dayKey
    }

    /// Seconds until the next full break, or nil when nothing is scheduled.
    func secondsUntilFullBreak(at now: Date) -> Int? {
        nextFullDueAt.map { max(0, Int($0.timeIntervalSince(now))) }
    }
}

/// A full break that sleep or a locked screen cut short.
struct InterruptedBreak: Codable, Equatable {
    var startedAt: Date
    var plannedEnd: Date
    var elapsedSeconds: Int
    var completedBlocks: Int
    var totalBlocks: Int
}

/// Enough of the snapshot to undo an away credit when the user taps "I was sitting".
struct CreditRestore: Codable, Equatable {
    var boutStartedAt: Date
    var nextFullDueAt: Date?
    var nextMicroDueAt: Date?
    var lastCompletedBreakAt: Date?
    var doneToday: Int
    var longestBoutSeconds: Int
    var expiresAt: Date
}

/// The day a date falls on, in the user's calendar. Used as the reset key for daily counters.
enum DayKey {
    static func key(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
