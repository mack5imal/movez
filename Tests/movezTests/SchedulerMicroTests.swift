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

    // MARK: - A micro-break on screen

    /// A call that starts while the micro-break is up used to take it down, and the re-anchor then
    /// landed inside the quiet zone before the full break, where a micro-break is dropped — so the
    /// user lost it altogether. What is on screen is seconds from over; it is allowed to finish.
    func testSignalsDoNotInterruptAMicroBreakAlreadyOnScreen() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)

        XCTAssertEqual(harness.send(.signals(SignalSnapshot(microphoneActive: true))), [])
        XCTAssertTrue(harness.state.isMicroCountIn)

        harness.run(until: { $0.isMicroRunning })
        XCTAssertEqual(harness.send(.signals(SignalSnapshot(microphoneActive: true))), [])
        XCTAssertTrue(harness.state.isMicroRunning)

        harness.run(until: { $0.isSitting })
        XCTAssertNotNil(harness.snapshot.nextMicroDueAt ?? harness.snapshot.nextFullDueAt)

        // Only once it is over does the call take hold.
        harness.send(.signals(SignalSnapshot(microphoneActive: true)))
        XCTAssertEqual(harness.state.name, "suppressed")
    }

    // MARK: - What reaches history

    private func ranSeconds(_ harness: SchedulerHarness) -> [Int] {
        harness.effects.compactMap { effect in
            if case .recordMicroDone(let seconds) = effect { return seconds } else { return nil }
        }
    }

    func testAMicroBreakThatRanItsMinuteIsRecorded() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        harness.clearEffects()

        harness.run(until: { $0.isSitting })
        // The backstop is the longest micro-break, 65 s, reached on the first two-second tick past it.
        XCTAssertEqual(ranSeconds(harness), [66])
    }

    /// A micro-break that runs its course ends on the completion chime a full break ends on.
    func testAMicroBreakThatRanToTheEndChimes() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        harness.clock.advance(60)
        harness.clearEffects()

        // The panel ends a single-movement micro-break at sixty seconds.
        harness.send(.microEnded)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.effects.filter { $0 == .chime(.completion) }.count, 1)
    }

    func testSkippingSnoozingOrNeverStartingIsQuiet() {
        let skipped = SchedulerHarness()
        skipped.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        skipped.clock.advance(40)
        skipped.clearEffects()
        skipped.send(.userMicroSkip)
        XCTAssertFalse(skipped.effects.contains(.chime(.completion)), "a skip is not a finish")

        let snoozed = SchedulerHarness()
        snoozed.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        snoozed.clearEffects()
        snoozed.send(.userMicroSnooze)
        XCTAssertFalse(snoozed.effects.contains(.chime(.completion)))

        let countIn = SchedulerHarness()
        countIn.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        countIn.clearEffects()
        countIn.send(.microEnded)
        XCTAssertFalse(countIn.effects.contains(.chime(.completion)), "nothing was done during a count-in")
    }

    func testAMicroBreakSkippedPastHalfItsLengthIsRecorded() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        harness.clock.advance(35)
        harness.clearEffects()

        harness.send(.userMicroSkip)
        XCTAssertEqual(ranSeconds(harness), [35], "half the minute is the full break's rule too")
    }

    /// The count-in is not the micro-break: nothing has been asked of the user yet. Recording it
    /// put movements nobody did into history, where they weighed themselves down for three days.
    func testACountInThatNeverStartedRecordsNothing() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute)
        harness.clearEffects()

        harness.send(.userMicroSkip)
        XCTAssertEqual(ranSeconds(harness), [])
        XCTAssertTrue(harness.effectNames.contains("hideMicro"), "the panel still comes down")
    }

    func testAMicroBreakSkippedAtOnceRecordsNothing() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        harness.clock.advance(2)
        harness.clearEffects()

        harness.send(.userMicroSkip)
        XCTAssertEqual(ranSeconds(harness), [])
    }

    /// Idle, sleep and a pause all take the panel down through `dismissSurfaces`, and are judged on
    /// the same rule rather than never being recorded at all.
    func testAnIdleStretchRecordsAMicroBreakThatHadAlreadyRun() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isMicroRunning }, limit: 40 * minute)
        harness.clock.advance(40)
        harness.clearEffects()

        harness.send(.idle(seconds: 5 * Int(minute)))
        XCTAssertEqual(ranSeconds(harness), [40])
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
