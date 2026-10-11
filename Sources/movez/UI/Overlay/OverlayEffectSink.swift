import AppKit
import Foundation

/// Turns scheduler effects into the overlay appearing, advancing and going away, and into sound.
@MainActor
final class OverlayEffectSink: EffectSink {
    let controller: OverlayWindowController
    let chimes: ChimePlayer

    init(controller: OverlayWindowController, chimes: ChimePlayer) {
        self.controller = controller
        self.chimes = chimes
    }

    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator) {
        switch effect {
        case .startFullBreak:
            present(coordinator: coordinator)
        case .endFullBreak(let outcome):
            // A break the user finished fades out; one cut short by sleep or a lock goes at once.
            controller.dismiss(animated: isGraceful(outcome))
        case .chime(let chime):
            // Sound inside a break belongs to the overlay, which is the only thing that knows
            // about blocks; by the time the scheduler reports the break ended, the completion
            // chime has already played. Playing its copy too would double it.
            guard !(chime == .completion && controller.isPresenting) else { return }
            chimes.play(chime)
        default:
            break
        }
    }

    private func isGraceful(_ outcome: BreakOutcome) -> Bool {
        switch outcome {
        case .interrupted: return false
        case .completed, .skipped, .snoozed: return true
        }
    }

    private func present(coordinator: AppCoordinator) {
        guard let session = coordinator.currentBreak else { return }
        let viewModel = OverlayViewModel(
            routine: session.routine,
            startedAt: session.startedAt,
            clock: coordinator.clock,
            config: coordinator.settings.schedulerConfig,
            chimes: chimes,
            snoozesLeft: coordinator.scheduler.snoozesLeft,
            skipsToday: coordinator.scheduler.snapshot.skipsToday,
            streak: coordinator.streak,
            nextBreakAt: coordinator.scheduler.snapshot.nextFullDueAt,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        viewModel.onBlockCompleted = { [weak coordinator] block, _ in
            coordinator?.recordOverlayBlock(block)
        }
        viewModel.onSnooze = { [weak coordinator] in coordinator?.snooze() }
        viewModel.onSkip = { [weak coordinator] in coordinator?.skip() }
        viewModel.onFinished = { [weak coordinator] completed, total, elapsed in
            coordinator?.finishOverlayBreak(completed: completed, total: total, elapsed: elapsed)
        }
        controller.present(viewModel)
    }
}
