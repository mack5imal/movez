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
    /// The settings' own defaults, so a relaunch can read the same settings back.
    let defaults: UserDefaults
    private(set) var coordinator: AppCoordinator
    private let modeBuilders: ModeBuilderTable?

    init(
        workingHours: WorkingHours = .standard,
        startAt: Date = SchedulerHarness.mondayMorning,
        modeBuilders: ModeBuilderTable? = nil,
        configure: (SettingsStore) -> Void = { _ in }
    ) {
        clock = ManualClock(now: startAt)
        defaults = ScratchDefaults.make()
        settings = SettingsStore(defaults: defaults)
        settings.workingHours = workingHours
        configure(settings)
        history = HistoryStore(store: historyStore)
        self.modeBuilders = modeBuilders
        coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            strengthLibrary: RoutineTestSupport.strengthLibrary,
            modeBuilders: modeBuilders,
            settings: settings,
            history: history,
            clock: clock,
            snapshotStore: snapshotStore,
            sink: sink
        )
    }

    /// Quits and starts again on the same state file, history file and settings, the way a
    /// relaunch reads them back: the coordinator, the settings and the history are all new
    /// objects, and only what was written survives. Read them through `coordinator` afterwards:
    /// `history` and `settings` stay the first launch's.
    func relaunch() {
        coordinator.stop()
        let settings = SettingsStore(defaults: defaults)
        let history = HistoryStore(store: historyStore)
        coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            strengthLibrary: RoutineTestSupport.strengthLibrary,
            modeBuilders: modeBuilders,
            settings: settings,
            history: history,
            clock: clock,
            snapshotStore: snapshotStore,
            sink: sink
        )
        coordinator.applyLaunchGap()
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

extension RoutineTestSupport {
    /// The bundled strength library, loaded once for every coordinator a test builds.
    static let strengthLibrary: StrengthLibrary = {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: library)
        } catch {
            fatalError("Bundled strength library failed to load: \(error)")
        }
    }()
}

extension AppCoordinator {
    /// What the overlay does when the block on screen ends, through the same intents the overlay
    /// calls: the block is recorded by its index, and the last one finishes the break. Production
    /// has no "next block" intent of its own, so the tests drive the path the app actually takes.
    func nextBlock() {
        guard let current = currentBreak else { return }
        let index = current.blockIndex
        if let routine = current.routine {
            guard routine.blocks.indices.contains(index) else { return }
            recordOverlayBlock(routine.blocks[index], index: index)
        } else {
            recordOverlayPart(index: index)
        }
        guard let after = currentBreak, index >= after.totalBlocks - 1 else { return }
        finishOverlayBreak(
            completed: after.completedBlocks,
            total: after.totalBlocks,
            elapsed: max(0, Int(clock.now.timeIntervalSince(after.startedAt)))
        )
    }
}
