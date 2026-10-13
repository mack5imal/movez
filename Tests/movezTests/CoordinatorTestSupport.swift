import Foundation
import XCTest
@testable import movez

/// Builds a coordinator on a manual clock with isolated settings and history, and drives it the
/// way the real tick timer would.
@MainActor
final class CoordinatorHarness {
    let clock: ManualClock
    let settings: SettingsStore
    let history: HistoryStore
    let sink = RecordingEffectSink()
    let snapshotStore = InMemorySnapshotStore()
    let historyStore = InMemoryHistoryStore()
    let coordinator: AppCoordinator

    init(
        workingHours: WorkingHours = .standard,
        startAt: Date = SchedulerHarness.mondayMorning,
        configure: (SettingsStore) -> Void = { _ in }
    ) {
        clock = ManualClock(now: startAt)
        let suite = ScratchDefaults.make()
        settings = SettingsStore(defaults: suite)
        settings.workingHours = workingHours
        configure(settings)
        history = HistoryStore(store: historyStore)
        coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            settings: settings,
            history: history,
            clock: clock,
            snapshotStore: snapshotStore,
            sink: sink
        )
    }

    var scheduler: Scheduler { coordinator.scheduler }
    var state: SchedulerState { coordinator.scheduler.state }
    var now: Date { clock.now }

    /// Advances in 2 s ticks.
    func run(seconds: TimeInterval) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            clock.advance(2)
            elapsed += 2
            coordinator.tick()
        }
    }

    func run(until predicate: (SchedulerState) -> Bool, limit: TimeInterval = 4 * 3600) -> Bool {
        var elapsed: TimeInterval = 0
        while elapsed < limit {
            if predicate(coordinator.scheduler.state) { return true }
            clock.advance(2)
            elapsed += 2
            coordinator.tick()
        }
        return predicate(coordinator.scheduler.state)
    }

    /// Works through every block of the break currently on screen.
    func completeBreak() {
        guard var remaining = coordinator.currentBreak?.totalBlocks else { return }
        while remaining > 0, coordinator.currentBreak != nil {
            clock.advance(60)
            coordinator.nextBlock()
            remaining -= 1
        }
    }
}
