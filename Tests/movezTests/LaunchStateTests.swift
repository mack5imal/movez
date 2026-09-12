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
        SettingsStore(defaults: UserDefaults(suiteName: "movez.tests.\(UUID().uuidString)") ?? .standard)
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
        XCTAssertEqual(library?.version, "4")
        XCTAssertEqual(library?.movements.count, 147)
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
