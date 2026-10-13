import XCTest
@testable import movez

/// What movez does when it starts up into a mess: no files, broken files, nothing to serve.
@MainActor
final class LaunchStateTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("movez.tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func settings() -> SettingsStore {
        SettingsStore(defaults: ScratchDefaults.make())
    }

    // MARK: - Relaunching into a running session

    /// A coordinator built the way `AppDelegate` builds one, on a seeded state file.
    private func relaunch(
        seed: SchedulerSnapshot,
        at now: Date,
        workingHours: WorkingHours = .alwaysOn
    ) -> (coordinator: AppCoordinator, sink: RecordingEffectSink) {
        let store = InMemorySnapshotStore(seed: seed)
        let sink = RecordingEffectSink()
        let settings = self.settings()
        settings.workingHours = workingHours
        let coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            settings: settings,
            history: HistoryStore(store: InMemoryHistoryStore()),
            clock: ManualClock(now: now),
            snapshotStore: store,
            sink: sink
        )
        coordinator.applyLaunchGap()
        return (coordinator, sink)
    }

    /// A snapshot mid-bout: sat down at `boutStartedAt`, break due 55 minutes later.
    private func sitting(boutStartedAt: Date, savedAt: Date?, doneToday: Int = 0) -> SchedulerSnapshot {
        var snapshot = SchedulerSnapshot(
            now: boutStartedAt,
            dayKey: DayKey.key(for: boutStartedAt, calendar: .current)
        )
        snapshot.state = .sitting
        snapshot.nextFullDueAt = boutStartedAt.addingTimeInterval(55 * 60)
        snapshot.nextMicroDueAt = boutStartedAt.addingTimeInterval(30 * 60)
        snapshot.doneToday = doneToday
        snapshot.savedAt = savedAt
        return snapshot
    }

    private static func date(month: Int = 9, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_767_225_600)
    }

    func testASnapshotSavedMinutesAgoResumesWithTheTimeItHadLeft() {
        let satDown = Self.date(day: 7, hour: 23, minute: 30)
        let saved = Self.date(day: 7, hour: 23, minute: 50)
        let launch = Self.date(day: 7, hour: 23, minute: 52)

        let (coordinator, sink) = relaunch(seed: sitting(boutStartedAt: satDown, savedAt: saved, doneToday: 3), at: launch)

        XCTAssertEqual(coordinator.scheduler.state.name, "sitting")
        // Two minutes off, so the break that was due at 00:25 is now due at 00:27.
        XCTAssertDate(
            coordinator.scheduler.snapshot.nextFullDueAt,
            satDown.addingTimeInterval(55 * 60 + 120),
            accuracy: 2,
            "the countdown moves out by the gap, it does not restart"
        )
        XCTAssertEqual(coordinator.scheduler.snapshot.doneToday, 3, "and the day is untouched")
        XCTAssertFalse(sink.names.contains("showToast"))
    }

    func testAQuitWhileWorkingIsNeverCreditedAsABreak() {
        let satDown = Self.date(day: 7, hour: 14)
        let saved = Self.date(day: 7, hour: 14, minute: 20)
        let launch = Self.date(day: 7, hour: 14, minute: 30)   // ten minutes gone

        let (coordinator, sink) = relaunch(seed: sitting(boutStartedAt: satDown, savedAt: saved, doneToday: 2), at: launch)

        XCTAssertEqual(coordinator.scheduler.snapshot.doneToday, 2,
                       "movez was not watching, so it does not get to say a break happened")
        XCTAssertFalse(sink.names.contains("showToast"))
        XCTAssertDate(
            coordinator.scheduler.snapshot.nextFullDueAt,
            satDown.addingTimeInterval(55 * 60 + 600),
            accuracy: 2
        )
    }

    func testASnapshotRestoredAfterTheWeekendDoesNotFireABreakAtLaunch() {
        let friday = Self.date(day: 4, hour: 17)
        let (coordinator, sink) = relaunch(
            seed: sitting(boutStartedAt: friday, savedAt: friday.addingTimeInterval(30 * 60), doneToday: 5),
            at: Self.date(day: 7, hour: 9)
        )

        XCTAssertFalse(sink.names.contains("showHeadsUp"), "no break at the moment of launch")
        XCTAssertFalse(sink.names.contains("startFullBreak"))
        XCTAssertEqual(coordinator.scheduler.state.name, "sitting")
        XCTAssertEqual(coordinator.scheduler.snapshot.doneToday, 0, "Monday does not open with Friday's numbers")
        XCTAssertDate(
            coordinator.scheduler.snapshot.nextFullDueAt,
            Self.date(day: 7, hour: 9).addingTimeInterval(55 * 60),
            accuracy: 2
        )
    }

    /// Quit after midnight and relaunched the same evening: the calendar day never changed, so
    /// nothing used to notice that the session had ended hours ago.
    func testASnapshotRestoredLaterTheSameDayDoesNotFireABreakAtLaunch() {
        let earlyHours = Self.date(day: 7, hour: 0, minute: 30)
        let (coordinator, sink) = relaunch(
            seed: sitting(boutStartedAt: earlyHours, savedAt: earlyHours.addingTimeInterval(20 * 60)),
            at: Self.date(day: 7, hour: 23)
        )

        XCTAssertFalse(sink.names.contains("showHeadsUp"))
        XCTAssertFalse(sink.names.contains("startFullBreak"))
        XCTAssertDate(
            coordinator.scheduler.snapshot.nextFullDueAt,
            Self.date(day: 7, hour: 23).addingTimeInterval(55 * 60),
            accuracy: 2,
            "twenty-two hours is a new session by any reading"
        )
    }

    func testAStateFileWithNoSavedTimeStillDoesNotFireABreakAtLaunch() {
        let satDown = Self.date(day: 7, hour: 6)
        let (coordinator, sink) = relaunch(
            seed: sitting(boutStartedAt: satDown, savedAt: nil),   // written by an older build
            at: Self.date(day: 7, hour: 9)
        )

        XCTAssertFalse(sink.names.contains("showHeadsUp"))
        XCTAssertFalse(sink.names.contains("startFullBreak"))
        XCTAssertEqual(coordinator.scheduler.state.name, "sitting")
    }

    func testABreakRestoredWithNothingOnScreenIsResolvedAtLaunch() {
        let satDown = Self.date(day: 7, hour: 10)
        var seed = sitting(boutStartedAt: satDown, savedAt: Self.date(day: 7, hour: 10, minute: 55))
        seed.state = .fullBreak(startedAt: Self.date(day: 7, hour: 10, minute: 55))

        let (coordinator, _) = relaunch(seed: seed, at: Self.date(day: 7, hour: 11, minute: 15))

        XCTAssertEqual(coordinator.scheduler.state.name, "sitting",
                       "the overlay died with the process; movez must not sit in `full_break` forever")
    }

    func testTheStateFileIsRefreshedWhileTheAppIsQuiet() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let before = harness.snapshotStore.saveCount

        harness.run(seconds: 3 * 60)   // no transitions in three quiet minutes

        XCTAssertGreaterThanOrEqual(
            harness.snapshotStore.saveCount - before, 5,
            "the state file is the app's proof of life and has to be kept warm"
        )
        XCTAssertDate(harness.snapshotStore.saved?.savedAt, harness.now, accuracy: 31)
    }

    // MARK: - First launch

    func testAFirstLaunchWithNoFilesStartsAFreshDay() throws {
        let directory = try temporaryDirectory()
        let snapshots = FileSnapshotStore(url: directory.appendingPathComponent("state.json"))
        let history = FileHistoryStore(url: directory.appendingPathComponent("history.json"))

        XCTAssertNil(try snapshots.load())
        XCTAssertNil(try history.load())

        let coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            settings: settings(),
            history: HistoryStore(store: history),
            clock: ManualClock(now: SchedulerHarness.mondayMorning),
            snapshotStore: snapshots
        )
        XCTAssertEqual(coordinator.scheduler.state.name, "sitting")
        XCTAssertEqual(coordinator.todayStats, .empty)
    }

    // MARK: - Corrupt files

    func testACorruptStateFileStartsFreshInsteadOfCrashing() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("state.json")
        try "{ this is not json".write(to: url, atomically: true, encoding: .utf8)
        let store = FileSnapshotStore(url: url)

        XCTAssertThrowsError(try store.load(), "the store itself is honest about it")
        XCTAssertNil(AppCoordinator.restore(from: store), "and the coordinator starts fresh")

        let coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            settings: settings(),
            history: HistoryStore(),
            clock: ManualClock(now: SchedulerHarness.mondayMorning),
            snapshotStore: store
        )
        XCTAssertEqual(coordinator.scheduler.state.name, "sitting")
    }

    func testACorruptHistoryFileCostsTheRecordAndNothingElse() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("history.json")
        try "]]not json[[".write(to: url, atomically: true, encoding: .utf8)

        let store = HistoryStore(store: FileHistoryStore(url: url))
        XCTAssertEqual(store.data, HistoryData())
        XCTAssertEqual(store.stats(on: SchedulerHarness.mondayMorning), .empty)
    }

    // MARK: - A library that will not load

    func testAMissingLibraryIsFatalAndSaysSo() {
        let presenter = RecordingFatalPresenter()
        let library = Launch.loadLibrary(
            using: { throw LibraryError.resourceMissing("movement-library-v4.json") },
            presenter: presenter
        )

        XCTAssertNil(library)
        XCTAssertEqual(presenter.errors.count, 1)
        XCTAssertEqual(presenter.errors.first as? LibraryError, .resourceMissing("movement-library-v4.json"))
    }

    func testTheBundledLibraryLoadsAndIsTheOneTheFooterAdvertises() {
        let presenter = RecordingFatalPresenter()
        let library = Launch.loadLibrary(presenter: presenter)

        XCTAssertNotNil(library)
        XCTAssertTrue(presenter.errors.isEmpty)
        XCTAssertEqual(library?.version, "4.1")
        XCTAssertEqual(library?.movements.count, 159)
    }

    // MARK: - Nothing left to choose from

    func testABucketWithEveryMovementExcludedStillBuildsARoutine() {
        let library = RoutineTestSupport.library
        var context = RoutineContext()
        context.excluded = Set(library.movements(in: .cir).map(\.id))

        let routine = RoutineTestSupport.builder.build(context: context)

        XCTAssertFalse(routine.blocks.isEmpty, "a break with no movements is worse than a repeat")
        XCTAssertTrue(
            routine.movementIds.allSatisfy { !context.excluded.contains($0) },
            "and it still never serves something the user has switched off"
        )
    }

    func testEveryEquipmentOffStillBuildsARoutine() {
        var context = RoutineContext()
        context.equipment = []
        let routine = RoutineTestSupport.builder.build(context: context)
        XCTAssertGreaterThanOrEqual(routine.blocks.count, 3)
    }

    func testEveryMovementExcludedFallsBackRatherThanServingNothing() {
        let library = RoutineTestSupport.library
        var context = RoutineContext()
        context.excluded = Set(library.movements.map(\.id))

        let routine = RoutineTestSupport.builder.build(context: context)
        XCTAssertFalse(routine.blocks.isEmpty, "the last resort is a repeat, never an empty break")
    }

    // MARK: - The font

    func testTheFontRegistersAndTheAppWouldStillRunWithoutIt() {
        XCTAssertTrue(MovezFont.register())
        XCTAssertTrue(MovezFont.isAvailable)
        // The fallback is what keeps a missing font from being fatal.
        XCTAssertNotNil(MovezFont.nsFont(13, weight: .semibold))
    }

    // MARK: - Long calls

    func testAMicrophoneHeldForThreeHoursReadsInHours() {
        let deferred = PanelViewModel.DeferredInfo(sittingFor: 3 * 3600 + 12 * 60, reason: .microphone)
        let model = PanelViewModel(
            phase: .headsUp,
            clock: ManualClock(now: SchedulerHarness.mondayMorning),
            startedAt: SchedulerHarness.mondayMorning,
            totalSeconds: 60
        )
        model.deferred = deferred
        XCTAssertEqual(model.deferredBadge, "Sitting for 3 h 12 m · break waited for your call")
    }

    // MARK: - Displays

    func testAScreenChangeMidBreakIsSomethingTheOverlayListensFor() throws {
        let source = try String(
            contentsOf: AccessibilityTests.repositoryRoot()
                .appendingPathComponent("Sources/movez/UI/Overlay/OverlayWindowController.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("didChangeScreenParametersNotification"))
        XCTAssertTrue(source.contains("rebuildForScreenChange"))
    }
}
