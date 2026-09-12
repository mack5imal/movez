import Foundation

/// Manual pause and the Focus Filter (research §4.5).
///
/// A pause never costs the user the time they have already sat: the remaining countdown is put in
/// a drawer and handed back when the pause lifts. A Focus filter turning off does not lift a
/// pause the user set by hand.
extension Scheduler {
    /// Pass nil seconds for "the rest of the day".
    mutating func pause(seconds: Int?, focusInitiated: Bool, now: Date) -> [SchedulerEffect] {
        if case .fullBreak = snapshot.state { return [] }
        if case .paused = snapshot.state { return extendOrSwitchPause(seconds: seconds, now: now) }

        let wasPolling = pollingRequired
        var effects = dismissSurfaces()

        snapshot.remainingAtPauseSeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(now))) }
        snapshot.pauseIsFocusInitiated = focusInitiated
        let until = pauseEnd(seconds: seconds, focusInitiated: focusInitiated, now: now)
        transition(to: .paused(until: until), reason: focusInitiated ? "focus filter" : "paused by hand", at: now)

        effects += [.persist, .menuRefresh]
        if wasPolling { effects.append(.pollingChanged(false)) }
        return effects
    }

    private func pauseEnd(seconds: Int?, focusInitiated: Bool, now: Date) -> Date? {
        if focusInitiated { return nil }
        if let seconds { return now.addingTimeInterval(TimeInterval(seconds)) }
        // "Rest of the day" runs to the end of working hours, or to midnight on a day off.
        return config.workingHours.endOfToday(now, calendar: config.calendar)
            ?? config.calendar.startOfDay(for: now).addingTimeInterval(24 * 3600 - 60)
    }

    private mutating func extendOrSwitchPause(seconds: Int?, now: Date) -> [SchedulerEffect] {
        guard case .paused = snapshot.state else { return [] }
        let until = pauseEnd(seconds: seconds, focusInitiated: false, now: now)
        transition(to: .paused(until: until), reason: "pause changed", at: now)
        return [.persist, .menuRefresh]
    }

    mutating func extendPause(seconds: Int, now: Date) -> [SchedulerEffect] {
        guard case .paused(let until) = snapshot.state else { return [] }
        let extended = (until ?? now).addingTimeInterval(TimeInterval(seconds))
        transition(to: .paused(until: extended), reason: "pause extended", at: now)
        return [.persist, .menuRefresh]
    }

    mutating func resumeFromPause(now: Date, focusInitiated: Bool, reason: String) -> [SchedulerEffect] {
        guard case .paused = snapshot.state else { return [] }
        // A Focus filter switching off must not cancel a pause the user set deliberately.
        if focusInitiated, !snapshot.pauseIsFocusInitiated { return [] }

        var effects = endPauseBookkeeping(now: now)
        transition(to: .sitting, reason: reason, at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    /// Restores the countdown a pause was holding and turns polling back on.
    mutating func endPauseBookkeeping(now: Date) -> [SchedulerEffect] {
        let remaining = snapshot.remainingAtPauseSeconds ?? config.sitSeconds
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(remaining))
        snapshot.nextMicroDueAt = microDue(anchoredAt: now)
        snapshot.remainingAtPauseSeconds = nil
        snapshot.pauseIsFocusInitiated = false
        return [.pollingChanged(true)]
    }

    mutating func tickPaused(until: Date?, now: Date) -> [SchedulerEffect] {
        guard let until, now >= until else { return [] }
        return resumeFromPause(now: now, focusInitiated: false, reason: "pause elapsed")
    }
}
