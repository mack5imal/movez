import Foundation

/// Idle handling: one threshold, one choice.
///
/// An absence shorter than the user's "Count me away after" is sitting, and nothing happens. A
/// longer one either resets both countdowns or pauses them, as the user has chosen, and is never a
/// break: it adds nothing to the day's count or the streak. It is logged, and the toast that says
/// what happened offers "I was sitting", because the app cannot tell a walk to the kitchen from a
/// long read on paper.
///
/// An absence as long as the sitting interval itself is standby — the countdowns simply start
/// again, silently, when the user comes back, whichever behaviour is chosen. It is logged as a
/// reset all the same.
///
/// An absence ends only on evidence that the user is back. The monitors report the input age on
/// every poll whether or not anything was touched, and treating each of those reports as a return
/// once credited a break every two seconds for as long as the user was gone.
extension Scheduler {
    mutating func handleIdle(seconds: Int, now: Date) -> [SchedulerEffect] {
        guard seconds >= config.awayThresholdSeconds else { return [] }
        guard snapshot.state.interruptibleByIdle else { return [] }

        // An absence cannot begin before the last break or the last absence ended, or the same
        // minutes are counted twice: once when the machine woke with nobody at it, and again when
        // the user came back.
        var since = now.addingTimeInterval(-Double(seconds))
        for floor in [snapshot.lastCompletedBreakAt, snapshot.lastAbsenceEndedAt].compactMap({ $0 }) where floor > since {
            since = floor
        }
        guard now.timeIntervalSince(since) >= Double(config.awayThresholdSeconds) else { return [] }

        var effects = dismissSurfaces(now: now)
        captureCountdowns(at: since)
        snapshot.awayInputAge = seconds
        transition(to: .away(since: since), reason: "idle for \(seconds / 60) min", at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    /// A poll while away.
    ///
    /// Idle time only grows until something is touched, so an input age lower than the last one
    /// seen is the evidence of a return, and nothing else is: not the age on its own, which is
    /// reported every two seconds whether anyone is there or not, and not the clock, which runs
    /// ahead of the idle counter under the debug time scale.
    mutating func handleInputWhileAway(age: Int, since: Date, now: Date) -> [SchedulerEffect] {
        guard let lastSeen = snapshot.awayInputAge, age < lastSeen else {
            // The first reading after a sleep or a lock sets the baseline; every later one that
            // has not dropped moves it on.
            snapshot.awayInputAge = age
            return []
        }
        return endAbsence(since: since, returnedAt: now, now: now)
    }

    /// The user is back — noticed by a keystroke, or by the end of the wake-quiet minute.
    ///
    /// One path for both, so which of the two notices first can never change what the absence
    /// was worth: an absence as long as the sitting interval is standby, a gap that crossed the
    /// opening of a working day starts the day over, a break the lid closed on accounts for its
    /// own absence, and anything else resets or pauses the countdowns.
    mutating func endAbsence(since: Date, returnedAt: Date, now: Date) -> [SchedulerEffect] {
        let absence = max(0, Int(returnedAt.timeIntervalSince(since)))
        snapshot.lastAbsenceEndedAt = returnedAt
        if absence >= config.sitSeconds {
            return enterStandby(absence: absence, since: since, now: now)
        }
        if crossedWorkingDayOpening(gapSeconds: absence, now: returnedAt) {
            return resetDay(now: now, reason: "gap crossed a working-day opening — new day")
        }

        // A break that was on screen when the lid closed accounts for that absence; the countdowns
        // must not be reset or paused for the same minutes as well.
        if snapshot.interruptedBreak != nil {
            snapshot.nextFullDueAt = snapshot.dueAtAway ?? snapshot.nextFullDueAt
            clearAwayMarkers()
            transition(to: .sitting, reason: "back after \(absence) s", at: now)
            return [.persist, .menuRefresh] + resumeInterruptedBreak(now: now)
        }

        return returnFromAway(since: since, absence: absence, now: now)
    }

    /// Away for at least a whole sitting interval: standby.
    ///
    /// Nothing is said — the user was not at the desk at all, and resuming a countdown from before
    /// lunch would only hand them a break the moment they sat down. The reset is logged like any
    /// other. The one thing kept is the bout that ended when they left, which is time they really
    /// did spend sitting. The day's counters move only if the absence crossed midnight, which is
    /// the only thing that ends a day.
    private mutating func enterStandby(absence: Int, since: Date, now: Date) -> [SchedulerEffect] {
        recordBout(endingAt: since)
        rollDayCountersIfStale(now: now)
        let record = AbsenceRecord(behaviour: .reset, awaySeconds: absence)
        return [.recordAbsence(record)] + startFreshSession(now: now, reason: "away \(absence / 60) min — standby")
    }

    private mutating func returnFromAway(since: Date, absence: Int, now: Date) -> [SchedulerEffect] {
        if absence < config.awayThresholdSeconds {
            snapshot.nextFullDueAt = snapshot.dueAtAway ?? snapshot.nextFullDueAt
            clearAwayMarkers()
            transition(to: .sitting, reason: "back after \(absence) s", at: now)
            return [.persist, .menuRefresh]
        }

        captureCreditRestore(now: now)
        switch config.awayBehaviour {
        case .reset: resetCountdowns(since: since, now: now)
        case .pause: pauseCountdowns(since: since, absence: absence)
        }
        clearAwayMarkers()
        let verb = config.awayBehaviour == .reset ? "reset" : "paused"
        transition(to: .sitting, reason: "away \(absence / 60) min, countdowns \(verb)", at: now)

        let toast = ToastInfo(
            behaviour: config.awayBehaviour,
            awaySeconds: absence,
            nextBreakAt: snapshot.nextFullDueAt,
            reversal: .wasSitting
        )
        let record = AbsenceRecord(behaviour: config.awayBehaviour, awaySeconds: absence)
        return [.recordAbsence(record), .showToast(toast), .chime(.toast), .persist, .menuRefresh]
    }

    /// Both countdowns start again from now. The bout that ended when the user left is kept, but
    /// nothing is counted as done: the last break is still the last break.
    private mutating func resetCountdowns(since: Date, now: Date) {
        recordBout(endingAt: since)
        startFreshInterval(now: now)
    }

    /// Both countdowns carry on with exactly the time they had when the user left.
    ///
    /// The bout and the micro anchor move forward by the absence along with the due times, as the
    /// launch shift does: `apply(_:)` re-plans from them when a setting changes, and left behind
    /// they would make the countdown jump for no reason the user can see.
    private mutating func pauseCountdowns(since: Date, absence: Int) {
        let gap = TimeInterval(absence)
        let returnedAt = since.addingTimeInterval(gap)
        snapshot.boutStartedAt = snapshot.boutStartedAt.addingTimeInterval(gap)
        snapshot.microAnchorAt = snapshot.microAnchorAt?.addingTimeInterval(gap)
        let full = snapshot.remainingAtAwaySeconds.map { returnedAt.addingTimeInterval(TimeInterval($0)) }
        snapshot.nextFullDueAt = full ?? snapshot.nextFullDueAt
        snapshot.nextMicroDueAt = snapshot.remainingMicroAtAwaySeconds.flatMap { remaining in
            let micro = returnedAt.addingTimeInterval(TimeInterval(remaining))
            // The same quiet zone `microDue` keeps before a full break.
            if let full = snapshot.nextFullDueAt,
               full.timeIntervalSince(micro) < Double(config.microMinGapBeforeFullSeconds) { return nil }
            return micro
        }
    }

    /// "I was sitting" — put back exactly what the absence changed, as long as the toast is still
    /// on screen.
    mutating func reverseCredit(now: Date) -> [SchedulerEffect] {
        guard let restore = snapshot.creditRestore, now <= restore.expiresAt else { return [] }
        snapshot.boutStartedAt = restore.boutStartedAt
        snapshot.nextFullDueAt = restore.nextFullDueAt
        snapshot.nextMicroDueAt = restore.nextMicroDueAt
        snapshot.microAnchorAt = restore.microAnchorAt
        snapshot.lastCompletedBreakAt = restore.lastCompletedBreakAt
        snapshot.doneToday = restore.doneToday
        snapshot.longestBoutSeconds = restore.longestBoutSeconds
        snapshot.creditRestore = nil
        transition(to: .sitting, reason: "absence reversed — I was sitting", at: now)
        return [.hideToast, .persist, .menuRefresh]
    }

    private mutating func captureCreditRestore(now: Date) {
        snapshot.creditRestore = CreditRestore(
            boutStartedAt: snapshot.boutStartedAt,
            nextFullDueAt: snapshot.dueAtAway ?? snapshot.nextFullDueAt,
            nextMicroDueAt: snapshot.nextMicroDueAt,
            microAnchorAt: snapshot.microAnchorAt,
            lastCompletedBreakAt: snapshot.lastCompletedBreakAt,
            doneToday: snapshot.doneToday,
            longestBoutSeconds: snapshot.longestBoutSeconds,
            expiresAt: now.addingTimeInterval(TimeInterval(ToastInfo.defaultSecondsOnScreen))
        )
    }

    /// Notes what both countdowns had left when the user went, measured from when they went.
    mutating func captureCountdowns(at since: Date) {
        snapshot.dueAtAway = snapshot.nextFullDueAt
        snapshot.remainingAtAwaySeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(since))) }
        snapshot.remainingMicroAtAwaySeconds = snapshot.nextMicroDueAt.map { max(0, Int($0.timeIntervalSince(since))) }
    }

    /// Forgets the countdown an absence was holding. Called on every way out of an absence: a
    /// `dueAtAway` left behind is yesterday's due time waiting for the next short gap to restore it.
    mutating func clearAwayMarkers() {
        snapshot.remainingAtAwaySeconds = nil
        snapshot.remainingMicroAtAwaySeconds = nil
        snapshot.dueAtAway = nil
        snapshot.awayInputAge = nil
    }

    /// Takes every break surface off screen. Used by sleep, lock, pause and idle alike.
    ///
    /// It takes `now` rather than reaching for `Date()`: the scheduler is a pure function of the
    /// clock it is handed, and a single wall-clock read in here would break replay at 60×.
    mutating func dismissSurfaces(now: Date) -> [SchedulerEffect] {
        switch snapshot.state {
        case .headsUp, .pendingFull:
            return [.hideHeadsUp]
        case .fullBreak:
            return [.endFullBreak(.interrupted)]
        case .microCountIn, .microRunning:
            let record = microRecord(now: now)
            snapshot.nextMicroDueAt = microDue(anchoredAt: snapshot.microAnchorAt ?? now)
            snapshot.microAnchorAt = nil
            snapshot.microSnoozeUsed = false
            return record + [.hideMicro]
        default:
            return []
        }
    }
}
