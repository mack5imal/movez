import Foundation

/// Idle handling: three thresholds, one policy (research §4.2).
///
/// Under three minutes nothing happens. Three to five minutes is treated as a micro-break and the
/// countdown is handed back with the time that was left on it. Five minutes or more counts as a
/// full break. Both credits are reversible while the toast is up, because the app cannot tell a
/// walk to the kitchen from a long read on paper.
///
/// An absence ends only on evidence that the user is back. The monitors report the input age on
/// every poll whether or not anything was touched, and treating each of those reports as a return
/// credited a break every two seconds for as long as the user was gone.
extension Scheduler {
    mutating func handleIdle(seconds: Int, now: Date) -> [SchedulerEffect] {
        guard seconds >= config.awayThresholdSeconds else { return [] }
        guard snapshot.state.interruptibleByIdle else { return [] }

        // An absence cannot begin before the last break ended, or the same minutes are credited
        // twice: once when the machine woke with nobody at it, and again when the user came back.
        var since = now.addingTimeInterval(-Double(seconds))
        if let lastBreak = snapshot.lastCompletedBreakAt, lastBreak > since { since = lastBreak }
        guard now.timeIntervalSince(since) >= Double(config.awayThresholdSeconds) else { return [] }

        var effects = dismissSurfaces(now: now)
        snapshot.dueAtAway = snapshot.nextFullDueAt
        snapshot.remainingAtAwaySeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(since))) }
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
    /// was worth: a gap long enough to end the session starts the day over, a break the lid closed
    /// on is the credit for its own absence, and anything else goes through the idle table.
    mutating func endAbsence(since: Date, returnedAt: Date, now: Date) -> [SchedulerEffect] {
        let absence = max(0, Int(returnedAt.timeIntervalSince(since)))
        if shouldResetDay(gapSeconds: absence, now: returnedAt) {
            return resetDay(now: now, reason: "gap of \(absence / 3600) h — new day")
        }

        // A break that was on screen when the lid closed is the credit for that absence; the
        // idle table must not credit the same minutes a second time.
        if snapshot.interruptedBreak != nil {
            snapshot.nextFullDueAt = snapshot.dueAtAway ?? snapshot.nextFullDueAt
            clearAwayMarkers()
            transition(to: .sitting, reason: "back after \(absence) s", at: now)
            return [.persist, .menuRefresh] + resumeInterruptedBreak(now: now)
        }

        return returnFromAway(since: since, absence: absence, returnedAt: returnedAt, now: now)
    }

    private mutating func returnFromAway(since: Date, absence: Int, returnedAt: Date, now: Date) -> [SchedulerEffect] {
        notePostLunch(absence: absence, returnedAt: returnedAt)

        if absence < config.awayThresholdSeconds {
            snapshot.nextFullDueAt = snapshot.dueAtAway ?? snapshot.nextFullDueAt
            clearAwayMarkers()
            transition(to: .sitting, reason: "back after \(absence) s", at: now)
            return [.persist, .menuRefresh]
        }

        captureCreditRestore(now: now)
        return absence >= config.fullCreditSeconds
            ? creditFullBreak(absence: absence, since: since, now: now)
            : creditMicroBreak(absence: absence, now: now)
    }

    /// Three to five minutes away: not a break, but a real interruption of the sitting bout. The
    /// countdown resumes with exactly the time it had left.
    private mutating func creditMicroBreak(absence: Int, now: Date) -> [SchedulerEffect] {
        let remaining = snapshot.remainingAtAwaySeconds ?? config.sitSeconds
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(remaining))
        snapshot.nextMicroDueAt = microDue(anchoredAt: now)
        clearAwayMarkers()
        transition(to: .sitting, reason: "away \(absence / 60) min, counted as a micro-break", at: now)

        let toast = ToastInfo(
            kind: .creditedMicroBreak,
            awaySeconds: absence,
            nextBreakAt: snapshot.nextFullDueAt,
            reversal: .wasSittingAfterMicroCredit
        )
        return [.showToast(toast), .chime(.toast), .persist, .menuRefresh]
    }

    /// Five minutes or more away is a break, whatever the user was doing.
    private mutating func creditFullBreak(absence: Int, since: Date, now: Date) -> [SchedulerEffect] {
        snapshot.doneToday += 1
        snapshot.lastCompletedBreakAt = now
        recordBout(endingAt: since)
        startFreshInterval(now: now)
        clearAwayMarkers()
        transition(to: .sitting, reason: "away \(absence / 60) min, credited as a break", at: now)

        let toast = ToastInfo(
            kind: .creditedFullBreak,
            awaySeconds: absence,
            nextBreakAt: snapshot.nextFullDueAt,
            reversal: .wasSittingAfterFullCredit
        )
        return [.showToast(toast), .chime(.toast), .persist, .menuRefresh]
    }

    /// "I was sitting" — put back exactly what the credit changed, as long as the toast is still
    /// on screen.
    mutating func reverseCredit(now: Date) -> [SchedulerEffect] {
        guard let restore = snapshot.creditRestore, now <= restore.expiresAt else { return [] }
        snapshot.boutStartedAt = restore.boutStartedAt
        snapshot.nextFullDueAt = restore.nextFullDueAt
        snapshot.nextMicroDueAt = restore.nextMicroDueAt
        snapshot.lastCompletedBreakAt = restore.lastCompletedBreakAt
        snapshot.doneToday = restore.doneToday
        snapshot.longestBoutSeconds = restore.longestBoutSeconds
        snapshot.creditRestore = nil
        transition(to: .sitting, reason: "credit reversed — I was sitting", at: now)
        return [.hideToast, .persist, .menuRefresh]
    }

    private mutating func captureCreditRestore(now: Date) {
        snapshot.creditRestore = CreditRestore(
            boutStartedAt: snapshot.boutStartedAt,
            nextFullDueAt: snapshot.dueAtAway ?? snapshot.nextFullDueAt,
            nextMicroDueAt: snapshot.nextMicroDueAt,
            lastCompletedBreakAt: snapshot.lastCompletedBreakAt,
            doneToday: snapshot.doneToday,
            longestBoutSeconds: snapshot.longestBoutSeconds,
            expiresAt: now.addingTimeInterval(TimeInterval(ToastInfo.defaultSecondsOnScreen))
        )
    }

    /// Forgets the countdown an absence was holding. Called on every way out of an absence: a
    /// `dueAtAway` left behind is yesterday's due time waiting for the next short gap to restore it.
    mutating func clearAwayMarkers() {
        snapshot.remainingAtAwaySeconds = nil
        snapshot.dueAtAway = nil
        snapshot.awayInputAge = nil
    }

    /// A long absence ending over the middle of the day is lunch, and the next routine should say
    /// so with circulation and balance.
    private mutating func notePostLunch(absence: Int, returnedAt now: Date) {
        guard absence >= 20 * 60 else { return }
        let minutes = WorkingHours.minutes(of: now, calendar: config.calendar)
        guard minutes >= 11 * 60, minutes < 14 * 60 else { return }
        snapshot.postLunchPending = true
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
            snapshot.nextMicroDueAt = microDue(anchoredAt: snapshot.microAnchorAt ?? now)
            snapshot.microAnchorAt = nil
            snapshot.microSnoozeUsed = false
            return [.hideMicro]
        default:
            return []
        }
    }
}
