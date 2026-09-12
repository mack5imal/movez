import Foundation

/// Sleep, lock and wake (research §4.3).
///
/// Nothing fires for a minute after the machine comes back — waking up to a break overlay is the
/// single most complained-about behaviour in this category of app. After that quiet minute the
/// gap is treated exactly like an idle stretch of the same length.
extension Scheduler {
    mutating func handleSleepOrLock(now: Date, reason: String) -> [SchedulerEffect] {
        if case .fullBreak(let startedAt) = snapshot.state {
            snapshot.interruptedBreak = InterruptedBreak(
                startedAt: startedAt,
                plannedEnd: startedAt.addingTimeInterval(TimeInterval(config.breakSeconds)),
                elapsedSeconds: max(0, Int(now.timeIntervalSince(startedAt))),
                completedBlocks: 0,
                totalBlocks: 0
            )
        }
        guard snapshot.state != .away(since: now) else { return [] }

        // Sleep takes every surface down, not just the one that happened to be showing: waking
        // to a stale overlay is the loudest failure this whole category of app has.
        var effects = dismissSurfaces()
        for dismissal in [SchedulerEffect.hideHeadsUp, .hideMicro] where !effects.contains(dismissal) {
            effects.append(dismissal)
        }
        snapshot.dueAtAway = snapshot.nextFullDueAt
        snapshot.remainingAtAwaySeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(now))) }
        transition(to: .away(since: now), reason: reason, at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    mutating func handleWake(gapSeconds: Int, now: Date, reason: String) -> [SchedulerEffect] {
        let until = now.addingTimeInterval(TimeInterval(config.wakeQuietSeconds))
        transition(to: .postBreakGrace(until: until, resumeTo: .applyGap(seconds: gapSeconds)), reason: reason, at: now)
        return [.persist, .menuRefresh]
    }

    /// The quiet minute is over. Decide what the gap meant.
    mutating func applyGrace(_ resume: GraceResume, now: Date) -> [SchedulerEffect] {
        switch resume {
        case .applyGap(let seconds):
            return applyGap(seconds: seconds, now: now)
        case .afterSuppression:
            return resumeAfterSuppression(now: now)
        case .pendingFull:
            return enterPendingFull(now: now)
        case .sitting:
            transition(to: .sitting, reason: "grace ended", at: now)
            return [.persist, .menuRefresh]
        }
    }

    private mutating func applyGap(seconds: Int, now: Date) -> [SchedulerEffect] {
        if shouldResetDay(gapSeconds: seconds, now: now) {
            return resetDay(now: now, reason: "gap of \(seconds / 3600) h — new day")
        }

        // A break that was on screen when the lid closed is the credit for that absence; the
        // idle table must not credit the same minutes a second time.
        if snapshot.interruptedBreak != nil {
            transition(to: .sitting, reason: "back after \(seconds) s", at: now)
            snapshot.nextFullDueAt = snapshot.dueAtAway ?? snapshot.nextFullDueAt
            return [.persist, .menuRefresh] + resumeInterruptedBreak(now: now)
        }

        let since = now.addingTimeInterval(-Double(seconds))
        return returnFromAway(since: since, now: now)
    }

    /// A break cut short by a closed lid picks up where it left off if the machine came back
    /// before the break was due to end; otherwise it is judged by the completion rule.
    private mutating func resumeInterruptedBreak(now: Date) -> [SchedulerEffect] {
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

    func shouldResetDay(gapSeconds: Int, now: Date) -> Bool {
        if gapSeconds >= config.dayResetGapSeconds { return true }
        let since = now.addingTimeInterval(-Double(gapSeconds))
        guard let start = config.workingHours.nextStart(after: since, calendar: config.calendar) else { return false }
        return start <= now
    }

    /// A new day: the counters start again, the interval starts again, the settings do not.
    mutating func resetDay(now: Date, reason: String) -> [SchedulerEffect] {
        snapshot.doneToday = 0
        snapshot.snoozedToday = 0
        snapshot.skipsToday = 0
        snapshot.longestBoutSeconds = 0
        snapshot.microEmphasisIndex = 0
        snapshot.postLunchPending = false
        snapshot.interruptedBreak = nil
        snapshot.creditRestore = nil
        snapshot.deferredFullDueAt = nil
        snapshot.dayKey = DayKey.key(for: now, calendar: config.calendar)
        startFreshInterval(now: now)
        transition(to: .sitting, reason: reason, at: now)
        return [.persist, .menuRefresh]
    }
}
