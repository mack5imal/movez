import XCTest
@testable import movez

/// Settings apply to the session already running. Nothing here may cost the user the time they
/// have already sat.
@MainActor
final class SettingsLiveUpdateTests: XCTestCase {
    private func harness() -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn)
    }

    private func viewModel(_ harness: CoordinatorHarness) -> SettingsViewModel {
        SettingsViewModel(
            settings: harness.settings,
            library: RoutineTestSupport.library,
            launchAtLogin: FakeLaunchAtLogin(),
            onChange: { [coordinator = harness.coordinator] in coordinator.settingsChanged() }
        )
    }

    func testChangingThePresetMidBoutKeepsTheBoutButRePlansTheBreak() {
        let harness = harness()
        let settings = viewModel(harness)
        let boutStart = harness.scheduler.snapshot.boutStartedAt

        harness.run(seconds: 20 * 60)
        settings.setPreset(.eightyFiveFive)

        XCTAssertEqual(harness.scheduler.snapshot.boutStartedAt, boutStart, "the bout is not restarted")
        let due = harness.scheduler.snapshot.nextFullDueAt ?? .distantPast
        XCTAssertEqual(
            due.timeIntervalSince(boutStart),
            85 * 60,
            accuracy: 2,
            "the break is re-planned from the bout that is already running"
        )
    }

    func testEverySettingLeavesTheBoutWhereItWas() {
        let harness = harness()
        let settings = viewModel(harness)
        harness.run(seconds: 12 * 60)
        let boutStart = harness.scheduler.snapshot.boutStartedAt

        settings.setFocus(.moreHips)
        settings.setDifficultyCap(3)
        settings.toggleEquipment(.band)
        settings.setAwayMinutes(6)
        settings.setSounds(false)
        settings.setMicroEnabled(false)

        XCTAssertEqual(harness.scheduler.snapshot.boutStartedAt, boutStart)
    }

    func testTheAwayThresholdReachesTheScheduler() {
        let harness = harness()
        let settings = viewModel(harness)
        XCTAssertEqual(harness.settings.schedulerConfig.awayThresholdSeconds, 180)

        settings.setAwayMinutes(6)
        harness.sink.clear()
        harness.run(seconds: 4)

        // Five minutes away is under the new six-minute threshold, so nothing is credited.
        harness.coordinator.inject(.idle(seconds: 5 * 60))
        XCTAssertEqual(harness.state.name, "sitting", "not away yet at the new threshold")

        harness.coordinator.inject(.idle(seconds: 7 * 60))
        XCTAssertEqual(harness.state.name, "away")
    }

    func testTheDifficultyCapReachesTheNextRoutineTheCoordinatorBuilds() {
        let harness = harness()
        let settings = viewModel(harness)

        settings.setDifficultyCap(1)
        let context = harness.coordinator.routineContext(at: harness.now, breakIndex: 0)
        XCTAssertEqual(context.difficultyCap, 1)

        let routine = RoutineTestSupport.builder.build(context: context)
        XCTAssertTrue(routine.blocks.allSatisfy { $0.movement.difficulty <= 1 }, routine.movementIds.joined())
    }

    func testAnExcludedMovementNeverReachesABreak() {
        let harness = harness()
        let settings = viewModel(harness)
        let first = harness.coordinator.nextRoutine(at: harness.now)
        let victim = first.movementIds[0]

        settings.setExcluded(victim, true)
        harness.coordinator.invalidatePreview()

        let rebuilt = harness.coordinator.nextRoutine(at: harness.now)
        XCTAssertFalse(rebuilt.movementIds.contains(victim))
    }

    /// The aggregator reads the toggles on every poll, so switching one off silences that signal
    /// on the very next sample rather than at the next launch.
    func testTurningOffTheMicToggleSilencesTheSignalOnTheNextPoll() {
        let harness = harness()
        let settings = viewModel(harness)

        let mic = FakeMicSource()
        mic.inUse = true
        let aggregator = SignalAggregator(
            idle: FakeIdleSource(),
            mic: mic,
            capture: FakeCaptureSource(),
            fullscreen: FakeFullscreenSource(),
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { _ in }
        )

        XCTAssertTrue(aggregator.read(now: harness.now).microphoneActive)

        settings.setSuppressMic(false)
        XCTAssertFalse(
            aggregator.read(now: harness.now).microphoneActive,
            "the mic is still in use; movez has simply stopped caring"
        )
    }

    func testAFullscreenExceptionStopsThatAppSuppressingBreaks() {
        let harness = harness()
        let settings = viewModel(harness)

        let fullscreen = FakeFullscreenSource()
        fullscreen.isFullscreen = true
        fullscreen.bundleId = "com.apple.iWork.Keynote"
        let aggregator = SignalAggregator(
            idle: FakeIdleSource(),
            mic: FakeMicSource(),
            capture: FakeCaptureSource(),
            fullscreen: fullscreen,
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { _ in }
        )

        XCTAssertTrue(aggregator.read(now: harness.now).fullscreenActive)

        settings.addException("com.apple.iWork.Keynote")
        XCTAssertFalse(aggregator.read(now: harness.now).fullscreenActive)
    }

    func testWorkingHoursEditedInTheSheetReachTheScheduler() {
        let harness = harness()
        let settings = viewModel(harness)

        settings.beginEditingHours()
        settings.hoursDraft = .standard
        settings.hoursDraft.days[5].endMinutes = 13 * 60
        settings.applyHours()

        XCTAssertEqual(harness.settings.workingHours.days[5].endMinutes, 13 * 60)
        XCTAssertEqual(
            harness.coordinator.scheduler.snapshot.configHash,
            harness.settings.schedulerConfig.stableHash,
            "the scheduler is holding the config the settings now describe"
        )
    }
}
