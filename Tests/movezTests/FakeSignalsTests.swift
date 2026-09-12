import XCTest
@testable import movez

@MainActor
final class FakeSignalsTests: XCTestCase {
    func testEveryInjectorProducesItsEvent() {
        let now = SchedulerHarness.mondayMorning
        XCTAssertEqual(SignalInjector.idleFour.event(now: now), .idle(seconds: 240))
        XCTAssertEqual(SignalInjector.idleSeven.event(now: now), .idle(seconds: 420))
        XCTAssertEqual(SignalInjector.sleep.event(now: now), .sleep)
        XCTAssertEqual(SignalInjector.wake.event(now: now), .wake(gapSeconds: 120))
        XCTAssertEqual(SignalInjector.wakeFiveHours.event(now: now), .wake(gapSeconds: 5 * 3600))
        XCTAssertEqual(SignalInjector.lock.event(now: now), .lock)
        XCTAssertEqual(SignalInjector.unlock.event(now: now), .unlock(gapSeconds: 15))
        XCTAssertEqual(SignalInjector.micOn.event(now: now), .signals(SignalSnapshot(microphoneActive: true)))
        XCTAssertEqual(SignalInjector.micOff.event(now: now), .signals(.quiet))
        XCTAssertEqual(SignalInjector.captureOn.event(now: now), .signals(SignalSnapshot(screenCaptureActive: true)))
        XCTAssertEqual(SignalInjector.fullscreenOn.event(now: now), .signals(SignalSnapshot(fullscreenActive: true)))
        XCTAssertEqual(SignalInjector.simulateFourHourGap.event(now: now), .wake(gapSeconds: 4 * 3600))
        XCTAssertNil(SignalInjector.fireMicro.event(now: now))
        XCTAssertEqual(SignalInjector.allCases.count, 16)
        XCTAssertFalse(SignalInjector.allCases.contains { $0.label.isEmpty })
    }

    func testInjectorsDriveTheSchedulerThroughTheCoordinator() {
        let harness = CoordinatorHarness()
        harness.run(seconds: 10 * 60)

        harness.coordinator.inject(.idle(seconds: 200))
        guard case .away = harness.state else { return XCTFail("idle 200 s should be away, got \(harness.state)") }
        harness.coordinator.inject(.input(lastEventAgeSeconds: 0))

        harness.coordinator.inject(.signals(SignalSnapshot(microphoneActive: true)))
        guard case .suppressed = harness.state else { return XCTFail("mic on should suppress") }
        harness.coordinator.inject(.signals(.quiet))
        guard case .postBreakGrace = harness.state else { return XCTFail("mic off starts the grace") }

        harness.run(seconds: 130)
        harness.coordinator.inject(.sleep)
        guard case .away = harness.state else { return XCTFail("sleep should park in away") }

        harness.coordinator.inject(.wake(gapSeconds: 120))
        guard case .postBreakGrace = harness.state else { return XCTFail("wake starts the quiet minute") }
    }

    func testFakeSourcesHonourTheExceptionList() {
        let fullscreen = FakeFullscreenSource()
        fullscreen.isFullscreen = true
        fullscreen.bundleId = "com.apple.Keynote"
        XCTAssertTrue(fullscreen.reading(exceptions: []).isFullscreen)
        XCTAssertFalse(fullscreen.reading(exceptions: ["com.apple.Keynote"]).isFullscreen)

        let idle = FakeIdleSource()
        idle.seconds = 12
        XCTAssertEqual(idle.idleSeconds(), 12)
    }
}
