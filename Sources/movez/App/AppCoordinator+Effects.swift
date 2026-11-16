import Foundation

/// Turning scheduler effects into app state: attaching breaks, recording history, and shaping
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
            dismissHeadsUp()
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
        case .recordAbsence(let record):
            recordAbsence(record)
        case .showToast(let info):
            toastInfo = info
        case .hideToast:
            reverseAbsenceRecord()
            toastInfo = nil
        case .recordHeadsUpOutcome(let outcome):
            recordHeadsUpOutcome(outcome)
        case .recordMicroDone(let seconds):
            recordMicro(ranSeconds: seconds)
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
        // Stamped even when the write fails, so a broken disk is retried at the heartbeat's pace
        // rather than on every tick.
        lastPersistAt = clock.now
        do {
            try snapshotStore?.save(snapshot)
        } catch {
            MovezLog.store.error("state could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Breaks

    /// Fills in what only the coordinator knows before an effect reaches anything.
    ///
    /// A heads-up is the moment the next break is fixed: it is planned here, in the mode in use
    /// now, and the full break that follows serves it however the mode changes in between (S13).
    func attachingBreak(to effect: SchedulerEffect) -> SchedulerEffect {
        guard case .showHeadsUp(var info) = effect else { return effect }
        let planned = nextBreak(at: clock.now)
        headsUpBreak = (planned: planned, mode: settings.mode)
        info.breakKind = planned.kind
        info.breakMinutes = max(1, Int((Double(planned.plannedSeconds) / 60).rounded()))
        return .showHeadsUp(info)
    }

    /// The heads-up is gone. Into its full break, its planned break stays for `beginBreak`;
    /// otherwise it is put aside for the snooze or skip that follows in the same batch, and the
    /// next heads-up plans afresh.
    private func dismissHeadsUp() {
        headsUpInfo = nil
        if case .fullBreak = scheduler.state { return }
        dismissedHeadsUpBreak = headsUpBreak ?? dismissedHeadsUpBreak
        headsUpBreak = nil
    }

    private func beginBreak(_ plan: BreakPlan) {
        // A break the lid closed on picks up where it left off, with the movements it had, and
        // without being counted twice among the day's breaks. Only a start the scheduler marks
        // as a resume serves it: a fresh break also clears the scheduler's interruption, and
        // serving the kept session then would run a stale break instead of the announced one.
        let kept = interruptedSession
        interruptedSession = nil
        if plan.resumed, let resumed = kept {
            headsUpBreak = nil
            currentBreak = BreakSession(
                planned: resumed.planned,
                mode: resumed.mode,
                startedAt: plan.startedAt,
                blockIndex: resumed.blockIndex,
                completedBlocks: resumed.completedBlocks,
                deferred: plan.deferred
            )
            return
        }

        // A resume with nothing kept is a break the app was relaunched under: the session died
        // with the process. The break served instead is new, so it starts now; backdated, its
        // opening blocks read as already run and were recorded as done.
        let startedAt = plan.resumed ? clock.now : plan.startedAt
        let announced = headsUpBreak ?? (planned: nextBreak(at: startedAt), mode: settings.mode)
        headsUpBreak = nil
        rememberBreak(announced.planned, at: startedAt)
        cachedPreview = nil
        currentBreak = BreakSession(
            planned: announced.planned,
            mode: announced.mode,
            startedAt: startedAt,
            deferred: plan.deferred
        )
    }

    private func finishBreak(_ outcome: BreakOutcome) {
        defer { currentBreak = nil }
        // A break the lid closed on and the scheduler later settled has no session on screen:
        // the one it ends is the session kept when it was interrupted.
        let settling = currentBreak == nil && outcome != .interrupted
        guard let current = currentBreak ?? (settling ? interruptedSession : nil) else { return }
        if settling { interruptedSession = nil }
        let kind = current.planned.kind

        switch outcome {
        case .completed(let completed, let total, _):
            // The scheduler judges an interruption by time alone and reports no blocks, so the
            // session's own count is the one written down.
            history.record(
                breakRecord: BreakRecord(
                    at: clock.now,
                    routineName: BreakRecord.movementBreakName,
                    outcome: .done,
                    completedBlocks: max(completed, current.completedBlocks),
                    totalBlocks: total > 0 ? total : current.totalBlocks,
                    kind: kind
                ),
                longestBoutSeconds: scheduler.snapshot.longestBoutSeconds
            )
        case .skipped(let completed):
            // The scheduler does not track blocks, so the coordinator supplies the real count.
            history.record(breakRecord: BreakRecord(
                at: clock.now,
                routineName: BreakRecord.movementBreakName,
                outcome: .skipped,
                completedBlocks: max(completed, current.completedBlocks),
                totalBlocks: current.totalBlocks,
                kind: kind
            ))
            recordRunningBout()
        case .snoozed:
            history.record(breakRecord: BreakRecord(
                at: clock.now,
                routineName: BreakRecord.movementBreakName,
                outcome: .snoozed,
                completedBlocks: current.completedBlocks,
                totalBlocks: current.totalBlocks,
                kind: kind
            ))
            recordRunningBout()
        case .interrupted:
            // Sleep or a locked screen: nothing is recorded until the machine comes back and the
            // scheduler decides what the interruption meant. The session is kept so the break
            // that resumes is this one.
            interruptedSession = current
        }
    }

    /// How long the user has been sitting in the bout that is still going, or nil when no bout is
    /// running (a break on screen, away, paused or off hours).
    func runningBoutSeconds(at now: Date) -> Int? {
        switch scheduler.state {
        case .sitting, .suppressed, .pendingFull, .headsUp, .snoozed, .microCountIn, .microRunning:
            return max(0, Int(now.timeIntervalSince(scheduler.snapshot.boutStartedAt)))
        default:
            return nil
        }
    }

    /// A skip or a snooze leaves the bout running, and the scheduler measures a bout only when it
    /// ends, so the bout so far is written down here. Without it a day of skips recorded a longest
    /// bout of nothing (APP-5).
    private func recordRunningBout() {
        guard let running = runningBoutSeconds(at: clock.now) else { return }
        history.recordLongestBout(running, on: clock.now)
    }

    /// Writes down a break that was turned away at the heads-up, which never became a session.
    ///
    /// The block count and kind are the break the heads-up announced, so the record reads the same
    /// as one written for a break the user actually saw, and a snoozed or skipped strength break
    /// is one the planner knows did not happen. Nothing was done, so no blocks are claimed.
    private func recordHeadsUpOutcome(_ outcome: HeadsUpOutcome) {
        let planned = (headsUpBreak ?? dismissedHeadsUpBreak)?.planned ?? previewNextBreak(now: clock.now)
        headsUpBreak = nil
        dismissedHeadsUpBreak = nil
        history.record(breakRecord: BreakRecord(
            at: clock.now,
            routineName: BreakRecord.movementBreakName,
            outcome: outcome == .snoozed ? .snoozed : .skipped,
            completedBlocks: 0,
            totalBlocks: planned.parts.count,
            kind: planned.kind
        ))
        recordRunningBout()
    }

    /// Writes one finished part of a break, a strength set as much as a movement block, so the
    /// planner, recency and the difficulty-3 unlock all read it.
    func recordPartCompletion(_ part: BreakPart, breakId: UUID?) {
        history.record(completion: MovementCompletion(
            movementId: part.movementId,
            at: clock.now,
            seconds: part.seconds,
            routineId: breakId
        ))
    }

    // MARK: - Micro-breaks

    /// Built in the mode in use now, and kept as it is until it ends whatever the mode does.
    private func beginMicro() {
        let next = Set(previewNextBreak(now: clock.now).movementIds)
        currentMicro = activeModeBuilder.microBreak(for: self, at: clock.now, nextFullBreakIds: next)
        currentMicroMode = settings.mode
    }

    private func endMicro() {
        if let micro = currentMicro { lastMicroIds = Set(micro.movementIds) }
        currentMicro = nil
        currentMicroMode = nil
    }

    /// Writes the micro-break's movements, on the scheduler's word that it ran (§4.11's half rule).
    ///
    /// Separate from `endMicro` because the panel comes down for a snooze, a skip, a closed lid and
    /// an idle stretch as well as for a minute of movement, and only the scheduler knows which of
    /// those just happened. `.recordMicroDone` arrives ahead of `.hideMicro`, so `currentMicro` is
    /// still here to be read.
    ///
    /// Only the movements the user got halfway through are written: a two-movement micro-break
    /// skipped in its first half did one of them, not both.
    private func recordMicro(ranSeconds: Int) {
        guard let micro = currentMicro else { return }
        for part in micro.partsRun(seconds: ranSeconds) {
            recordPartCompletion(part, breakId: nil)
        }
    }

    // MARK: - Absences

    /// Writes down that an absence reset or paused the countdowns. It goes in the same list as the
    /// breaks, so the record says what happened, but it moves none of the day's numbers. It is the
    /// same record in every mode: an absence is not a break of any kind (S23).
    private func recordAbsence(_ record: AbsenceRecord) {
        history.record(
            breakRecord: BreakRecord(
                at: clock.now,
                routineName: "Away \(record.awaySeconds / 60) min",
                outcome: BreakResult(record.behaviour),
                completedBlocks: 0,
                totalBlocks: 0
            ),
            longestBoutSeconds: scheduler.snapshot.longestBoutSeconds
        )
    }

    /// "I was sitting" takes the absence back out of the record as well as out of the scheduler.
    private func reverseAbsenceRecord() {
        guard let toast = toastInfo else { return }
        history.removeLastBreakRecord(matching: BreakResult(toast.behaviour))
    }

    // MARK: - Break selection

    /// The break this full break will run, built by the mode in use now. Deterministic in the day
    /// and the break index, and cached against everything it reads, so what the menu advertises is
    /// what the overlay serves.
    func nextBreak(at now: Date) -> PlannedBreak {
        let key = previewKey(at: now)
        if let cached = cachedPreview, cached.key == key { return cached.planned }

        let planned = plannedBreak(modeId: settings.mode.rawValue, at: now)
        cachedPreview = (key, planned)
        return planned
    }

    /// The coordinator's one build path: a full break from the builder `modeId` names, uncached.
    func plannedBreak(modeId: String, at now: Date) -> PlannedBreak {
        rollDayIfNeeded(at: now)
        return modeBuilders.builder(for: modeId).fullBreak(for: self, at: now)
    }

    /// The break on screen, a slept-through break waiting to resume, the break a heads-up
    /// announced, or else the next one to build: whichever the scheduler's next full break serves.
    func previewNextBreak(now: Date) -> PlannedBreak {
        currentBreak?.planned ?? interruptedSession?.planned ?? headsUpBreak?.planned ?? nextBreak(at: now)
    }

    /// Everything the built break depends on. When any of it moves, the preview is rebuilt.
    func previewKey(at now: Date) -> String {
        let index = breakIndexToday(at: now)
        let shared = [
            scheduler.snapshot.dayKey,
            String(index),
            // The breaks put on screen this run count as served today, so one more of them
            // changes what the next break may draw even before its record is written.
            String(breaksToday.count),
            String(history.data.completions.count),
            String(settings.schedulerConfig.stableHash),
            String(settings.excludedMovementIds.count),
            settings.focus.rawValue,
            String(settings.difficultyCap),
            settings.equipment.map(\.rawValue).sorted().joined(separator: "+"),
            settings.unavailableRequirements.map(\.rawValue).sorted().joined(separator: "+"),
            settings.mode.rawValue
        ]
        return (shared + activeModeBuilder.previewKeyParts(for: self, at: now)).joined(separator: "|")
    }

    func routineContext(at now: Date, breakIndex: Int) -> RoutineContext {
        rollDayIfNeeded(at: now)
        var context = RoutineContext()
        context.date = now
        context.usedMovementIdsToday = movementIdsUsedToday(at: now)
        context.usedStrRegionsLastBreak = breaksToday.last?.routine?.strengthRegions ?? []
        context.equipment = settings.equipment
        context.unavailable = settings.unavailableRequirements
        context.excluded = settings.excludedMovementIds
        context.focus = settings.focus
        context.difficultyCap = settings.difficultyCap
        context.unlockedDiff3 = history.unlockedDiff3(library: library)
        context.recency = history.recencyScores(before: now)
        context.seed = SplitMix64.seed(day: scheduler.snapshot.dayKey, index: breakIndex)
        return context
    }

    /// Everything served today, in any kind of break and from either library: what history has
    /// recorded, and the breaks already put on screen, which are remembered even when they were
    /// skipped.
    func idsServedToday(at now: Date) -> Set<String> {
        rollDayIfNeeded(at: now)
        return history.usedMovementIds(on: now).union(breaksToday.flatMap(\.movementIds))
    }

    /// The movement-library ids a Movement build must leave alone today: everything served, plus
    /// the counterpart of any strength move served today that is the same exercise (S8). With no
    /// strength move served, that is exactly what was served.
    func movementIdsUsedToday(at now: Date) -> Set<String> {
        let served = idsServedToday(at: now)
        guard let strengthLibrary, let crossModeUsage else { return served }
        let strength = served.filter { strengthLibrary.movement(id: $0) != nil }
        guard !strength.isEmpty else { return served }
        return served.union(crossModeUsage.used(movementIds: [], strengthIds: strength).movementIds)
    }

    /// The last micro-break's ids as a Movement micro-break must leave them alone: a strength
    /// micro-break just before a switch counts by its `same` overlaps and their families, as
    /// everything served today does (S8). After a Movement micro-break it is exactly its ids.
    func lastMicroMovementIds() -> Set<String> {
        guard let strengthLibrary, let crossModeUsage else { return lastMicroIds }
        let strength = lastMicroIds.filter { strengthLibrary.movement(id: $0) != nil }
        guard !strength.isEmpty else { return lastMicroIds }
        return lastMicroIds.union(crossModeUsage.used(movementIds: [], strengthIds: strength).movementIds)
    }

    /// Which of the day's seeds the next full break is built from: the breaks recorded today,
    /// absences aside. Every full break that reached the heads-up is recorded however it ended,
    /// so the index moves on with each one. It is read from history rather than counted in
    /// memory, so a relaunch carries on from the same index: counted in memory it went back to 0,
    /// and a break skipped before any block was done, which leaves no completion behind, was
    /// built again exactly as the user had just turned it down (DECISIONS 78).
    func breakIndexToday(at now: Date) -> Int {
        rollDayIfNeeded(at: now)
        return history.breaks(on: now).filter { !$0.outcome.isAbsence }.count
    }

    func rememberBreak(_ planned: PlannedBreak, at now: Date) {
        rollDayIfNeeded(at: now)
        breaksToday.append(planned)
    }

    func rollDayIfNeeded(at now: Date) {
        let key = DayKey.key(for: now, calendar: settings.schedulerConfig.calendar)
        guard key != routinesDayKey else { return }
        routinesDayKey = key
        breaksToday.removeAll()
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
        state.breakMode = settings.mode
        state.dayProgress = dayProgress
        return state
    }

    /// "1 h 12 m" / "32 m" — the phrasing the menu uses.
    nonisolated static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }
}
