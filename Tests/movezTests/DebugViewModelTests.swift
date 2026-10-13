import XCTest
@testable import movez

@MainActor
final class DebugViewModelTests: XCTestCase {
    private func harness() -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn)
    }

    private func debug(_ harness: CoordinatorHarness) -> DebugViewModel {
        DebugViewModel(coordinator: harness.coordinator)
    }

    /// The reasons in the transition log, oldest first.
    private func reasons(_ harness: CoordinatorHarness) -> [String] {
        harness.scheduler.snapshot.transitions.transitions.map(\.reason)
    }

    private func states(_ harness: CoordinatorHarness) -> [String] {
        harness.scheduler.snapshot.transitions.transitions.map(\.to.name)
    }

    // MARK: - Time scale

    func testTheTimeScaleReachesTheClockAndThePollingInterval() {
        let harness = harness()
        let aggregator = SignalAggregator(
            idle: FakeIdleSource(),
            mic: FakeMicSource(),
            capture: FakeCaptureSource(),
            fullscreen: FakeFullscreenSource(),
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { _ in }
        )
        harness.coordinator.aggregator = aggregator
        XCTAssertEqual(aggregator.pollInterval, 2, accuracy: 0.001)

        debug(harness).setTimeScale(60)

        XCTAssertEqual(harness.settings.debugTimeScale, 60)
        XCTAssertEqual(
            aggregator.pollInterval,
            SignalAggregator.minimumPollSeconds,
            accuracy: 0.001,
            "2 / 60 s is below the floor, so the floor is what it polls at"
        )
    }

    /// The one test that has to run in real time: sixty times means the countdown visibly moves
    /// while you watch it.
    func testSixtyTimesMovesTheCountdownWithinASecondOfRealTime() {
        let clock = SystemClock()
        let suite = ScratchDefaults.make()
        let settings = SettingsStore(defaults: suite)
        settings.workingHours = .alwaysOn
        let coordinator = AppCoordinator(
            library: RoutineTestSupport.library,
            settings: settings,
            history: HistoryStore(),
            clock: clock,
            sink: RecordingEffectSink()
        )
        let menu = MenuBarViewModel(coordinator: coordinator)
        let before = menu.state.minutesRemaining
        XCTAssertEqual(before, 55)

        DebugViewModel(coordinator: coordinator).setTimeScale(60)
        XCTAssertEqual(clock.timeScale, 60)

        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        coordinator.tick()
        menu.refresh()

        XCTAssertLessThanOrEqual(
            menu.state.minutesRemaining,
            before - 1,
            "1.2 real seconds is over a scaled minute"
        )
    }

    // MARK: - Injectors

    func testSevenMinutesIdleGoesAwayAndResetsOnTheNextKeystroke() {
        let harness = harness()
        debug(harness).fire(.idleSeven)
        XCTAssertEqual(harness.state.name, "away")

        harness.coordinator.report(inputAgeSeconds: 0)
        XCTAssertEqual(harness.state.name, "sitting")
        XCTAssertTrue(
            reasons(harness).contains { $0.contains("countdowns reset") },
            reasons(harness).joined(separator: " | ")
        )
        XCTAssertEqual(harness.coordinator.toastInfo?.behaviour, .reset)
    }

    /// Four minutes and seven are the same kind of absence now: past the threshold is past it.
    func testFourMinutesIdleIsTheSameAsSeven() {
        let harness = harness()
        debug(harness).fire(.idleFour)
        harness.coordinator.report(inputAgeSeconds: 0)
        XCTAssertEqual(harness.coordinator.toastInfo?.behaviour, .reset)
        XCTAssertEqual(harness.coordinator.toastInfo?.awaySeconds, 240)
    }

    func testMicOnSuppressesAndMicOffOpensTheGrace() {
        let harness = harness()
        let debug = debug(harness)

        debug.fire(.micOn)
        XCTAssertEqual(harness.state.name, "suppressed")
        XCTAssertEqual(harness.coordinator.signalOverrides.micInUse, true, "held on until it is switched off")

        debug.fire(.micOff)
        XCTAssertEqual(harness.state.name, "post_break_grace")
        XCTAssertNil(harness.coordinator.signalOverrides.micInUse)
        XCTAssertEqual(harness.coordinator.signalOverrides.summary, "none")
    }

    func testAHeldSignalSurvivesThePollThatFollowsIt() {
        let harness = harness()
        let overrides = harness.coordinator.signalOverrides
        let aggregator = SignalAggregator(
            idle: FakeIdleSource(),
            mic: OverridingMicSource(FakeMicSource(), overrides: overrides),
            capture: FakeCaptureSource(),
            fullscreen: FakeFullscreenSource(),
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { _ in }
        )

        debug(harness).fire(.micOn)
        XCTAssertTrue(
            aggregator.read(now: harness.now).microphoneActive,
            "an injected signal that a poll undoes proves nothing"
        )
    }

    func testSleepTakesEverySurfaceDownAndGoesAway() {
        let harness = harness()
        harness.sink.clear()

        debug(harness).fire(.sleep)

        XCTAssertEqual(harness.state.name, "away")
        XCTAssertTrue(harness.sink.names.contains("hideHeadsUp"), harness.sink.names.joined(separator: ","))
        XCTAssertTrue(harness.sink.names.contains("hideMicro"))
    }

    func testCaptureAndFullscreenSuppressTheSameWay() {
        for injector in [SignalInjector.captureOn, .fullscreenOn] {
            let harness = harness()
            debug(harness).fire(injector)
            XCTAssertEqual(harness.state.name, "suppressed", injector.label)
        }
    }

    func testFireFullBreakSkipsStraightPastTheHeadsUp() {
        let harness = harness()
        debug(harness).fire(.fireFullBreak)
        XCTAssertEqual(harness.state.name, "full_break")
        XCTAssertFalse(states(harness).contains("heads_up"))
    }

    func testFireMicroStartsTheCountIn() {
        let harness = harness()
        debug(harness).fire(.fireMicro)
        XCTAssertEqual(harness.state.name, "micro_count_in")
        XCTAssertNotNil(harness.coordinator.currentMicro)
    }

    func testAFourHourGapIsStandby() {
        let harness = harness()
        harness.coordinator.scheduler.snapshot.skipsToday = 1
        debug(harness).fire(.simulateFourHourGap)
        XCTAssertEqual(harness.state.name, "post_break_grace", "a wake is quiet for a minute first")

        harness.run(seconds: 90)
        XCTAssertTrue(
            reasons(harness).contains { $0.contains("standby") },
            reasons(harness).joined(separator: " | ")
        )
        XCTAssertEqual(harness.scheduler.snapshot.skipsToday, 1, "the day's counters are the day's, not the session's")
    }

    // MARK: - The inspector

    func testTheInspectorNamesEveryFieldItShows() {
        let harness = harness()
        let debug = debug(harness)
        debug.fire(.micOn)
        let text = debug.state.inspectorText
        for label in DebugViewModel.Field.all {
            XCTAssertTrue(text.contains(label), "missing \(label)")
        }
        XCTAssertTrue(text.contains(DebugState.transitionsHeading))
    }

    func testTheInspectorReadsNewestFirstAndStopsAtTwenty() {
        let harness = harness()
        let debug = debug(harness)

        // Twelve full cycles is well past the log's twenty entries.
        for _ in 0..<12 {
            debug.fire(.micOn)
            debug.fire(.micOff)
            harness.run(seconds: 130)
        }
        // The view model refreshes off the coordinator asynchronously; ticks driven by hand need
        // to be picked up by hand.
        debug.refresh()

        XCTAssertEqual(debug.state.transitions.count, TransitionLog.capacity)
        let newest = harness.scheduler.snapshot.transitions.transitions.last
        XCTAssertEqual(debug.state.transitions.first, newest?.line(formatter: TransitionLog.timeFormatter))
    }

    func testTheInspectorReportsWhatTheSchedulerIsHolding() {
        let harness = harness()
        let debug = debug(harness)
        debug.fire(.micOn)

        let rows = Dictionary(uniqueKeysWithValues: debug.state.rows.map { ($0.label, $0.value) })
        XCTAssertEqual(rows[DebugViewModel.Field.state], "suppressed")
        XCTAssertEqual(rows[DebugViewModel.Field.overrides], "mic=on")
        XCTAssertEqual(rows[DebugViewModel.Field.polling], "on")
        XCTAssertEqual(rows[DebugViewModel.Field.snoozesLeft], "2")
        XCTAssertTrue(rows[DebugViewModel.Field.nextFullDueAt]?.contains("in 55 min") ?? false)
    }

    /// Writes the evidence the phase asks for: the inspector after three injectors.
    func testWritesAnInspectorSample() throws {
        let harness = harness()
        let debug = debug(harness)

        debug.fire(.micOn)
        debug.fire(.micOff)
        debug.fire(.fireFullBreak)

        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/inspector-sample.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try debug.state.inspectorText.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(debug.state.inspectorText.contains("suppressed"))
    }

    // MARK: - The disclosure

    func testTheDisclosureIsClosedByDefaultAndRemembersBeingOpened() {
        let suite = ScratchDefaults.make()

        let first = SettingsStore(defaults: suite)
        XCTAssertFalse(first.debugExpanded, "debug tools are not what the window is for")
        first.debugExpanded = true

        let reloaded = SettingsStore(defaults: suite)
        XCTAssertTrue(reloaded.debugExpanded)
    }

    func testTheSectionOffersThreeSpeedsAndEveryInjector() {
        XCTAssertEqual(DebugState.timeScales, [1, 10, 60])
        XCTAssertEqual(DebugState.timeScaleOptions.map(\.label), ["1×", "10×", "60×"])
        XCTAssertEqual(DebugState.schedulerActions.map(\.label), [
            "Fire full break now", "Fire micro now", "Simulate 4 h gap"
        ])
        XCTAssertEqual(DebugState.signalInjectors.count, SignalInjector.allCases.count - 3)
        XCTAssertTrue(DebugState.signalInjectors.contains(.idleSeven))
    }
}
