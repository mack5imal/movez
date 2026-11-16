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
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let routine = session.routine {
            presentRoutine(routine, session: session, coordinator: coordinator, reduceMotion: reduceMotion)
            return
        }
        let viewModel: StrengthOverlayViewModel
        if let strengthBreak = session.planned.strengthBreak {
            viewModel = StrengthOverlayViewModel(
                strengthBreak: strengthBreak, startedAt: session.startedAt, clock: coordinator.clock,
                config: coordinator.scheduler.config, chimes: chimes, snoozesLeft: coordinator.scheduler.snoozesLeft,
                skipsToday: coordinator.scheduler.snapshot.skipsToday, reduceMotion: reduceMotion, mode: session.mode
            )
        } else if let endRangeBreak = session.planned.endRangeBreak {
            viewModel = StrengthOverlayViewModel(
                endRangeBreak: endRangeBreak, startedAt: session.startedAt, clock: coordinator.clock,
                config: coordinator.scheduler.config, chimes: chimes, snoozesLeft: coordinator.scheduler.snoozesLeft,
                skipsToday: coordinator.scheduler.snapshot.skipsToday, reduceMotion: reduceMotion, mode: session.mode
            )
        } else {
            return
        }
        viewModel.onWorkCompleted = { [weak coordinator] index in coordinator?.recordOverlayPart(index: index) }
        viewModel.onSnooze = { [weak coordinator] in coordinator?.snooze() }
        viewModel.onSkip = { [weak coordinator] in coordinator?.skip() }
        viewModel.onPauseExpired = { [weak coordinator] in coordinator?.pauseExpired() }
        viewModel.onFinished = { [weak coordinator] completed, total, elapsed in
            coordinator?.finishOverlayBreak(completed: completed, total: total, elapsed: elapsed)
        }
        controller.present(viewModel)
    }

    private func presentRoutine(_ routine: Routine, session: BreakSession, coordinator: AppCoordinator, reduceMotion: Bool) {
        let viewModel = OverlayViewModel(
            routine: routine,
            startedAt: session.startedAt,
            clock: coordinator.clock,
            // The scheduler's config, not the settings': it carries the length of the break on
            // screen, which is what "half the time" is measured against.
            config: coordinator.scheduler.config,
            chimes: chimes,
            snoozesLeft: coordinator.scheduler.snoozesLeft,
            skipsToday: coordinator.scheduler.snapshot.skipsToday,
            reduceMotion: reduceMotion,
            mode: session.mode,
            resumingAt: session.blockIndex,
            completedBlocks: session.completedBlocks
        )
        viewModel.onBlockCompleted = { [weak coordinator] block, index in
            coordinator?.recordOverlayBlock(block, index: index)
        }
        viewModel.onSnooze = { [weak coordinator] in coordinator?.snooze() }
        viewModel.onSkip = { [weak coordinator] in coordinator?.skip() }
        viewModel.onPauseExpired = { [weak coordinator] in coordinator?.pauseExpired() }
        viewModel.onFinished = { [weak coordinator] completed, total, elapsed in
            coordinator?.finishOverlayBreak(completed: completed, total: total, elapsed: elapsed)
        }
        controller.present(viewModel)
    }
}
