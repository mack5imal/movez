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
        if case .paused = snapshot.state {
            return extendOrSwitchPause(seconds: seconds, focusInitiated: focusInitiated, now: now)
        }

        let wasPolling = pollingRequired
        var effects = dismissSurfaces(now: now)

        snapshot.remainingAtPauseSeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(now))) }
        snapshot.pauseStartedAt = now
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

    private mutating func extendOrSwitchPause(
        seconds: Int?,
        focusInitiated: Bool,
        now: Date
    ) -> [SchedulerEffect] {
        guard case .paused = snapshot.state else { return [] }
        // A Focus turning on over a pause the user set by hand changes nothing. The deliberate
        // choice outranks the automatic one — and rewriting it would both lengthen the pause to
        // the end of the day and leave the Focus unable to lift what it did not set.
        if focusInitiated, !snapshot.pauseIsFocusInitiated { return [] }

        snapshot.pauseIsFocusInitiated = focusInitiated
        let until = pauseEnd(seconds: seconds, focusInitiated: focusInitiated, now: now)
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

        // A pause can outlast the working day (a Focus left on overnight, say). Ending outside
        // working hours goes straight to off hours, and ending after a working day opened starts
        // that day fresh, as the opening itself would have: the countdown the pause put away
        // belongs to yesterday.
        if !snapshot.adHocSession, !config.workingHours.isWithin(now, calendar: config.calendar) {
            clearPauseBookkeeping()
            return enterOffHours(now: now, reason: "\(reason), outside working hours")
        }
        if let started = snapshot.pauseStartedAt,
           crossedWorkingDayOpening(gapSeconds: max(0, Int(now.timeIntervalSince(started))), now: now) {
            clearPauseBookkeeping()
            rollDayCountersIfStale(now: now)
            return [.pollingChanged(true)] + startFreshSession(now: now, reason: "\(reason), a working day opened during it")
        }

        // The bout moves on with the countdown the pause hands back, as it does for an absence,
        // so the time spent paused is never counted as time sat.
        if let started = snapshot.pauseStartedAt {
            snapshot.boutStartedAt = snapshot.boutStartedAt.addingTimeInterval(now.timeIntervalSince(started))
        }
        var effects = endPauseBookkeeping(now: now)
        transition(to: .sitting, reason: reason, at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    private mutating func clearPauseBookkeeping() {
        snapshot.remainingAtPauseSeconds = nil
        snapshot.pauseStartedAt = nil
        snapshot.pauseIsFocusInitiated = false
    }

    /// Restores the countdown a pause was holding and turns polling back on.
    mutating func endPauseBookkeeping(now: Date) -> [SchedulerEffect] {
        let remaining = snapshot.remainingAtPauseSeconds ?? config.sitSeconds
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(remaining))
        snapshot.nextMicroDueAt = microDue(anchoredAt: now)
        clearPauseBookkeeping()
        return [.pollingChanged(true)]
    }

    mutating func tickPaused(until: Date?, now: Date) -> [SchedulerEffect] {
        guard let until, now >= until else { return [] }
        return resumeFromPause(now: now, focusInitiated: false, reason: "pause elapsed")
    }
}
