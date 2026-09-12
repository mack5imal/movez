import XCTest
@testable import movez

final class SchedulerCoreTests: XCTestCase {
    private let minute: TimeInterval = 60

    // MARK: - The core cycle

    func testSittingToPendingToHeadsUpToBreak() {
        let harness = SchedulerHarness()
        let start = harness.start
        XCTAssertEqual(harness.snapshot.nextFullDueAt, start.addingTimeInterval(55 * minute))

        harness.run(until: { $0.isPendingFull })
        XCTAssertTrue(harness.state.isPendingFull)
        XCTAssertLessThan(abs(harness.now.timeIntervalSince(start) - 55 * minute), 2)

        harness.clearEffects()
        harness.send(.input(lastEventAgeSeconds: 12))
        XCTAssertTrue(harness.state.isHeadsUp)
        XCTAssertTrue(harness.effectNames.contains("showHeadsUp"))
        XCTAssertTrue(harness.effectNames.contains("chime(headsUp)"))

        let headsUpAt = harness.now
        harness.clearEffects()
        harness.run(until: { $0.isFullBreak })
        XCTAssertTrue(harness.state.isFullBreak)
        XCTAssertLessThan(abs(harness.now.timeIntervalSince(headsUpAt) - 60), 2.5)
        XCTAssertTrue(harness.effectNames.contains("startFullBreak"))
        XCTAssertTrue(harness.effectNames.contains("hideHeadsUp"))
    }

    func testContinuousInputCapsTheWaitAtSixtySeconds() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isPendingFull })
        let dueAt = harness.now

        harness.run(seconds: 90, inputAge: 1)
        XCTAssertTrue(harness.state.isHeadsUp || harness.state.isFullBreak)

        let headsUp = harness.snapshot.transitions.transitions.first { $0.to.isHeadsUp }
        let elapsed = try? XCTUnwrap(headsUp).at.timeIntervalSince(dueAt)
        XCTAssertNotNil(elapsed)
        XCTAssertLessThanOrEqual(abs((elapsed ?? 0) - 60), 2, "heads-up should fire at due + 60 s")
    }

    func testCompletionAnchorsTheNextBreakToTheEnd() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isPendingFull })
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.run(until: { $0.isFullBreak })

        harness.clock.advance(4 * minute)
        let endedAt = harness.now
        harness.clearEffects()
        harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 240))

        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, endedAt.addingTimeInterval(55 * minute))
        XCTAssertEqual(harness.snapshot.nextMicroDueAt, endedAt.addingTimeInterval(30 * minute))
        XCTAssertEqual(harness.snapshot.boutStartedAt, endedAt)
        XCTAssertEqual(harness.snapshot.doneToday, 1)
        XCTAssertTrue(harness.effectNames.contains("chime(completion)"))
    }

    // MARK: - Snooze

    func testSnoozeReturnsThroughHeadsUpAndIsCapped() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        XCTAssertTrue(harness.state.isHeadsUp)

        harness.clock.advance(4)
        harness.send(.userSnooze)
        guard case .snoozed(let until) = harness.state else { return XCTFail("expected snoozed, got \(harness.state)") }
        XCTAssertEqual(until, harness.now.addingTimeInterval(5 * minute))
        XCTAssertEqual(harness.snapshot.snoozedToday, 1)

        harness.run(until: { $0.isHeadsUp })
        XCTAssertTrue(harness.state.isHeadsUp, "a snooze comes back through the heads-up, not the overlay")

        harness.clock.advance(4)
        harness.send(.userSnooze)
        XCTAssertTrue(harness.state.isSnoozed)
        XCTAssertEqual(harness.snapshot.snoozedToday, 2)

        harness.run(until: { $0.isHeadsUp })
        harness.clock.advance(4)
        let before = harness.state
        let effects = harness.send(.userSnooze)
        XCTAssertEqual(effects, [], "a third snooze is refused")
        XCTAssertEqual(harness.state, before)
        XCTAssertEqual(harness.snapshot.snoozedToday, 2)
        XCTAssertEqual(harness.scheduler.snoozesLeft, 0)
    }

    // MARK: - Skip

    func testSkipIsBlockedForThreeSecondsThenReschedules() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        let boutStart = harness.snapshot.boutStartedAt

        XCTAssertEqual(harness.send(.userSkip), [], "skip is inert for the first 3 s")
        XCTAssertTrue(harness.state.isHeadsUp)
        XCTAssertEqual(harness.snapshot.skipsToday, 0)

        harness.clock.advance(4)
        harness.send(.userSkip)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.skipsToday, 1)
        XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(55 * minute))
        XCTAssertEqual(harness.snapshot.boutStartedAt, boutStart, "skipping does not restart the sitting bout")
    }

    func testSkipIsBlockedForThreeSecondsInsideTheOverlayToo() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        XCTAssertTrue(harness.state.isFullBreak)

        XCTAssertEqual(harness.send(.userSkip), [])
        harness.clock.advance(4)
        harness.send(.userSkip)
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.skipsToday, 1)
    }

    // MARK: - Completion rule

    func testDoneIsOnlyAcceptedOnceTheBreakCounts() {
        let config = SchedulerConfig()
        XCTAssertFalse(Scheduler.meetsCompletionRule(completed: 1, total: 4, elapsed: 40, config: config))
        XCTAssertTrue(Scheduler.meetsCompletionRule(completed: 2, total: 4, elapsed: 40, config: config))
        XCTAssertTrue(Scheduler.meetsCompletionRule(completed: 0, total: 4, elapsed: 150, config: config))
        XCTAssertTrue(Scheduler.meetsCompletionRule(completed: 3, total: 5, elapsed: 10, config: config))

        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)

        XCTAssertEqual(harness.send(.userDone(completedBlocks: 1, totalBlocks: 4, elapsed: 40)), [])
        XCTAssertTrue(harness.state.isFullBreak, "Done is refused before the break counts")

        harness.send(.breakEnded(completedBlocks: 1, totalBlocks: 4, elapsed: 40))
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.skipsToday, 1, "an early exit is recorded as a skip")
        XCTAssertEqual(harness.snapshot.doneToday, 0)
    }

    func testDoneIsAcceptedAtHalfTheBlocks() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.send(.userDone(completedBlocks: 2, totalBlocks: 4, elapsed: 130))
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.doneToday, 1)
        XCTAssertEqual(harness.snapshot.skipsToday, 0)
    }

    // MARK: - Longest bout and make due in

    func testLongestBoutMeasuresSittingNotBreaks() {
        let harness = SchedulerHarness()
        let boutStart = harness.snapshot.boutStartedAt
        harness.run(until: { $0.isFullBreak }, limit: 90 * minute)
        let breakStart = harness.now
        harness.clock.advance(5 * minute)
        harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))

        let sitting = Int(breakStart.timeIntervalSince(boutStart))
        XCTAssertEqual(harness.snapshot.longestBoutSeconds, sitting, accuracy: 4)
        XCTAssertLessThan(
            harness.snapshot.longestBoutSeconds,
            Int(harness.now.timeIntervalSince(boutStart)),
            "the five minutes of break are not sitting time"
        )
    }

    func testMakeDueInResetsOnlyTheDueTime() {
        let harness = SchedulerHarness()
        harness.run(seconds: 10 * minute)
        let boutStart = harness.snapshot.boutStartedAt
        harness.send(.userMakeDueIn(seconds: 5 * 60))
        XCTAssertEqual(harness.snapshot.nextFullDueAt, harness.now.addingTimeInterval(5 * minute))
        XCTAssertEqual(harness.snapshot.boutStartedAt, boutStart)
        XCTAssertNil(harness.snapshot.nextMicroDueAt, "a micro inside the 10 min quiet zone is dropped")
    }

    // MARK: - Transition log

    func testTransitionLogKeepsTheLastTwenty() {
        let harness = SchedulerHarness()
        for _ in 0..<12 {
            harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
            harness.send(.userStartNow)
            harness.clock.advance(5 * minute)
            harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))
        }
        XCTAssertEqual(harness.snapshot.transitions.count, TransitionLog.capacity)
        XCTAssertEqual(harness.snapshot.transitions.newestFirst.first?.to, .sitting)
        for transition in harness.snapshot.transitions.transitions {
            XCTAssertFalse(transition.reason.isEmpty)
        }
    }

    func testWritesOneFullCycleForEvidence() {
        // Micro-breaks off so the evidence shows the core cycle on its own.
        var config = SchedulerConfig()
        config.microEnabled = false
        let harness = SchedulerHarness(config: config)
        harness.run(until: { $0.isPendingFull })
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.run(until: { $0.isFullBreak })
        harness.clock.advance(5 * minute)
        harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))

        let rendered = harness.snapshot.transitions.rendered()
        RoutineTestSupport.write(
            "One full 55/5 cycle on a manual clock (ticks every 2 s)\n\n" + rendered + "\n",
            to: "transition-log-core.txt"
        )
        XCTAssertEqual(
            harness.snapshot.transitions.transitions.map(\.to.name),
            ["pending_full", "heads_up", "full_break", "sitting"]
        )
    }
}
