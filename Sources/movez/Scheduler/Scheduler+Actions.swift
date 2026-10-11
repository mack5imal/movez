import Foundation

/// The state entries and the user actions. Kept apart from the tick loop so both stay readable.
extension Scheduler {
    // MARK: - State entries

    mutating func enterPendingFull(now: Date) -> [SchedulerEffect] {
        snapshot.pendingInputWaitStartedAt = now
        transition(to: .pendingFull(since: now), reason: "full break due", at: now)
        return [.persist, .menuRefresh]
    }

    mutating func enterHeadsUp(now: Date, deferredSince: Date? = nil, reason: String) -> [SchedulerEffect] {
        snapshot.pendingInputWaitStartedAt = nil
        let deferral = deferredSince ?? snapshot.deferredFullDueAt
        if let deferral, now.timeIntervalSince(deferral) > Double(config.deferredBadgeSeconds) {
            // A break that has been waiting for half an hour has earned less patience.
            snapshot.snoozeAllowanceThisBreak = config.deferredSnoozeAllowance
        }
        transition(to: .headsUp(startedAt: now, deferredSince: deferral), reason: reason, at: now)
        let info = headsUpInfo(now: now, deferredSince: deferral)
        return [.showHeadsUp(info), .chime(.headsUp), .persist, .menuRefresh]
    }

    mutating func enterFullBreak(now: Date, deferred: Bool, reason: String) -> [SchedulerEffect] {
        snapshot.deferredFullDueAt = nil
        snapshot.deferredReason = nil
        snapshot.interruptedBreak = nil
        clearAwayMarkers()
        transition(to: .fullBreak(startedAt: now), reason: reason, at: now)
        let plan = BreakPlan(startedAt: now, seconds: config.breakSeconds, deferred: deferred)
        return [.hideHeadsUp, .startFullBreak(plan), .persist, .menuRefresh]
    }

    func headsUpInfo(now: Date, deferredSince: Date?) -> HeadsUpInfo {
        let sittingSince = snapshot.lastCompletedBreakAt ?? snapshot.boutStartedAt
        let deferredFor = deferredSince.map { max(0, Int(now.timeIntervalSince($0))) }
        let longWait = (deferredFor ?? 0) > config.deferredBadgeSeconds
        return HeadsUpInfo(
            dueAt: snapshot.nextFullDueAt ?? now,
            startsAt: now.addingTimeInterval(TimeInterval(config.headsUpSeconds)),
            sittingSince: sittingSince,
            sittingSeconds: max(0, Int(now.timeIntervalSince(sittingSince))),
            snoozesLeft: snoozesLeft,
            maxSnoozes: snapshot.snoozeAllowanceThisBreak ?? config.maxSnoozesPerBreak,
            skipsToday: snapshot.skipsToday,
            deferred: deferredSince != nil,
            deferredSince: deferredSince,
            deferredForSeconds: deferredFor,
            deferredReason: snapshot.deferredReason,
            showDeferredBadge: longWait
        )
    }

    // MARK: - Break actions

    mutating func takeBreakNow(now: Date) -> [SchedulerEffect] {
        var prelude: [SchedulerEffect] = []
        switch snapshot.state {
        case .sitting, .pendingFull, .headsUp, .snoozed, .away, .suppressed, .postBreakGrace:
            break
        case .paused:
            // Taking a break by hand ends the pause rather than sitting behind it.
            prelude = endPauseBookkeeping(now: now)
        case .offHours:
            prelude = beginAdHocSession(now: now)
        default:
            return []
        }
        return prelude + enterFullBreak(now: now, deferred: false, reason: "take a break now")
    }

    mutating func startBreakNow(now: Date) -> [SchedulerEffect] {
        guard case .headsUp(_, let deferredSince) = snapshot.state else { return [] }
        return enterFullBreak(now: now, deferred: deferredSince != nil, reason: "start now")
    }

    mutating func makeDue(in seconds: Int, now: Date) -> [SchedulerEffect] {
        guard case .sitting = snapshot.state else { return [] }
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(seconds))
        if let micro = snapshot.nextMicroDueAt, let full = snapshot.nextFullDueAt,
           full.timeIntervalSince(micro) < Double(config.microMinGapBeforeFullSeconds) {
            snapshot.nextMicroDueAt = nil
        }
        return [.persist, .menuRefresh]
    }

    mutating func nextBlock() -> [SchedulerEffect] {
        guard case .fullBreak = snapshot.state else { return [] }
        return [.chime(.transition)]
    }

    /// A snooze is a deferral, never a skip: it costs one of the two allowances and comes back
    /// through the heads-up rather than straight to the overlay.
    ///
    /// A break left paused past its limit is snoozed `beyondAllowance`: it is coming back, not
    /// being skipped, and running out of snoozes does not change that.
    mutating func snooze(now: Date, beyondAllowance: Bool = false) -> [SchedulerEffect] {
        guard snoozesLeft > 0 || beyondAllowance else { return [] }
        var dismissal: [SchedulerEffect]
        switch snapshot.state {
        case .headsUp where !beyondAllowance: dismissal = [.hideHeadsUp, .recordHeadsUpOutcome(.snoozed)]
        case .fullBreak: dismissal = [.endFullBreak(.snoozed)]
        default: return []
        }

        snapshot.snoozesUsedThisBreak += 1
        snapshot.snoozedToday += 1
        let until = now.addingTimeInterval(TimeInterval(config.snoozeSeconds))
        transition(to: .snoozed(until: until), reason: "snoozed \(config.snoozeSeconds / 60) min", at: now)
        return dismissal + [.persist, .menuRefresh]
    }

    /// Skipping starts a fresh interval from now but leaves the sitting bout running — the body
    /// has still been in the chair the whole time.
    mutating func skip(now: Date) -> [SchedulerEffect] {
        var dismissal: [SchedulerEffect]
        switch snapshot.state {
        case .headsUp(let startedAt, _):
            guard now.timeIntervalSince(startedAt) >= Double(config.skipDelaySeconds) else { return [] }
            dismissal = [.hideHeadsUp, .recordHeadsUpOutcome(.skipped)]
        case .fullBreak(let startedAt):
            guard now.timeIntervalSince(startedAt) >= Double(config.skipDelaySeconds) else { return [] }
            dismissal = [.endFullBreak(.skipped(completedBlocks: 0))]
        default:
            return []
        }

        snapshot.skipsToday += 1
        rescheduleAfterSkip(now: now)
        transition(to: .sitting, reason: "skipped", at: now)
        return dismissal + [.persist, .menuRefresh]
    }

    mutating func finishBreak(
        completed: Int,
        total: Int,
        elapsed: Int,
        now: Date,
        userInitiated: Bool
    ) -> [SchedulerEffect] {
        guard case .fullBreak(let startedAt) = snapshot.state else { return [] }
        let counts = Scheduler.meetsCompletionRule(completed: completed, total: total, elapsed: elapsed, config: config)
        // "Done" is only offered once the break has actually been done; an early exit is a skip.
        if userInitiated, !counts { return [] }

        if counts {
            snapshot.doneToday += 1
            snapshot.lastCompletedBreakAt = now
            recordBout(endingAt: startedAt)
            startFreshInterval(now: now)
            transition(to: .sitting, reason: "break completed", at: now)
            let outcome = BreakOutcome.completed(completedBlocks: completed, totalBlocks: total, elapsed: elapsed)
            return [.chime(.completion), .endFullBreak(outcome), .persist, .menuRefresh]
        }

        snapshot.skipsToday += 1
        rescheduleAfterSkip(now: now)
        transition(to: .sitting, reason: "break ended below the completion threshold", at: now)
        return [.endFullBreak(.skipped(completedBlocks: completed)), .persist, .menuRefresh]
    }

    private mutating func rescheduleAfterSkip(now: Date) {
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(config.sitSeconds))
        snapshot.nextMicroDueAt = microDue(anchoredAt: now)
        snapshot.snoozesUsedThisBreak = 0
        snapshot.snoozeAllowanceThisBreak = nil
        snapshot.microAnchorAt = nil
        snapshot.microSnoozeUsed = false
        snapshot.pendingInputWaitStartedAt = nil
        snapshot.deferredFullDueAt = nil
    }

    // MARK: - Micro-break actions

    mutating func enterMicroCountIn(now: Date) -> [SchedulerEffect] {
        if snapshot.microAnchorAt == nil { snapshot.microAnchorAt = now }
        snapshot.nextMicroDueAt = nil
        transition(to: .microCountIn(startedAt: now), reason: "micro-break due", at: now)
        let info = MicroInfo(
            startsAt: now.addingTimeInterval(TimeInterval(config.microCountInSeconds)),
            countInSeconds: config.microCountInSeconds,
            seconds: config.microSeconds
        )
        return [.showMicroCountIn(info), .chime(.microCountIn), .persist, .menuRefresh]
    }

    mutating func enterMicroRunning(now: Date) -> [SchedulerEffect] {
        transition(to: .microRunning(startedAt: now), reason: "micro-break started", at: now)
        return [.showMicroRunning, .persist]
    }

    mutating func startMicroNow(now: Date) -> [SchedulerEffect] {
        guard case .microCountIn = snapshot.state else { return [] }
        return enterMicroRunning(now: now)
    }

    /// The micro-break ran its course. One that got as far as running ends on the completion chime
    /// a full break ends on; skips and snoozes go through their own paths and stay quiet.
    mutating func endMicro(now: Date) -> [SchedulerEffect] {
        let ranToTheEnd: Bool
        switch snapshot.state {
        case .microCountIn: ranToTheEnd = false
        case .microRunning: ranToTheEnd = true
        default: return []
        }
        let record = microRecord(now: now)
        closeMicroCycle(now: now, reason: "micro-break finished")
        let chime: [SchedulerEffect] = ranToTheEnd ? [.chime(.completion)] : []
        return record + chime + [.hideMicro, .persist, .menuRefresh]
    }

    /// How long the movement itself has been on screen. A count-in is not the micro-break: nothing
    /// has been asked of the user yet.
    func microRanSeconds(now: Date) -> Int {
        guard case .microRunning(let startedAt) = snapshot.state else { return 0 }
        return max(0, Int(now.timeIntervalSince(startedAt)))
    }

    /// A micro-break is written to history at half its length, the rule the full break already uses
    /// (research §4.11).
    ///
    /// It has to be a rule rather than "the panel went away", because the panel goes away for a
    /// snooze, a skip, a closed lid and an idle stretch alike. Recording all four wrote movements
    /// nobody did into history, where they then weighed themselves down for three days (23e).
    func microRecord(now: Date) -> [SchedulerEffect] {
        let ran = microRanSeconds(now: now)
        guard ran * 2 >= config.microSeconds else { return [] }
        return [.recordMicroDone(seconds: ran)]
    }

    /// One snooze puts the micro-break back in five minutes; a second is a skip.
    mutating func snoozeMicro(now: Date) -> [SchedulerEffect] {
        switch snapshot.state {
        case .microCountIn, .microRunning: break
        default: return []
        }
        guard !snapshot.microSnoozeUsed else { return skipMicro(now: now) }

        let record = microRecord(now: now)
        snapshot.microSnoozeUsed = true
        snapshot.nextMicroDueAt = now.addingTimeInterval(TimeInterval(config.snoozeSeconds))
        transition(to: .sitting, reason: "micro-break snoozed", at: now)
        return record + [.hideMicro, .persist, .menuRefresh]
    }

    mutating func skipMicro(now: Date) -> [SchedulerEffect] {
        switch snapshot.state {
        case .microCountIn, .microRunning: break
        default: return []
        }
        let record = microRecord(now: now)
        closeMicroCycle(now: now, reason: "micro-break skipped")
        return record + [.hideMicro, .persist, .menuRefresh]
    }

    /// Ends the micro cycle and re-anchors the next one to the cycle's original start, so a
    /// snooze never pushes the whole cadence later.
    private mutating func closeMicroCycle(now: Date, reason: String) {
        let anchor = snapshot.microAnchorAt ?? now
        snapshot.microAnchorAt = nil
        snapshot.microSnoozeUsed = false
        snapshot.microEmphasisIndex += 1
        snapshot.nextMicroDueAt = microDue(anchoredAt: anchor)
        transition(to: .sitting, reason: reason, at: now)
    }
}
