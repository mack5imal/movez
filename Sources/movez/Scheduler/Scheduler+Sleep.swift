import Foundation

/// Sleep, lock and wake (research §4.3).
///
/// Nothing fires for a minute after the machine comes back — waking up to a break overlay is the
/// single most complained-about behaviour in this category of app. After that quiet minute the
/// gap is treated exactly like an idle stretch of the same length.
extension Scheduler {
    mutating func handleSleepOrLock(now: Date, reason: String) -> [SchedulerEffect] {
        switch snapshot.state {
        case .away:
            // Already away. A lock on top of an idle stretch must not restart the clock on it,
            // or a six-minute absence is measured as the four minutes since the screen locked.
            return []
        case .paused, .offHours:
            // A pause outlasts a closed lid, and off hours there is nothing to interrupt. Going
            // away here would cancel the pause and credit a break the user never took.
            return []
        case .postBreakGrace(_, .returnFromAbsence(let since, _)):
            // Woke and went straight back to sleep inside the quiet minute. The absence being
            // resolved is still going, and it began when the user first left, not now.
            snapshot.awayInputAge = nil
            transition(to: .away(since: since), reason: reason, at: now)
            return [.persist, .menuRefresh]
        default:
            break
        }

        if case .fullBreak(let startedAt) = snapshot.state {
            snapshot.interruptedBreak = InterruptedBreak(
                startedAt: startedAt,
                plannedEnd: startedAt.addingTimeInterval(TimeInterval(config.breakSeconds)),
                elapsedSeconds: max(0, Int(now.timeIntervalSince(startedAt))),
                completedBlocks: 0,
                totalBlocks: 0
            )
        }

        // Sleep takes every surface down, not just the one that happened to be showing: waking
        // to a stale overlay is the loudest failure this whole category of app has.
        var effects = dismissSurfaces(now: now)
        for dismissal in [SchedulerEffect.hideHeadsUp, .hideMicro] where !effects.contains(dismissal) {
            effects.append(dismissal)
        }
        snapshot.dueAtAway = snapshot.nextFullDueAt
        snapshot.remainingAtAwaySeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(now))) }
        // The idle age at the moment of locking is unknown here; the next poll sets the baseline.
        snapshot.awayInputAge = nil
        transition(to: .away(since: now), reason: reason, at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    /// The machine or the screen came back.
    ///
    /// macOS sends several notifications for one return — wake, screens wake, session active,
    /// unlock — and each measures its gap from the last poll, which the monitors take again within
    /// two seconds of waking. A later notification therefore routinely reports a gap of nothing
    /// for an absence of hours. So the absence is measured from when it began, which the scheduler
    /// already knows, and a later, smaller report can never shrink it.
    mutating func handleWake(
        gapSeconds: Int,
        now: Date,
        reason: String,
        fromTickGap: Bool = false
    ) -> [SchedulerEffect] {
        let reportedStart = now.addingTimeInterval(-Double(gapSeconds))
        switch snapshot.state {
        case .paused, .offHours:
            // A pause outlasts a closed lid in both directions, and off hours there is nothing to
            // come back to — the mirrors of the guards in `handleSleepOrLock`. Without them the
            // wake cancels the pause, or leaves off hours with the monitors still stopped.
            return []
        case .away(let since):
            // A poll that ran late is App Nap, not the user. Input or a real wake ends an absence.
            if fromTickGap { return [] }
            return enterAbsenceGrace(since: min(since, reportedStart), returnedAt: now, now: now, reason: reason)
        case .postBreakGrace(_, .returnFromAbsence(let since, let returnedAt)):
            return enterAbsenceGrace(since: min(since, reportedStart), returnedAt: returnedAt, now: now, reason: reason)
        default:
            // Nothing was away, so a gap no longer than a poll is the notification for a return
            // that has already been handled. Treating it as a wake would throw away a heads-up, a
            // snooze or a deferred break for a quiet minute that protects nothing.
            guard Double(gapSeconds) > SignalAggregator.tickGapThresholdSeconds else { return [] }
            return enterAbsenceGrace(since: reportedStart, returnedAt: now, now: now, reason: reason)
        }
    }

    private mutating func enterAbsenceGrace(
        since: Date,
        returnedAt: Date,
        now: Date,
        reason: String
    ) -> [SchedulerEffect] {
        let until = now.addingTimeInterval(TimeInterval(config.wakeQuietSeconds))
        let resume = GraceResume.returnFromAbsence(since: since, returnedAt: returnedAt)
        transition(to: .postBreakGrace(until: until, resumeTo: resume), reason: reason, at: now)
        return [.persist, .menuRefresh]
    }

    /// The quiet minute is over. Decide what the gap meant.
    mutating func applyGrace(_ resume: GraceResume, now: Date) -> [SchedulerEffect] {
        switch resume {
        case .returnFromAbsence(let since, let returnedAt):
            return endAbsence(since: since, returnedAt: returnedAt, now: now)
        case .applyGap(let seconds):
            // Written by an earlier build, which measured the gap back from the end of the grace.
            return endAbsence(since: now.addingTimeInterval(-Double(seconds)), returnedAt: now, now: now)
        case .afterSuppression:
            return resumeAfterSuppression(now: now)
        case .pendingFull:
            return enterPendingFull(now: now)
        case .sitting:
            transition(to: .sitting, reason: "grace ended", at: now)
            return [.persist, .menuRefresh]
        }
    }

    /// A break cut short by a closed lid picks up where it left off if the machine came back
    /// before the break was due to end; otherwise it is judged by the completion rule.
    mutating func resumeInterruptedBreak(now: Date) -> [SchedulerEffect] {
        guard let interrupted = snapshot.interruptedBreak else { return [] }
        snapshot.interruptedBreak = nil

        guard now < interrupted.plannedEnd else {
            let counts = Scheduler.meetsCompletionRule(
                completed: interrupted.completedBlocks,
                total: interrupted.totalBlocks,
                elapsed: interrupted.elapsedSeconds,
                config: config
            )
            if counts {
                snapshot.doneToday += 1
                snapshot.lastCompletedBreakAt = now
                recordBout(endingAt: interrupted.startedAt)
                startFreshInterval(now: now)
            } else {
                snapshot.skipsToday += 1
                snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(config.sitSeconds))
                snapshot.nextMicroDueAt = microDue(anchoredAt: now)
            }
            return [.persist, .menuRefresh]
        }

        let resumedStart = now.addingTimeInterval(-Double(interrupted.elapsedSeconds))
        transition(to: .fullBreak(startedAt: resumedStart), reason: "break resumed after wake", at: now)
        let plan = BreakPlan(startedAt: resumedStart, seconds: config.breakSeconds)
        return [.startFullBreak(plan), .persist, .menuRefresh]
    }

    /// The app was not running for a while.
    ///
    /// Time movez could not observe is time it will not judge. A running app knows from the idle
    /// clock whether the user was at the keyboard; an app that was not running knows nothing, so
    /// the countdown is moved forward by the gap rather than credited as a break. Only a gap long
    /// enough to have ended the session outright starts the day over.
    mutating func applyLaunchGap(seconds: Int, now: Date) -> [SchedulerEffect] {
        guard Double(seconds) > SignalAggregator.tickGapThresholdSeconds else {
            return rollDayIfStale(now: now)
        }

        switch snapshot.state {
        case .paused, .offHours:
            // A pause and a closed working day outrank a gap, exactly as they do a closed lid.
            return rollDayIfStale(now: now)
        default:
            break
        }

        if snapshot.state.isBreakSurfaceVisible {
            // Whatever was on screen died with the process. There is nothing left to resume.
            rollDayCountersIfStale(now: now)
            return startFreshSession(now: now, reason: "relaunched with a break on screen")
        }

        if seconds >= config.dayResetGapSeconds {
            return resetDay(now: now, reason: "gone \(seconds / 3600) h — new day")
        }

        return shiftInterval(by: seconds, now: now)
    }

    /// Moves the bout forward by the time the app was not watching, so the user keeps exactly the
    /// countdown they had.
    ///
    /// `boutStartedAt` moves with the due times rather than staying put: `apply(_:)` recomputes
    /// `nextFullDueAt` from it whenever a setting changes, so the two drifting apart would show up
    /// later as a countdown that jumps for no reason the user can see.
    private mutating func shiftInterval(by seconds: Int, now: Date) -> [SchedulerEffect] {
        let gap = TimeInterval(seconds)
        snapshot.boutStartedAt = snapshot.boutStartedAt.addingTimeInterval(gap)
        snapshot.nextFullDueAt = snapshot.nextFullDueAt?.addingTimeInterval(gap)
        snapshot.nextMicroDueAt = snapshot.nextMicroDueAt?.addingTimeInterval(gap)
        snapshot.microAnchorAt = snapshot.microAnchorAt?.addingTimeInterval(gap)
        snapshot.dueAtAway = snapshot.dueAtAway?.addingTimeInterval(gap)
        rollDayCountersIfStale(now: now)

        let reason = "relaunched after \(seconds) s — countdown moved on"
        if case .away(let since) = snapshot.state {
            // The absence moves with everything else, so it measures only the stretch movez was
            // awake to see. `since + gap` can never overtake `now`: the user was already away
            // when the app went down.
            transition(to: .away(since: since.addingTimeInterval(gap)), reason: reason, at: now)
        } else {
            transition(to: snapshot.state, reason: reason, at: now)
        }
        return [.persist, .menuRefresh]
    }

    /// Midnight, crossed while the app was running or while it was gone.
    ///
    /// The counters, the routine seed and the streak all key off `dayKey`, so a stale one is
    /// rolled forward before anything reads it — otherwise Monday opens with Friday's numbers and
    /// Friday's routines. The sitting bout is deliberately not rolled with them: a body fifteen
    /// minutes from a break at 23:45 is fifteen minutes from a break at 00:01, and handing it a
    /// fresh fifty-five minutes there is the one thing a break reminder must never do. Nor is the
    /// state touched — a break on screen, a call in progress, a pause and an absence all outlast
    /// midnight the same way they outlast a closed lid.
    mutating func rollDayIfStale(now: Date) -> [SchedulerEffect] {
        guard rollDayCountersIfStale(now: now) else { return [] }
        // A self-transition: nothing moves, but the log is the only place this is visible.
        transition(to: snapshot.state, reason: "midnight — a new day's counters", at: now)
        return [.persist, .menuRefresh]
    }

    func shouldResetDay(gapSeconds: Int, now: Date) -> Bool {
        if gapSeconds >= config.dayResetGapSeconds { return true }
        let since = now.addingTimeInterval(-Double(gapSeconds))
        guard let start = config.workingHours.nextStart(after: since, calendar: config.calendar),
              start <= now else { return false }
        // A window that runs to midnight and opens again at midnight never closed: what the gap
        // crossed is a day boundary, not the start of a working day. Someone who works 00:00–24:00
        // and steps away at 23:55 comes back to the countdown they left.
        return !config.workingHours.isWithin(start.addingTimeInterval(-1), calendar: config.calendar)
    }

    /// Everything scoped to one calendar day, and nothing else. The sitting bout is not one of
    /// those things — see `rollDayIfStale`.
    private mutating func rollDayCounters(now: Date) {
        snapshot.doneToday = 0
        snapshot.snoozedToday = 0
        snapshot.skipsToday = 0
        snapshot.longestBoutSeconds = 0
        snapshot.microEmphasisIndex = 0
        snapshot.postLunchPending = false
        snapshot.dayKey = DayKey.key(for: now, calendar: config.calendar)
    }

    /// Rolls the day-scoped counters when the calendar day has moved on. True when it did.
    @discardableResult
    mutating func rollDayCountersIfStale(now: Date) -> Bool {
        guard !snapshot.dayKey.isEmpty else { return false }
        guard DayKey.key(for: now, calendar: config.calendar) != snapshot.dayKey else { return false }
        rollDayCounters(now: now)
        return true
    }

    /// A new sitting session: the interval starts from now and nothing is owed from the last one.
    ///
    /// The three transients cleared here are kept across midnight on purpose — a break interrupted
    /// at 23:58 must still resume, a credit taken at 23:59:58 must still be reversible while its
    /// toast is up, and a break deferred by a call still in progress is still owed. They are only
    /// moot once the session they belong to has genuinely ended.
    mutating func startFreshSession(now: Date, reason: String) -> [SchedulerEffect] {
        snapshot.interruptedBreak = nil
        snapshot.creditRestore = nil
        snapshot.deferredFullDueAt = nil
        clearAwayMarkers()
        startFreshInterval(now: now)
        transition(to: .sitting, reason: reason, at: now)
        return [.persist, .menuRefresh]
    }

    /// A gap long enough that the session it interrupted is over: the counters start again, the
    /// interval starts again, the settings do not.
    mutating func resetDay(now: Date, reason: String) -> [SchedulerEffect] {
        // Unconditional: a four-hour gap at noon is still a reset, even though the day has not
        // turned over.
        rollDayCounters(now: now)
        return startFreshSession(now: now, reason: reason)
    }
}
