import Foundation

/// Movement mode's builds, exactly as the coordinator made them before there were modes: the full
/// break through `RoutineBuilder`, the micro-break through `MicroBreakBuilder`.
@MainActor
struct MovementModeBuilder: ModeBreakBuilding {
    /// The routine reads nothing the coordinator's shared preview key leaves out.
    func previewKeyParts(for coordinator: AppCoordinator, at now: Date) -> [String] { [] }

    func fullBreak(for coordinator: AppCoordinator, at now: Date) -> PlannedBreak {
        let index = coordinator.breakIndexToday(at: now)
        return .movement(coordinator.builder.build(context: coordinator.routineContext(at: now, breakIndex: index)))
    }

    func microBreak(for coordinator: AppCoordinator, at now: Date, nextFullBreakIds: Set<String>) -> PlannedMicro {
        let snapshot = coordinator.scheduler.snapshot
        let settings = coordinator.settings
        var context = MicroContext()
        context.usedMovementIdsToday = coordinator.movementIdsUsedToday(at: now)
        context.lastMicroMovementIds = coordinator.lastMicroMovementIds()
        context.nextFullRoutineIds = nextFullBreakIds
        context.excluded = settings.excludedMovementIds
        context.equipment = settings.equipment
        context.unavailable = settings.unavailableRequirements
        context.difficultyCap = settings.difficultyCap
        context.unlockedDiff3 = coordinator.history.unlockedDiff3(library: coordinator.library)
        context.recency = coordinator.history.recencyScores(before: now)
        context.seed = SplitMix64.seed(day: snapshot.dayKey, index: 1_000 + snapshot.microEmphasisIndex)
        return .movement(coordinator.microBuilder.build(context: context))
    }

    func dayProgress(for coordinator: AppCoordinator, at now: Date) -> ModeDayProgress? { nil }
}
