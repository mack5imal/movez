import Foundation

/// The sitting → break loop as a pure state machine.
///
/// `handle` is total: every unhandled combination of state and event returns no effects and
/// changes nothing. There are no timers here — the coordinator sends `.tick` — and no calls to
/// `Date()`, which is what lets a whole working day be replayed in milliseconds.
struct Scheduler {
    var snapshot: SchedulerSnapshot
    private(set) var config: SchedulerConfig

    init(config: SchedulerConfig = SchedulerConfig(), now: Date) {
        self.config = config
        snapshot = SchedulerSnapshot(now: now, dayKey: DayKey.key(for: now, calendar: config.calendar))
        snapshot.configHash = config.stableHash
        startFreshInterval(now: now)
    }

    init(snapshot: SchedulerSnapshot, config: SchedulerConfig = SchedulerConfig()) {
        self.snapshot = snapshot
        self.config = config
    }

    var state: SchedulerState { snapshot.state }

    /// The signal monitors idle their polling loop entirely while the scheduler cannot act on
    /// what they would report.
    var pollingRequired: Bool {
        switch snapshot.state {
        case .paused, .offHours: return false
        default: return true
        }
    }

    /// Snoozes left for the break currently being negotiated.
    var snoozesLeft: Int {
        max(0, (snapshot.snoozeAllowanceThisBreak ?? config.maxSnoozesPerBreak) - snapshot.snoozesUsedThisBreak)
    }

    // MARK: - Event dispatch

    mutating func handle(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect] {
        if let effects = handleClockEvents(event, now: now) { return effects }
        if let effects = handleBreakActions(event, now: now) { return effects }
        if let effects = handleMicroActions(event, now: now) { return effects }
        if let effects = handleSignalEvents(event, now: now) { return effects }
        if let effects = handleSessionEvents(event, now: now) { return effects }
        return []
    }

    private mutating func handleSignalEvents(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect]? {
        switch event {
        case .idle(let seconds): return handleIdle(seconds: seconds, now: now)
        case .sleep: return handleSleepOrLock(now: now, reason: "machine slept")
        case .lock: return handleSleepOrLock(now: now, reason: "screen locked")
        case .wake(let gap): return handleWake(gapSeconds: gap, now: now, reason: "woke after \(gap) s")
        case .unlock(let gap): return handleWake(gapSeconds: gap, now: now, reason: "unlocked after \(gap) s")
        case .gapDetected(let gap): return handleWake(gapSeconds: gap, now: now, reason: "tick gap of \(gap) s")
        case .signals(let signals): return handleSignals(signals, now: now)
        case .toastReverse: return reverseCredit(now: now)
        default: return nil
        }
    }

    private mutating func handleSessionEvents(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect]? {
        switch event {
        case .userPause(let seconds): return pause(seconds: seconds, focusInitiated: false, now: now)
        case .userResume: return resumeFromPause(now: now, focusInitiated: false, reason: "resumed by hand")
        case .userExtendPause(let seconds): return extendPause(seconds: seconds, now: now)
        case .focusFilter(let paused):
            return paused
                ? pause(seconds: nil, focusInitiated: true, now: now)
                : resumeFromPause(now: now, focusInitiated: true, reason: "focus filter cleared")
        case .userStartSession: return beginAdHocSession(now: now)
        case .userEndSession: return endAdHocSession(now: now)
        default: return nil
        }
    }

    private mutating func handleClockEvents(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect]? {
        switch event {
        case .tick: return tick(now: now)
        case .input(let age): return handleInput(lastEventAgeSeconds: age, now: now)
        case .settingsChanged(let updated): return apply(updated, now: now)
        default: return nil
        }
    }

    private mutating func handleBreakActions(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect]? {
        switch event {
        case .userTakeBreakNow: return takeBreakNow(now: now)
        case .userMakeDueIn(let seconds): return makeDue(in: seconds, now: now)
        case .userStartNow: return startBreakNow(now: now)
        case .userSnooze: return snooze(now: now)
        case .userSkip: return skip(now: now)
        case .userNextBlock: return nextBlock()
        case .userDone(let completed, let total, let elapsed):
            return finishBreak(completed: completed, total: total, elapsed: elapsed, now: now, userInitiated: true)
        case .breakEnded(let completed, let total, let elapsed):
            return finishBreak(completed: completed, total: total, elapsed: elapsed, now: now, userInitiated: false)
        default: return nil
        }
    }

    private mutating func handleMicroActions(_ event: SchedulerEvent, now: Date) -> [SchedulerEffect]? {
        switch event {
        case .userMicroStartNow: return startMicroNow(now: now)
        case .userMicroSnooze: return snoozeMicro(now: now)
        case .userMicroSkip: return skipMicro(now: now)
        case .microEnded: return endMicro(now: now)
        default: return nil
        }
    }

    // MARK: - Tick

    private mutating func tick(now: Date) -> [SchedulerEffect] {
        // Working hours first: opening a new working day already rolls the counters, and an
        // ad-hoc session that ran past midnight has to end before anything else is decided.
        let hours = applyWorkingHours(now: now)
        if !hours.isEmpty { return hours }

        // Then the day itself, for the session that simply ran through midnight — or was
        // restored from a launch on an earlier day — without either boundary firing.
        let rolled = rollDayIfStale(now: now)
        if !rolled.isEmpty { return rolled }
        if let effects = tickBreakStates(now: now) { return effects }
        if let effects = tickMicroStates(now: now) { return effects }
        if let effects = tickInterruptedStates(now: now) { return effects }
        return []
    }

    private mutating func tickInterruptedStates(now: Date) -> [SchedulerEffect]? {
        switch snapshot.state {
        case .paused(let until):
            return tickPaused(until: until, now: now)
        case .suppressed(let since, let deferred):
            return tickSuppressed(since: since, deferredFullDue: deferred, now: now)
        case .postBreakGrace(let until, let resume):
            guard now >= until else { return [] }
            return applyGrace(resume, now: now)
        case .away, .offHours:
            return []
        default:
            return nil
        }
    }

    private mutating func tickBreakStates(now: Date) -> [SchedulerEffect]? {
        switch snapshot.state {
        case .sitting:
            return tickSitting(now: now)
        case .pendingFull(let since):
            guard now.timeIntervalSince(since) >= Double(config.inputWaitCapSeconds) else { return [] }
            return enterHeadsUp(now: now, reason: "input wait capped")
        case .headsUp(let startedAt, let deferredSince):
            guard now.timeIntervalSince(startedAt) >= Double(config.headsUpSeconds) else { return [] }
            return enterFullBreak(now: now, deferred: deferredSince != nil, reason: "heads-up elapsed")
        case .snoozed(let until):
            guard now >= until else { return [] }
            return enterHeadsUp(now: now, reason: "snooze elapsed")
        default:
            return nil
        }
    }

    private mutating func tickMicroStates(now: Date) -> [SchedulerEffect]? {
        switch snapshot.state {
        case .microCountIn(let startedAt):
            guard now.timeIntervalSince(startedAt) >= Double(config.microCountInSeconds) else { return [] }
            return enterMicroRunning(now: now)
        case .microRunning(let startedAt):
            guard now.timeIntervalSince(startedAt) >= Double(config.microSeconds) else { return [] }
            return endMicro(now: now)
        default:
            return nil
        }
    }

    private mutating func tickSitting(now: Date) -> [SchedulerEffect] {
        if let due = snapshot.nextFullDueAt, now >= due {
            return enterPendingFull(now: now)
        }
        guard config.microEnabled, let micro = snapshot.nextMicroDueAt, now >= micro else { return [] }
        if let full = snapshot.nextFullDueAt,
           full.timeIntervalSince(now) < Double(config.microMinGapBeforeFullSeconds) {
            // Too close to the full break to be worth interrupting for.
            snapshot.nextMicroDueAt = nil
            return [.persist]
        }
        return enterMicroCountIn(now: now)
    }

    private mutating func handleInput(lastEventAgeSeconds age: Int, now: Date) -> [SchedulerEffect] {
        if case .away(let since) = snapshot.state { return returnFromAway(since: since, now: now) }
        guard case .pendingFull = snapshot.state, age >= config.inputPauseSeconds else { return [] }
        return enterHeadsUp(now: now, reason: "input paused for \(age) s")
    }

    // MARK: - Interval bookkeeping

    /// Starts a new sitting bout: the countdown, the micro anchor and the per-break allowances
    /// all reset together.
    ///
    /// Defer, never reset. Exactly four things move `boutStartedAt`, and they are all here: a
    /// completed or credited break, a gap long enough to have ended the session (four hours, or
    /// one spanning a working-day opening), the working day or an ad-hoc session opening, and the
    /// launch shift that moves the whole bout forward by time movez was not running. Midnight is
    /// deliberately not one of them — it rolls the day's counters and leaves the bout alone.
    mutating func startFreshInterval(now: Date) {
        snapshot.boutStartedAt = now
        snapshot.nextFullDueAt = now.addingTimeInterval(TimeInterval(config.sitSeconds))
        snapshot.microAnchorAt = nil
        snapshot.microSnoozeUsed = false
        snapshot.snoozesUsedThisBreak = 0
        snapshot.snoozeAllowanceThisBreak = nil
        snapshot.pendingInputWaitStartedAt = nil
        snapshot.nextMicroDueAt = microDue(anchoredAt: now)
    }

    /// The next micro-break time for an anchor, or nil when it would land inside the ten-minute
    /// quiet zone before the full break — or when micro-breaks are off.
    func microDue(anchoredAt anchor: Date) -> Date? {
        guard config.microEnabled else { return nil }
        let candidate = anchor.addingTimeInterval(TimeInterval(config.microEverySeconds))
        guard let full = snapshot.nextFullDueAt else { return candidate }
        guard full.timeIntervalSince(candidate) >= Double(config.microMinGapBeforeFullSeconds) else { return nil }
        return candidate
    }

    mutating func recordBout(endingAt end: Date) {
        let seconds = Int(end.timeIntervalSince(snapshot.boutStartedAt))
        snapshot.longestBoutSeconds = max(snapshot.longestBoutSeconds, max(0, seconds))
    }

    mutating func transition(to newState: SchedulerState, reason: String, at now: Date) {
        let from = snapshot.state
        snapshot.state = newState
        snapshot.transitions.append(Transition(at: now, from: from, to: newState, reason: reason))
    }

    // MARK: - Settings

    /// Settings apply live. The due times are re-planned from the bout that is already running,
    /// so changing the preset never costs the user the time they have already sat.
    mutating func apply(_ updated: SchedulerConfig, now: Date) -> [SchedulerEffect] {
        let wasPolling = pollingRequired
        config = updated
        snapshot.configHash = updated.stableHash

        if snapshot.state.countdownRuns {
            snapshot.nextFullDueAt = snapshot.boutStartedAt.addingTimeInterval(TimeInterval(updated.sitSeconds))
            snapshot.nextMicroDueAt = microDue(anchoredAt: snapshot.microAnchorAt ?? snapshot.boutStartedAt)
        }

        var effects: [SchedulerEffect] = [.persist, .menuRefresh]
        if wasPolling != pollingRequired { effects.append(.pollingChanged(pollingRequired)) }
        return effects
    }

    /// Research §4.11: a break counts as done at half the movements or half the time.
    static func meetsCompletionRule(
        completed: Int,
        total: Int,
        elapsed: Int,
        config: SchedulerConfig
    ) -> Bool {
        let required = Int((Double(total) * config.completionFraction).rounded(.up))
        return completed >= max(1, required) || elapsed >= config.completionSeconds
    }
}
