import XCTest
@testable import movez

final class SchedulerMicroTests: XCTestCase {
    private let minute: TimeInterval = 60

    private func microTimes(preset: PresetId, customMinutes: Int? = nil, within: TimeInterval) -> [TimeInterval] {
        let config = SchedulerConfig.from(preset: preset, customSitMinutes: customMinutes)
        let harness = SchedulerHarness(config: config)
        let start = harness.start
        var fired: [TimeInterval] = []
        var elapsed: TimeInterval = 0

        while elapsed < within {
            harness.clock.advance(SchedulerHarness.tickSeconds)
            elapsed += SchedulerHarness.tickSeconds
            for effect in harness.send(.tick) {
                if case .showMicroCountIn = effect { fired.append(harness.now.timeIntervalSince(start)) }
            }
            if harness.state.isMicroCountIn { harness.send(.userMicroStartNow) }
            if harness.state.isMicroRunning { harness.clock.advance(60); harness.send(.tick) }
            if harness.state.isPendingFull { break }
        }
        return fired
    }

    func testMicroCadencePerPreset() {
        XCTAssertEqual(microTimes(preset: .fiftyFiveFive, within: 60 * minute).map { Int($0 / 60) }, [30])
        XCTAssertEqual(microTimes(preset: .eightyFiveFive, within: 90 * minute).map { Int($0 / 60) }, [30, 60])
        XCTAssertEqual(microTimes(preset: .twentyFiveFive, within: 30 * minute), [])
        XCTAssertEqual(microTimes(preset: .custom, customMinutes: 45, within: 50 * minute).map { Int($0 / 60) }, [30])
        XCTAssertEqual(microTimes(preset: .custom, customMinutes: 35, within: 40 * minute), [])
    }

    func testTwentyFiveFiveNeverEnablesMicroBreaks() {
        let config = SchedulerConfig.from(preset: .twentyFiveFive, microOn: true)
        XCTAssertFalse(config.microEnabled, "25/5 bouts are already short enough")
        XCTAssertEqual(config.sitSeconds, 25 * 60)
    }

    func testCustomPresetIsClampedAndStepped() {
        XCTAssertEqual(SchedulerConfig.clampCustom(3), 15)
        XCTAssertEqual(SchedulerConfig.clampCustom(200), 120)
        XCTAssertEqual(SchedulerConfig.clampCustom(47), 45)
        XCTAssertFalse(SchedulerConfig.from(preset: .custom, customSitMinutes: 40, microOn: true).microEnabled)
        XCTAssertTrue(SchedulerConfig.from(preset: .custom, customSitMinutes: 45, microOn: true).microEnabled)
    }

    func testCountInBecomesTheRunningMicroThenEnds() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        XCTAssertTrue(harness.state.isMicroCountIn)
        XCTAssertTrue(harness.effectNames.contains("showMicroCountIn"))

        harness.run(until: { $0.isMicroRunning })
        XCTAssertTrue(harness.state.isMicroRunning)

        harness.clearEffects()
        harness.run(until: { $0.isSitting })
        XCTAssertTrue(harness.effectNames.contains("hideMicro"))
        XCTAssertEqual(harness.snapshot.microEmphasisIndex, 1)
    }

    func testMicroSnoozeOnceThenSkip() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        let originalAnchor = harness.snapshot.microAnchorAt
        XCTAssertNotNil(originalAnchor)

        harness.send(.userMicroSnooze)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, harness.now.addingTimeInterval(5 * minute))
        XCTAssertTrue(harness.snapshot.microSnoozeUsed)

        harness.run(until: { $0.isMicroCountIn })
        XCTAssertTrue(harness.state.isMicroCountIn)
        XCTAssertEqual(harness.snapshot.microAnchorAt, originalAnchor, "the snooze keeps the original anchor")

        harness.send(.userMicroSnooze)
        XCTAssertTrue(harness.state.isSitting)
        // 55/5: the next micro would be anchor + 30 min, which lands inside the quiet zone before
        // the full break, so it is dropped rather than served.
        XCTAssertNil(harness.snapshot.nextMicroDueAt)
        XCTAssertFalse(harness.snapshot.microSnoozeUsed)
    }

    func testMicroSkipReAnchorsToTheOriginalStart() {
        let config = SchedulerConfig.from(preset: .eightyFiveFive)
        let harness = SchedulerHarness(config: config)
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        let anchor = harness.snapshot.microAnchorAt

        harness.clock.advance(20)
        harness.send(.userMicroSkip)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, anchor?.addingTimeInterval(30 * minute))
    }

    func testMicroDueDuringHeadsUpIsDropped() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.scheduler.snapshot.nextMicroDueAt = harness.now.addingTimeInterval(-60)
        harness.clearEffects()
        harness.run(seconds: 10)
        XCTAssertFalse(harness.effectNames.contains("showMicroCountIn"))
        XCTAssertTrue(harness.state.isHeadsUp || harness.state.isFullBreak)
    }
}
