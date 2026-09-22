import Foundation

/// Turning scheduler effects into app state: attaching routines, recording history, and shaping
/// what the menu bar shows.
extension AppCoordinator {
    func apply(_ effect: SchedulerEffect) {
        if applySurface(effect) { return }
        applySideEffect(effect)
    }

    /// The effects that put a break surface on screen or take it away.
    private func applySurface(_ effect: SchedulerEffect) -> Bool {
        switch effect {
        case .showHeadsUp(let info):
            headsUpInfo = info
        case .hideHeadsUp:
            headsUpInfo = nil
        case .startFullBreak(let plan):
            beginBreak(plan)
        case .endFullBreak(let outcome):
            finishBreak(outcome)
        case .showMicroCountIn:
            beginMicro()
        case .hideMicro:
            endMicro()
        default:
            return false
        }
        return true
    }

    /// Toasts, persistence and polling.
    private func applySideEffect(_ effect: SchedulerEffect) {
        switch effect {
        case .showToast(let info):
            recordCredit(info)
            toastInfo = info
        case .hideToast:
            reverseCreditRecord()
            toastInfo = nil
        case .recordHeadsUpOutcome(let outcome):
            recordHeadsUpOutcome(outcome)
        case .recordMicroDone:
            recordMicro()
        case .persist:
            persistSnapshot()
        case .pollingChanged(let enabled):
            aggregator?.setPolling(enabled)
        default:
            break
        }
    }

    /// Writes the snapshot, stamped with the moment it was written.
    ///
    /// The stamp is applied here rather than inside the scheduler so that `Scheduler` stays a pure
    /// function of (snapshot, event, now) and no in-memory snapshot ever carries one.
    func persistSnapshot() {
        var snapshot = scheduler.snapshot
        snapshot.savedAt = clock.now
        lastPersistAt = clock.now
        try? snapshotStore?.save(snapshot)
    }

    // MARK: - Breaks

    private func beginBreak(_ plan: BreakPlan) {
        // A break the lid closed on picks up where it left off, with the movements it had, and
        // without counting twice against the day's rotation.
        if let resumed = interruptedSession {
            interruptedSession = nil
            currentBreak = BreakSession(
                routine: resumed.routine,
                startedAt: plan.startedAt,
                blockIndex: resumed.blockIndex,
                completedBlocks: resumed.completedBlocks,
                deferred: plan.deferred
            )
            return
        }

        let routine = nextRoutine(at: plan.startedAt)
        rememberRoutine(routine, at: plan.startedAt)
        cachedPreview = nil
        currentBreak = BreakSession(routine: routine, startedAt: plan.startedAt, deferred: plan.deferred)
    }

    private func finishBreak(_ outcome: BreakOutcome) {
        defer { currentBreak = nil }
        guard let current = currentBreak else { return }

        switch outcome {
        case .completed(let completed, let total, _):
            history.record(
                breakRecord: BreakRecord(
                    at: clock.now,
                    routineName: current.routine.name,
                    outcome: .done,
                    completedBlocks: completed,
                    totalBlocks: total
                ),
                longestBoutSeconds: scheduler.snapshot.longestBoutSeconds
            )
        case .skipped(let completed):
            // The scheduler does not track blocks, so the coordinator supplies the real count.
            history.record(breakRecord: BreakRecord(
                at: clock.now,
                routineName: current.routine.name,
                outcome: .skipped,
                completedBlocks: max(completed, current.completedBlocks),
                totalBlocks: current.totalBlocks
            ))
        case .snoozed:
            history.record(breakRecord: BreakRecord(
                at: clock.now,
                routineName: current.routine.name,
                outcome: .snoozed,
                completedBlocks: current.completedBlocks,
                totalBlocks: current.totalBlocks
            ))
        case .interrupted:
            // Sleep or a locked screen: nothing is recorded until the machine comes back and the
            // scheduler decides what the interruption meant. The session is kept so the break
            // that resumes is this one.
            interruptedSession = current
        }
    }

    /// Writes down a break that was turned away at the heads-up, which never became a session.
    ///
    /// The routine named is the one that was about to run, so the record reads the same as one
    /// written for a break the user actually saw. Nothing was done, so no blocks are claimed.
    private func recordHeadsUpOutcome(_ outcome: HeadsUpOutcome) {
        let routine = previewNextRoutine(now: clock.now)
        history.record(breakRecord: BreakRecord(
            at: clock.now,
            routineName: routine?.name ?? "",
            outcome: outcome == .snoozed ? .snoozed : .skipped,
            completedBlocks: 0,
            totalBlocks: routine?.blocks.count ?? 0
        ))
    }

    /// Writes the block the user just finished to history.
    func recordBlockCompletion(_ block: RoutineBlock, routineId: UUID) {
        history.record(completion: MovementCompletion(
            movementId: block.movement.id,
            at: clock.now,
            seconds: block.seconds,
            routineId: routineId
        ))
    }

    // MARK: - Micro-breaks

    private func beginMicro() {
        var context = MicroContext()
        context.emphasisIndex = scheduler.snapshot.microEmphasisIndex
        context.lastMicroMovementIds = lastMicroIds
        context.nextFullRoutineIds = Set(previewNextRoutine(now: clock.now)?.movementIds ?? [])
        context.excluded = settings.excludedMovementIds
        context.equipment = settings.equipment
        context.recency = history.recencyScores(before: clock.now)
        context.seed = SplitMix64.seed(day: scheduler.snapshot.dayKey, index: 1_000 + scheduler.snapshot.microEmphasisIndex)
        currentMicro = microBuilder.build(context: context)
    }

    private func endMicro() {
        if let micro = currentMicro { lastMicroIds = Set(micro.movementIds) }
        currentMicro = nil
    }

    /// Writes the micro-break's movements, on the scheduler's word that it ran (§4.11's half rule).
    ///
    /// Separate from `endMicro` because the panel comes down for a snooze, a skip, a closed lid and
    /// an idle stretch as well as for a minute of movement, and only the scheduler knows which of
    /// those just happened. `.recordMicroDone` arrives ahead of `.hideMicro`, so `currentMicro` is
    /// still here to be read.
    private func recordMicro() {
        guard let micro = currentMicro else { return }
        for block in micro.blocks {
            history.record(completion: MovementCompletion(
                movementId: block.movement.id,
                at: clock.now,
                seconds: block.seconds,
                routineId: nil
            ))
        }
    }

    // MARK: - Credited absences

    private func recordCredit(_ info: ToastInfo) {
        guard info.kind == .creditedFullBreak else { return }
        history.record(
            breakRecord: BreakRecord(
                at: clock.now,
                routineName: "Away \(info.awaySeconds / 60) min",
                outcome: .credited,
                completedBlocks: 0,
                totalBlocks: 0
            ),
            longestBoutSeconds: scheduler.snapshot.longestBoutSeconds
        )
    }

    /// "I was sitting" takes the credited break back out of the record as well as out of the
    /// scheduler.
    private func reverseCreditRecord() {
        guard toastInfo?.kind == .creditedFullBreak else { return }
        history.removeLastBreakRecord(matching: .credited)
    }

    // MARK: - Routine selection

    /// The routine this break will run. Deterministic in the day and the break index, and cached
    /// against everything it reads, so what the menu advertises is what the overlay serves.
    func nextRoutine(at now: Date) -> Routine {
        let index = breakIndexToday(at: now)
        let key = previewKey(index: index)
        if let cached = cachedPreview, cached.key == key { return cached.routine }

        let routine = builder.build(context: routineContext(at: now, breakIndex: index))
        cachedPreview = (key, routine)
        return routine
    }

    func previewNextRoutine(now: Date) -> Routine? {
        currentBreak?.routine ?? nextRoutine(at: now)
    }

    /// Everything the built routine depends on. When any of it moves, the preview is rebuilt.
    private func previewKey(index: Int) -> String {
        [
            scheduler.snapshot.dayKey,
            String(index),
            String(history.data.completions.count),
            String(settings.schedulerConfig.stableHash),
            String(settings.excludedMovementIds.count),
            settings.focus.rawValue,
            String(settings.difficultyCap),
            settings.equipment.map(\.rawValue).sorted().joined(separator: "+")
        ].joined(separator: "|")
    }

    func routineContext(at now: Date, breakIndex: Int) -> RoutineContext {
        rollDayIfNeeded(at: now)
        var context = RoutineContext()
        context.date = now
        context.timeOfDay = timeOfDay(at: now, breakIndex: breakIndex)
        context.breakIndexToday = breakIndex
        context.usedMovementIdsToday = history.usedMovementIds(on: now)
            .union(routinesToday.flatMap(\.movementIds))
        context.usedStrRegionsLastBreak = routinesToday.last?.strengthRegions ?? []
        context.balanceServedToday = routinesToday.contains { $0.buckets.contains(.bal) }
        context.equipment = settings.equipment
        context.excluded = settings.excludedMovementIds
        context.focus = settings.focus
        context.difficultyCap = settings.difficultyCap
        context.unlockedDiff3 = history.unlockedDiff3(library: library)
        // The rotation walks on from wherever it was, rather than restarting at hips every
        // morning: a day with two breaks in it used to serve the first two slots and nothing else,
        // for as long as the user kept that pattern up.
        context.rotationIndex = history.routinesDoneBefore(now) + breakIndex
        context.recency = history.recencyScores(before: now)
        context.seed = SplitMix64.seed(day: scheduler.snapshot.dayKey, index: breakIndex)
        return context
    }

    /// The last break before the working day closes, or an ordinary one.
    ///
    /// The window has to genuinely close for a break to be the last one. Working hours that run
    /// the whole day still report an end at midnight, and treating that as a close gave anyone
    /// working through the evening a wind-down routine every night at eleven.
    func timeOfDay(at now: Date, breakIndex: Int) -> TimeOfDay {
        let config = settings.schedulerConfig
        guard let end = config.workingHours.nextEnd(after: now, calendar: config.calendar),
              now.addingTimeInterval(TimeInterval(config.sitSeconds)) > end,
              !config.workingHours.isWithin(end.addingTimeInterval(1), calendar: config.calendar) else {
            return .normal
        }
        return .last
    }

    func breakIndexToday(at now: Date) -> Int {
        rollDayIfNeeded(at: now)
        return routinesToday.count
    }

    func rememberRoutine(_ routine: Routine, at now: Date) {
        rollDayIfNeeded(at: now)
        routinesToday.append(routine)
    }

    func rollDayIfNeeded(at now: Date) {
        let key = DayKey.key(for: now, calendar: settings.schedulerConfig.calendar)
        guard key != routinesDayKey else { return }
        routinesDayKey = key
        routinesToday.removeAll()
    }

    // MARK: - Menu state

    func makeMenuState(now: Date) -> MenuState {
        var state = MenuState()
        switch scheduler.state {
        case .paused(let until):
            state.mode = .paused
            state.pausedUntil = until
        case .away(let since):
            state.mode = .away
            state.awaySeconds = max(0, Int(now.timeIntervalSince(since)))
        case .postBreakGrace(_, .returnFromAbsence(let since, let returnedAt)):
            // The absence is over and is being judged; the number stops where it stopped rather
            // than climbing through the quiet minute.
            state.mode = .away
            state.awaySeconds = max(0, Int(returnedAt.timeIntervalSince(since)))
        case .offHours:
            state.mode = .offHours
        case .fullBreak, .headsUp, .microCountIn, .microRunning:
            state.mode = .breaking
        default:
            state.mode = .sitting
        }

        state.secondsUntilBreak = scheduler.snapshot.secondsUntilFullBreak(at: now)
        state.nextBreakAt = scheduler.snapshot.nextFullDueAt
        // The subtitle is read off the published preview rather than rebuilt: this runs on every
        // tick, and the menu is the only thing that wants it.
        state.nextRoutineSubtitle = nextRoutinePreview?.subtitle ?? ""
        return state
    }

    /// "1 h 12 m" / "32 m" — the phrasing the menu uses.
    nonisolated static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }
}
