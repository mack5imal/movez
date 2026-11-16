import XCTest
@testable import movez

@MainActor
final class SignalAggregatorTests: XCTestCase {
    private struct Fakes {
        var aggregator: SignalAggregator
        var idle: FakeIdleSource
        var mic: FakeMicSource
        var capture: FakeCaptureSource
        var fullscreen: FakeFullscreenSource
    }

    private func makeAggregator(harness: CoordinatorHarness) -> Fakes {
        let idle = FakeIdleSource()
        let mic = FakeMicSource()
        let capture = FakeCaptureSource()
        let fullscreen = FakeFullscreenSource()
        let aggregator = SignalAggregator(
            idle: idle,
            mic: mic,
            capture: capture,
            fullscreen: fullscreen,
            clock: harness.clock,
            settings: harness.settings,
            dispatch: { [weak harness] event in harness?.coordinator.inject(event) }
        )
        return Fakes(aggregator: aggregator, idle: idle, mic: mic, capture: capture, fullscreen: fullscreen)
    }

    /// Polls by hand on the manual clock, the way the timer would while it runs. Whether it runs
    /// at all is the coordinator's job, asserted through `isRunning` below, not skipped here.
    private func poll(_ aggregator: SignalAggregator, harness: CoordinatorHarness, seconds: TimeInterval) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            harness.clock.advance(SignalAggregator.pollSeconds)
            elapsed += SignalAggregator.pollSeconds
            aggregator.poll()
        }
    }

    /// At 1× the timer polls every two seconds. The cadence is a property of the timer, so it is
    /// checked there rather than by counting a loop the test itself runs.
    func testPollsEveryTwoSecondsWhileSitting() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let aggregator = makeAggregator(harness: harness).aggregator
        harness.coordinator.aggregator = aggregator
        aggregator.setPolling(true)
        XCTAssertTrue(aggregator.isRunning)
        XCTAssertEqual(aggregator.pollInterval, SignalAggregator.pollSeconds)
        XCTAssertEqual(SignalAggregator.pollSeconds, 2)
    }

    /// What keeps movez from sampling anything while paused or off hours is the coordinator
    /// stopping the aggregator, so that is what is asserted: the timer stops when the working day
    /// closes and starts again when the next one opens.
    func testNoPollsWhilePausedOrOffHours() {
        let paused = CoordinatorHarness(workingHours: .alwaysOn)
        let pausedAggregator = makeAggregator(harness: paused).aggregator
        paused.coordinator.aggregator = pausedAggregator
        pausedAggregator.setPolling(true)
        paused.coordinator.pause(forSeconds: 2 * 3600)
        XCTAssertFalse(paused.scheduler.pollingRequired)
        XCTAssertFalse(pausedAggregator.isRunning, "a paused movez samples nothing")

        let closing = Calendar.current.date(byAdding: .minute, value: 9 * 60 - 2, to: SchedulerHarness.mondayMorning)
        let evening = CoordinatorHarness(startAt: closing ?? SchedulerHarness.mondayMorning)
        let eveningAggregator = makeAggregator(harness: evening).aggregator
        evening.coordinator.aggregator = eveningAggregator
        eveningAggregator.setPolling(true)
        evening.run(seconds: 4)
        XCTAssertTrue(eveningAggregator.isRunning, "17:58 on a Monday is working hours")

        evening.run(seconds: 4 * 60)
        XCTAssertEqual(evening.state, .offHours)
        XCTAssertFalse(eveningAggregator.isRunning, "the working day closing stops the polling")

        evening.run(seconds: 15 * 3600)
        XCTAssertNotEqual(evening.state, .offHours, "09:00 on Tuesday opens the next working day")
        XCTAssertTrue(eveningAggregator.isRunning, "and the polling starts again with it")
    }

    func testSettingsVetoEachSignal() {
        let harness = CoordinatorHarness()
        let fakes = makeAggregator(harness: harness)
        let (aggregator, idle, mic, capture, fullscreen) = (fakes.aggregator, fakes.idle, fakes.mic, fakes.capture, fakes.fullscreen)
        idle.seconds = 42
        mic.inUse = true
        capture.captured = true
        fullscreen.isFullscreen = true
        fullscreen.bundleId = "com.apple.Keynote"

        var snapshot = aggregator.read(now: harness.now)
        XCTAssertEqual(snapshot.idleSeconds, 42)
        XCTAssertTrue(snapshot.suppressing)
        XCTAssertEqual(snapshot.frontmostBundleId, "com.apple.Keynote")

        harness.settings.suppressMic = false
        harness.settings.suppressCapture = false
        harness.settings.suppressFullscreen = false
        snapshot = aggregator.read(now: harness.now)
        XCTAssertFalse(snapshot.suppressing, "a signal the user turned off never suppresses")

        harness.settings.suppressFullscreen = true
        harness.settings.fullscreenExceptions = ["com.apple.Keynote"]
        XCTAssertFalse(aggregator.read(now: harness.now).fullscreenActive, "an excepted app never suppresses")
    }

    func testATwelveSecondGapSynthesisesAWake() {
        let harness = CoordinatorHarness()
        let aggregator = makeAggregator(harness: harness).aggregator
        aggregator.poll()

        harness.clock.advance(12)
        aggregator.poll()

        let gapEvents = harness.scheduler.snapshot.transitions.transitions.filter { $0.reason.contains("tick gap") }
        XCTAssertEqual(gapEvents.count, 1, "a long gap between polls is treated as a wake")
        XCTAssertTrue(gapEvents[0].reason.contains("12"))
    }

    func testARealWakeStopsTheSynthesisedOne() {
        let harness = CoordinatorHarness()
        let aggregator = makeAggregator(harness: harness).aggregator
        aggregator.poll()

        harness.clock.advance(12)
        aggregator.noteRealWake(at: harness.now)
        aggregator.poll()

        let gapEvents = harness.scheduler.snapshot.transitions.transitions.filter { $0.reason.contains("tick gap") }
        XCTAssertTrue(gapEvents.isEmpty, "the real notification already covered it")
    }

    // MARK: - The microphone has to hold

    /// Dictation holds the mic for a few seconds at a time, and every one of those bursts used to
    /// defer breaks for the burst plus a two-minute grace.
    func testAShortMicrophoneBurstNeverSuppresses() {
        let harness = CoordinatorHarness()
        let fakes = makeAggregator(harness: harness)

        fakes.mic.inUse = true
        poll(fakes.aggregator, harness: harness, seconds: 30)
        XCTAssertFalse(fakes.aggregator.lastSnapshot.microphoneActive, "half a minute is a sentence, not a call")
        XCTAssertEqual(harness.state.name, "sitting")

        fakes.mic.inUse = false
        poll(fakes.aggregator, harness: harness, seconds: 4)
        XCTAssertEqual(harness.state.name, "sitting", "and nothing was deferred on the way out")
    }

    func testAMicrophoneHeldForAMinuteSuppresses() {
        let harness = CoordinatorHarness()
        let fakes = makeAggregator(harness: harness)

        fakes.mic.inUse = true
        poll(fakes.aggregator, harness: harness, seconds: SignalAggregator.micSustainSeconds + 2)
        XCTAssertTrue(fakes.aggregator.lastSnapshot.microphoneActive)
        XCTAssertEqual(harness.state.name, "suppressed", "a call outlasts a minute")
    }

    /// Two bursts either side of a quiet poll are two bursts, not one long call.
    func testTheMinuteStartsAgainWheneverTheMicrophoneDropsOut() {
        let harness = CoordinatorHarness()
        let fakes = makeAggregator(harness: harness)

        fakes.mic.inUse = true
        poll(fakes.aggregator, harness: harness, seconds: 40)
        fakes.mic.inUse = false
        poll(fakes.aggregator, harness: harness, seconds: 2)
        fakes.mic.inUse = true
        poll(fakes.aggregator, harness: harness, seconds: 40)

        XCTAssertFalse(fakes.aggregator.lastSnapshot.microphoneActive, "eighty seconds, but never sixty in a row")
        XCTAssertEqual(harness.state.name, "sitting")
    }

    func testAScreenShareStillSuppressesOnTheFirstReading() {
        let harness = CoordinatorHarness()
        let fakes = makeAggregator(harness: harness)

        fakes.capture.captured = true
        poll(fakes.aggregator, harness: harness, seconds: 2)
        XCTAssertEqual(harness.state.name, "suppressed", "a share means what it says at once")
    }

    func testPollingFollowsTheSchedulersRequirement() {
        let harness = CoordinatorHarness()
        let aggregator = makeAggregator(harness: harness).aggregator
        aggregator.setPolling(true)
        XCTAssertTrue(aggregator.isRunning)
        aggregator.setPolling(false)
        XCTAssertFalse(aggregator.isRunning)
        aggregator.stop()
    }
}
