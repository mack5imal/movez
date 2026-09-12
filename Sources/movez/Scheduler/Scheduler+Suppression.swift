import Foundation

/// Suppression (research §4.4): a break that comes due during a call, a screen share or a
/// fullscreen presentation is **deferred, never dropped and never reset**. The countdown keeps
/// running; only the interruption waits.
extension Scheduler {
    mutating func handleSignals(_ signals: SignalSnapshot, now: Date) -> [SchedulerEffect] {
        signals.suppressing ? beginSuppression(signals.reason, now: now) : endSuppression(now: now)
    }

    private mutating func beginSuppression(_ reason: SuppressionReason?, now: Date) -> [SchedulerEffect] {
        var deferred: Date?
        var effects: [SchedulerEffect] = []

        switch snapshot.state {
        case .sitting:
            break
        case .pendingFull, .snoozed:
            // A snooze that runs out during a call must not put the heads-up on screen for the
            // two seconds it takes the next poll to notice.
            deferred = snapshot.nextFullDueAt
        case .headsUp(_, let deferredSince):
            deferred = deferredSince ?? snapshot.nextFullDueAt
            effects.append(.hideHeadsUp)
        case .microCountIn, .microRunning:
            effects += dismissSurfaces(now: now)
        default:
            // A break already on screen is left alone, and paused or off-hours outrank a call.
            return []
        }

        snapshot.deferredFullDueAt = deferred ?? snapshot.deferredFullDueAt
        snapshot.deferredReason = reason ?? snapshot.deferredReason
        transition(to: .suppressed(since: now, deferredFullDue: deferred), reason: "call or screen share", at: now)
        return effects + [.persist, .menuRefresh]
    }

    private mutating func endSuppression(now: Date) -> [SchedulerEffect] {
        guard case .suppressed = snapshot.state else { return [] }
        let until = now.addingTimeInterval(TimeInterval(config.postSuppressionGraceSeconds))
        transition(to: .postBreakGrace(until: until, resumeTo: .afterSuppression), reason: "signals cleared", at: now)
        return [.persist, .menuRefresh]
    }

    mutating func resumeAfterSuppression(now: Date) -> [SchedulerEffect] {
        guard snapshot.deferredFullDueAt != nil else {
            transition(to: .sitting, reason: "back from a call, nothing was due", at: now)
            return [.persist, .menuRefresh]
        }
        return enterPendingFull(now: now)
    }

    /// While suppressed the countdown still runs; reaching zero simply records that a break is
    /// waiting, at its original due time.
    mutating func tickSuppressed(since: Date, deferredFullDue: Date?, now: Date) -> [SchedulerEffect] {
        var effects: [SchedulerEffect] = []

        if deferredFullDue == nil, let due = snapshot.nextFullDueAt, now >= due {
            snapshot.deferredFullDueAt = due
            transition(to: .suppressed(since: since, deferredFullDue: due), reason: "break deferred", at: now)
            effects += [.persist, .menuRefresh]
        }

        if let micro = snapshot.nextMicroDueAt, now >= micro {
            // A micro-break during a call is simply not worth having.
            snapshot.nextMicroDueAt = microDue(anchoredAt: now)
            effects.append(.persist)
        }
        return effects
    }
}
