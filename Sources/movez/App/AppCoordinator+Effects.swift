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
        case .persist:
            try? snapshotStore?.save(scheduler.snapshot)
        case .pollingChanged(let enabled):
            aggregator?.setPolling(enabled)
        default:
            break
        }
    }

    // MARK: - Breaks

    private func beginBreak(_ plan: BreakPlan) {
        let routine = nextRoutine(at: plan.startedAt)
        rememberRoutine(routine, at: plan.startedAt)
        cachedPreview = nil
        currentBreak = BreakSession(routine: routine, startedAt: plan.startedAt, deferred: plan.deferred)
        scheduler.snapshot.postLunchPending = false
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
            // scheduler decides what the interruption meant.
            break
        }
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
        context.isPostLunch = scheduler.snapshot.postLunchPending
        context.excluded = settings.excludedMovementIds
        context.equipment = settings.equipment
        context.seed = SplitMix64.seed(day: scheduler.snapshot.dayKey, index: 1_000 + scheduler.snapshot.microEmphasisIndex)
        currentMicro = microBuilder.build(context: context)
    }

    private func endMicro() {
        if let micro = currentMicro {
            lastMicroIds = Set(micro.movementIds)
            for block in micro.blocks {
                history.record(completion: MovementCompletion(
                    movementId: block.movement.id,
                    at: clock.now,
                    seconds: block.seconds,
                    routineId: nil
                ))
            }
        }
        currentMicro = nil
        scheduler.snapshot.postLunchPending = false
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
            settings.equipment.map(\.rawValue).sorted().joined(separator: "+"),
            scheduler.snapshot.postLunchPending ? "lunch" : "-"
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
        context.rotationIndex = breakIndex
        context.seed = SplitMix64.seed(day: scheduler.snapshot.dayKey, index: breakIndex)
        return context
    }

    /// First break of the day, last one before the working day closes, the one after lunch, or an
    /// ordinary one.
    func timeOfDay(at now: Date, breakIndex: Int) -> TimeOfDay {
        if breakIndex == 0 { return .first }
        if scheduler.snapshot.postLunchPending { return .postLunch }
        let config = settings.schedulerConfig
        if let end = config.workingHours.nextEnd(after: now, calendar: config.calendar),
           now.addingTimeInterval(TimeInterval(config.sitSeconds)) > end {
            return .last
        }
        return .normal
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
        case .offHours:
            state.mode = .offHours
        case .fullBreak, .headsUp, .microCountIn, .microRunning:
            state.mode = .breaking
        default:
            state.mode = .sitting
        }

        state.secondsUntilBreak = scheduler.snapshot.secondsUntilFullBreak(at: now)
        state.nextBreakAt = scheduler.snapshot.nextFullDueAt
        state.nextRoutineSubtitle = nextRoutinePreview?.subtitle ?? ""
        let stats = history.stats(on: now)
        state.statsLine = "Today · \(stats.summary)"
        state.longestBoutLine = "Longest sitting bout \(AppCoordinator.duration(stats.longestBoutSeconds))"
        state.streak = history.streak(on: now)
        return state
    }

    /// "1 h 12 m" / "32 m" — the phrasing the menu uses.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }
}
