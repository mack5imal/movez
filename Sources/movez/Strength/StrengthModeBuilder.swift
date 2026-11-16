import Foundation

/// Strength mode's builds: the day plan from `StrengthDayPlanner`, then a strength or end-range
/// break, and END micro-breaks (S6, S7, S22).
///
/// Everything it reads is in history or settings, never in what this run of the app happens to
/// remember, apart from the breaks already put on screen today. That is what lets a relaunch
/// rebuild the break the menu was already advertising: the seed's index is the day's recorded
/// breaks, which survive a relaunch, rather than the breaks this process has served.
@MainActor
struct StrengthModeBuilder: ModeBreakBuilding {
    let library: StrengthLibrary
    let usage: CrossModeUsage

    func plan(for coordinator: AppCoordinator, at now: Date) -> NextFullBreak {
        let settings = coordinator.settings
        return StrengthDayPlanner(calendar: settings.schedulerConfig.calendar).next(
            records: coordinator.history.data.breakRecords,
            strengthBreaksPerDay: settings.strengthBreaksPerDay,
            focus: settings.strengthFocus,
            armBreakPossible: StrengthDayPlanner.armBreakPossible(equipment: settings.strengthEquipment),
            today: now
        )
    }

    func previewKeyParts(for coordinator: AppCoordinator, at now: Date) -> [String] {
        let settings = coordinator.settings
        return [
            String(describing: plan(for: coordinator, at: now)),
            String(seedIndex(for: coordinator, at: now)),
            settings.strengthEquipment.map(\.rawValue).sorted().joined(separator: "+"),
            String(settings.strengthSolidWallNearby),
            String(settings.strengthBreaksPerDay),
            String(settings.strengthDifficultyCap),
            settings.strengthFocus.rawValue,
            settings.strengthExcludedIds.sorted().joined(separator: "+")
        ]
    }

    func fullBreak(for coordinator: AppCoordinator, at now: Date) -> PlannedBreak {
        let seed = SplitMix64.seed(day: coordinator.scheduler.snapshot.dayKey, index: seedIndex(for: coordinator, at: now))
        let context = context(for: coordinator, at: now, seed: seed)
        if case let .strength(letter, _, _, setOrder) = plan(for: coordinator, at: now) {
            return .strength(StrengthBreakBuilder(library: library).build(letter: letter, setOrder: setOrder, context: context))
        }
        let worked = workedRegionsToday(for: coordinator, at: now)
        return .endRange(EndRangeBreakBuilder(library: library).build(context: context, avoidingRegions: worked))
    }

    func microBreak(for coordinator: AppCoordinator, at now: Date, nextFullBreakIds: Set<String>) -> PlannedMicro {
        let settings = coordinator.settings
        let snapshot = coordinator.scheduler.snapshot
        var context = StrengthMicroContext()
        context.usedStrengthIdsToday = usedStrengthIds(for: coordinator, at: now)
        context.lastMicroMovementIds = coordinator.lastMicroIds
        context.nextFullBreakIds = nextFullBreakIds
        context.solidWallNearby = settings.strengthSolidWallNearby
        context.difficultyCap = settings.strengthDifficultyCap
        context.unlockedBuckets = unlockedBuckets(for: coordinator)
        context.recency = coordinator.history.recencyScores(before: now)
        context.excluded = settings.strengthExcludedIds
        context.seed = SplitMix64.seed(day: snapshot.dayKey, index: 1_000 + snapshot.microEmphasisIndex)
        return .strength(StrengthMicroBuilder(library: library).build(context: context))
    }

    func dayProgress(for coordinator: AppCoordinator, at now: Date) -> ModeDayProgress? {
        let perDay = coordinator.settings.strengthBreaksPerDay
        if case let .strength(letter, index, count, _) = plan(for: coordinator, at: now) {
            return ModeDayProgress(dayLetter: letter, breakNumber: index, breaksPerDay: count)
        }
        let letter = StrengthDayPlanner(calendar: coordinator.settings.schedulerConfig.calendar)
            .letter(records: coordinator.history.data.breakRecords, today: now)
        return ModeDayProgress(dayLetter: letter, breakNumber: nil, breaksPerDay: perDay)
    }

    // MARK: - Inputs

    func context(for coordinator: AppCoordinator, at now: Date, seed: UInt64) -> StrengthContext {
        let settings = coordinator.settings
        var context = StrengthContext()
        context.usedStrengthIdsToday = usedStrengthIds(for: coordinator, at: now)
        context.equipment = settings.strengthEquipment
        context.solidWallNearby = settings.strengthSolidWallNearby
        context.difficultyCap = settings.strengthDifficultyCap
        context.unlockedBuckets = unlockedBuckets(for: coordinator)
        context.focus = settings.strengthFocus
        context.recency = coordinator.history.recencyScores(before: now)
        context.excluded = settings.strengthExcludedIds
        context.seed = seed
        return context
    }

    /// Today's served ids from both libraries, widened so that a `same` overlap served in a
    /// Movement break, or any member of its family, rules its strength counterpart out (S8).
    func usedStrengthIds(for coordinator: AppCoordinator, at now: Date) -> Set<String> {
        let served = coordinator.idsServedToday(at: now)
        let strength = served.filter { library.movement(id: $0) != nil }
        return usage.used(movementIds: served.subtracting(strength), strengthIds: strength).strengthIds
    }

    /// The breaks recorded today, absences aside. Every full break that reached the heads-up is
    /// recorded however it ended, so the index moves on with each one, and it is read from history
    /// so that it is the same after a relaunch.
    func seedIndex(for coordinator: AppCoordinator, at now: Date) -> Int {
        coordinator.history.breaks(on: now).filter { !$0.outcome.isAbsence }.count
    }

    private func unlockedBuckets(for coordinator: AppCoordinator) -> Set<StrengthBucket> {
        StrengthUnlock.unlockedBuckets(library: library, completions: coordinator.history.data.completions)
    }

    /// The regions today's completed strength work loaded, which an end-range break leaves alone
    /// where it can. Read from history's completions rather than from the breaks served, so a
    /// skipped strength break, which loaded nothing, adds nothing; the warm-ups are counted with
    /// the sets, which is harmless because each warm-up is drawn from a pattern the day trains.
    private func workedRegionsToday(for coordinator: AppCoordinator, at now: Date) -> Set<Region> {
        var regions = Set<Region>()
        for id in coordinator.history.usedMovementIds(on: now) {
            guard let movement = library.movement(id: id), movement.bucket != .end else { continue }
            regions.formUnion(movement.regions)
        }
        return regions
    }
}
