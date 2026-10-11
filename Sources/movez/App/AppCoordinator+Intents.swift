import Foundation

/// Everything the UI can ask for. Each intent is a thin wrapper around a scheduler event plus
/// whatever block bookkeeping the scheduler cannot do itself.
extension AppCoordinator {
    // MARK: - Menu bar

    func takeBreakNow() { inject(.userTakeBreakNow) }
    func makeDue(inSeconds seconds: Int) { inject(.userMakeDueIn(seconds: seconds)) }
    func pause(forSeconds seconds: Int?) { inject(.userPause(seconds: seconds)) }
    func resume() { inject(.userResume) }
    func extendPause(bySeconds seconds: Int) { inject(.userExtendPause(seconds: seconds)) }
    func startSession() { inject(.userStartSession) }
    func endSession() { inject(.userEndSession) }

    // MARK: - Heads-up and overlay

    func startNow() { inject(.userStartNow) }
    func snooze() { inject(.userSnooze) }

    func skip() { inject(.userSkip) }

    /// Advances to the next block, recording the one that just finished.
    func nextBlock() {
        guard var current = currentBreak, let block = current.block else { return }
        recordBlockCompletion(block, routineId: current.routine.id)
        current.completedBlocks += 1

        guard !current.isLastBlock else {
            currentBreak = current
            done()
            return
        }
        current.blockIndex += 1
        currentBreak = current
        inject(.userNextBlock)
    }

    /// True once the break counts: half the movements, or half the time.
    var canFinishBreak: Bool {
        guard let current = currentBreak else { return false }
        return Scheduler.meetsCompletionRule(
            completed: current.completedBlocks,
            total: current.totalBlocks,
            elapsed: elapsedInBreak,
            config: settings.schedulerConfig
        )
    }

    var elapsedInBreak: Int {
        guard let current = currentBreak else { return 0 }
        return max(0, Int(clock.now.timeIntervalSince(current.startedAt)))
    }

    func done() {
        guard let current = currentBreak else { return }
        inject(.userDone(
            completedBlocks: current.completedBlocks,
            totalBlocks: current.totalBlocks,
            elapsed: elapsedInBreak
        ))
    }

    /// Ends the break as it stands — the scheduler decides whether that counts or is a skip.
    func endBreak() {
        guard let current = currentBreak else { return }
        inject(.breakEnded(
            completedBlocks: current.completedBlocks,
            totalBlocks: current.totalBlocks,
            elapsed: elapsedInBreak
        ))
    }

    /// The overlay owns block progression while a break is on screen — it is the only thing that
    /// knows about blocks — so this records what it did without driving the scheduler.
    func recordOverlayBlock(_ block: RoutineBlock) {
        guard var current = currentBreak else { return }
        recordBlockCompletion(block, routineId: current.routine.id)
        current.completedBlocks += 1
        current.blockIndex = min(current.blockIndex + 1, max(0, current.totalBlocks - 1))
        currentBreak = current
    }

    /// Ends a break the overlay finished. The scheduler decides whether that counts, from the time
    /// the overlay says the break ran: it knows about time spent paused, and the wall clock doesn't.
    func finishOverlayBreak(completed: Int, total: Int, elapsed: Int) {
        inject(.breakEnded(completedBlocks: completed, totalBlocks: total, elapsed: elapsed))
    }

    // MARK: - Micro-break

    func microStartNow() { inject(.userMicroStartNow) }
    func microSnooze() { inject(.userMicroSnooze) }
    func microSkip() { inject(.userMicroSkip) }

    /// The micro-break's minute ran out. The panel owns its own countdown, the way the overlay
    /// owns the break's, so it is the panel that says when the minute is done.
    func microEnded() { inject(.microEnded) }

    /// A Focus turning on or off.
    func focusFilter(paused: Bool) { inject(.focusFilter(paused: paused)) }

    // MARK: - Toast

    func reverseToast() {
        guard let toast = toastInfo else { return }
        inject(.toastReverse(toast.reversal))
    }
}
