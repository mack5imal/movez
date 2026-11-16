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

    /// The overlay sat paused for five minutes without the break counting: it ends as snoozed.
    func pauseExpired() { inject(.overlayPauseExpired) }

    /// The overlay owns block progression while a break is on screen — it is the only thing that
    /// knows about blocks — so this records what it did without driving the scheduler.
    ///
    /// The block is the one the overlay names by `index`, as with `recordOverlayPart`. A block
    /// already recorded is ignored: written twice, it counted twice in recency and toward the
    /// difficulty-3 unlock.
    func recordOverlayBlock(_ block: RoutineBlock, index: Int) {
        guard var current = currentBreak, index >= current.completedBlocks, index < current.totalBlocks else { return }
        recordPartCompletion(BreakPart(movementId: block.movement.id, seconds: block.seconds), breakId: current.planned.id)
        current.completedBlocks = index + 1
        current.blockIndex = min(index + 1, max(0, current.totalBlocks - 1))
        currentBreak = current
    }

    /// Records the part of a strength or end-range break the overlay just finished: its warm-up,
    /// a set, its cool-down or an end-range block. As with `recordOverlayBlock`, the overlay owns
    /// the progression and this only writes it down.
    ///
    /// The part is the one the overlay names by `index`, not the session's own position: after a
    /// wake the overlay is rebuilt and replays the parts already done from the backdated start,
    /// so a part already recorded, or an index past the last part, is ignored rather than written
    /// again.
    func recordOverlayPart(index: Int) {
        guard var current = currentBreak else { return }
        let parts = current.planned.parts
        guard parts.indices.contains(index), index >= current.completedBlocks else { return }
        recordPartCompletion(parts[index], breakId: current.planned.id)
        current.completedBlocks = index + 1
        current.blockIndex = min(index + 1, max(0, current.totalBlocks - 1))
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

    /// A Focus turning on or off. The request is held until the scheduler can take it.
    func focusFilter(paused: Bool) {
        pendingFocusPause = paused
        applyPendingFocus()
    }

    /// Offers the held Focus request to the scheduler. A pause waits out a full break on screen,
    /// the one state that refuses it; anything else settles the request, including a pause set by
    /// hand, which a Focus never overrides. Once settled it is not offered again, so "Resume now"
    /// during a Focus is not undone on the next tick.
    func applyPendingFocus() {
        guard let paused = pendingFocusPause else { return }
        if paused, case .fullBreak = scheduler.state { return }
        pendingFocusPause = nil
        inject(.focusFilter(paused: paused))
    }

    // MARK: - Toast

    func reverseToast() {
        guard let toast = toastInfo else { return }
        inject(.toastReverse(toast.reversal))
    }
}
