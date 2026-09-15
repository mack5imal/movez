import Foundation

/// Working hours and ad-hoc sessions (research §4.9).
///
/// Outside working hours movez is silent and stops polling entirely. The user can still start a
/// session by hand — an evening of work gets the same treatment as a weekday.
extension Scheduler {
    /// Called at the top of every tick, before the state machine runs.
    mutating func applyWorkingHours(now: Date) -> [SchedulerEffect] {
        if snapshot.adHocSession { return endAdHocSessionIfStale(now: now) }

        let within = config.workingHours.isWithin(now, calendar: config.calendar)
        switch snapshot.state {
        case .offHours:
            guard within else { return [] }
            return openWorkingDay(now: now)
        case .paused, .fullBreak:
            // A pause outlasts the working day, and a break already running is allowed to finish.
            return []
        default:
            guard !within else { return [] }
            return enterOffHours(now: now, reason: "outside working hours")
        }
    }

    mutating func enterOffHours(now: Date, reason: String) -> [SchedulerEffect] {
        let wasPolling = pollingRequired
        var effects = dismissSurfaces(now: now)
        snapshot.adHocSession = false
        snapshot.adHocSessionStartedAt = nil
        clearAwayMarkers()
        transition(to: .offHours, reason: reason, at: now)
        effects += [.persist, .menuRefresh]
        if wasPolling { effects.append(.pollingChanged(false)) }
        return effects
    }

    /// The working day opens with a clean interval and clean counters.
    ///
    /// One branch, not two: midnight has usually rolled the counters already (`rollDayIfStale`),
    /// so a "is this a new day?" test would read false by 09:00 and skip the roll that a session
    /// running through the night still needs.
    private mutating func openWorkingDay(now: Date) -> [SchedulerEffect] {
        rollDayCountersIfStale(now: now)
        return [.pollingChanged(true)] + startFreshSession(now: now, reason: "working hours started")
    }

    mutating func beginAdHocSession(now: Date) -> [SchedulerEffect] {
        snapshot.adHocSession = true
        snapshot.adHocSessionStartedAt = now
        // Rolls as well as stamps: a session started at 00:30 must not carry yesterday's counters.
        rollDayCountersIfStale(now: now)
        snapshot.dayKey = DayKey.key(for: now, calendar: config.calendar)
        startFreshInterval(now: now)
        transition(to: .sitting, reason: "session started by hand", at: now)
        return [.pollingChanged(true), .persist, .menuRefresh]
    }

    mutating func endAdHocSession(now: Date) -> [SchedulerEffect] {
        guard snapshot.adHocSession else { return [] }
        return enterOffHours(now: now, reason: "session ended")
    }

    /// An ad-hoc session does not survive midnight.
    private mutating func endAdHocSessionIfStale(now: Date) -> [SchedulerEffect] {
        guard let started = snapshot.adHocSessionStartedAt else { return [] }
        guard !config.calendar.isDate(now, inSameDayAs: started) else { return [] }
        return enterOffHours(now: now, reason: "session ended at midnight")
    }

    /// The next time the working day opens, for the off-hours menu.
    func nextWorkingStart(after now: Date) -> Date? {
        config.workingHours.nextStart(after: now, calendar: config.calendar)
    }
}
