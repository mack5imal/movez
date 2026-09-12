import Foundation

/// Idle handling: three thresholds, one policy (research §4.2).
///
/// Under three minutes nothing happens. Three to five minutes is treated as a micro-break and the
/// countdown is handed back with the time that was left on it. Five minutes or more counts as a
/// full break. Both credits are reversible for six seconds, because the app cannot tell a walk to
/// the kitchen from a long read on paper.
extension Scheduler {
    /// The states an idle stretch can interrupt. A running full break is not one of them: the
    /// user standing still during a stretch is the point.
    static let idleInterruptible: [String] = ["sitting", "pending_full", "heads_up", "micro_count_in", "micro_running"]

    mutating func handleIdle(seconds: Int, now: Date) -> [SchedulerEffect] {
        guard seconds >= config.awayThresholdSeconds else { return [] }
        guard Self.idleInterruptible.contains(snapshot.state.name) else { return [] }

        let since = now.addingTimeInterval(-Double(seconds))
        var effects = dismissSurfaces()
        snapshot.dueAtAway = snapshot.nextFullDueAt
        snapshot.remainingAtAwaySeconds = snapshot.nextFullDueAt.map { max(0, Int($0.timeIntervalSince(since))) }
        transition(to: .away(since: since), reason: "idle for \(seconds / 60) min", at: now)
        effects += [.persist, .menuRefresh]
        return effects
    }

    /// The user is back at the keyboard.
    mutating func returnFromAway(since: Date, now: Date) -> [SchedulerEffect] {
        let absence = max(0, Int(now.timeIntervalSince(since)))
        notePostLunch(absence: absence, returnedAt: now)

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
        return [.showToast(toast), .persist, .menuRefresh]
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
        return [.showToast(toast), .persist, .menuRefresh]
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
            expiresAt: now.addingTimeInterval(TimeInterval(ToastInfo(
                kind: .creditedFullBreak,
                awaySeconds: 0,
                nextBreakAt: nil,
                reversal: .wasSittingAfterFullCredit
            ).secondsOnScreen))
        )
    }

    private mutating func clearAwayMarkers() {
        snapshot.remainingAtAwaySeconds = nil
        snapshot.dueAtAway = nil
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
    mutating func dismissSurfaces() -> [SchedulerEffect] {
        switch snapshot.state {
        case .headsUp, .pendingFull:
            return [.hideHeadsUp]
        case .fullBreak:
            return [.endFullBreak(.interrupted)]
        case .microCountIn, .microRunning:
            snapshot.nextMicroDueAt = microDue(anchoredAt: snapshot.microAnchorAt ?? Date())
            snapshot.microAnchorAt = nil
            snapshot.microSnoozeUsed = false
            return [.hideMicro]
        default:
            return []
        }
    }
}
