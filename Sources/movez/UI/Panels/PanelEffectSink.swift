import Foundation

/// Turns the scheduler's panel effects into windows, and the panels' buttons back into intents.
///
/// The coordinator has already applied the effect to its own state by the time this runs, which
/// is why the micro-break and the toast can be read straight off it.
@MainActor
final class PanelEffectSink: EffectSink {
    let controller: PanelWindowController
    private let chimes: ChimePlayer?

    init(controller: PanelWindowController, chimes: ChimePlayer? = nil) {
        self.controller = controller
        self.chimes = chimes
    }

    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator) {
        switch effect {
        case .showHeadsUp(let info):
            present(headsUp: info, coordinator: coordinator)
        case .hideHeadsUp, .hideMicro:
            controller.hidePanel()
        case .showMicroCountIn(let info):
            present(micro: info, coordinator: coordinator)
        case .showMicroRunning:
            // The count-in panel stays put; only its contents change.
            controller.panelModel?.beginMicroRunning(at: coordinator.clock.now)
        case .showToast:
            presentToast(coordinator: coordinator)
        case .hideToast:
            controller.hideToast()
        default:
            break
        }
    }

    private func present(headsUp info: HeadsUpInfo, coordinator: AppCoordinator) {
        let now = coordinator.clock.now
        let config = coordinator.settings.schedulerConfig
        let routine = coordinator.nextRoutinePreview ?? coordinator.nextRoutine(at: now)
        let model = PanelViewModel(
            phase: .headsUp,
            clock: coordinator.clock,
            startedAt: now,
            totalSeconds: config.headsUpSeconds
        )
        model.blockCount = routine.blocks.count
        model.breakMinutes = max(1, config.breakSeconds / 60)
        model.snoozesLeft = info.snoozesLeft
        model.skipsToday = info.skipsToday
        if info.showDeferredBadge {
            model.deferred = PanelViewModel.DeferredInfo(
                sittingFor: TimeInterval(info.sittingSeconds),
                reason: info.deferredReason ?? .microphone
            )
        }
        model.actions.startNow = { [weak coordinator] in coordinator?.startNow() }
        model.actions.snooze = { [weak coordinator] in coordinator?.snooze() }
        model.actions.skip = { [weak coordinator] in coordinator?.skip() }
        controller.present(panel: model)
    }

    private func present(micro info: MicroInfo, coordinator: AppCoordinator) {
        guard let micro = coordinator.currentMicro else { return }
        let model = PanelViewModel(
            phase: .microCountIn,
            clock: coordinator.clock,
            startedAt: coordinator.clock.now,
            totalSeconds: info.countInSeconds
        )
        model.micro = micro
        model.microSeconds = info.seconds
        model.chimes = chimes
        model.microSnoozeUsed = coordinator.scheduler.snapshot.microSnoozeUsed
        model.actions.microStartNow = { [weak coordinator] in coordinator?.microStartNow() }
        model.actions.microSnooze = { [weak coordinator] in coordinator?.microSnooze() }
        model.actions.microSkip = { [weak coordinator] in coordinator?.microSkip() }
        model.actions.microEnded = { [weak coordinator] in coordinator?.microEnded() }
        controller.present(panel: model)
    }

    private func presentToast(coordinator: AppCoordinator) {
        guard let info = coordinator.toastInfo else { return }
        let model = PanelViewModel(
            phase: .toast,
            clock: coordinator.clock,
            startedAt: coordinator.clock.now,
            totalSeconds: info.secondsOnScreen
        )
        model.toast = info
        model.actions.reverseToast = { [weak coordinator] in coordinator?.reverseToast() }
        controller.present(toast: model)
    }
}
