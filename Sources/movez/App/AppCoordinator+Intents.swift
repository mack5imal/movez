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

    func setCollapsed(_ movementId: String, _ collapsed: Bool) {
        history.setCollapsed(movementId, collapsed)
    }

    func isCollapsed(_ movementId: String) -> Bool {
        history.isCollapsed(movementId)
    }

    // MARK: - Micro-break

    func microStartNow() { inject(.userMicroStartNow) }
    func microSnooze() { inject(.userMicroSnooze) }
    func microSkip() { inject(.userMicroSkip) }

    // MARK: - Toast

    func reverseToast() {
        guard let toast = toastInfo else { return }
        inject(.toastReverse(toast.reversal))
    }
}
