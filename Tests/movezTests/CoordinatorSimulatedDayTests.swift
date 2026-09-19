import XCTest
@testable import movez

@MainActor
final class CoordinatorSimulatedDayTests: XCTestCase {
    private let minute: TimeInterval = 60

    /// Runs a working day, taking each break the moment it comes due and completing it in five
    /// minutes. That keeps the arithmetic honest: every break is due exactly 55 minutes after the
    /// previous one ended.
    private struct TakenBreak {
        var start: Date
        var end: Date
        var routine: Routine
    }

    private func simulateDay(
        harness: CoordinatorHarness,
        skipBreakIndex: Int? = nil,
        hours: TimeInterval = 9 * 3600
    ) -> [TakenBreak] {
        var breaks: [TakenBreak] = []
        var elapsed: TimeInterval = 0

        while elapsed < hours {
            harness.clock.advance(2)
            elapsed += 2
            harness.coordinator.tick()

            guard harness.state.isPendingFull else { continue }
            harness.coordinator.takeBreakNow()
            guard let session = harness.coordinator.currentBreak else { continue }
            let start = harness.now

            if breaks.count == skipBreakIndex {
                harness.clock.advance(10)
                harness.coordinator.skip()
            } else {
                harness.clock.advance(5 * minute)
                harness.coordinator.inject(.userDone(
                    completedBlocks: session.totalBlocks,
                    totalBlocks: session.totalBlocks,
                    elapsed: 300
                ))
            }
            breaks.append(TakenBreak(start: start, end: harness.now, routine: session.routine))
            elapsed += breaks.count == skipBreakIndex ? 10 : 5 * minute
        }
        return breaks
    }

    func testAFullWorkingDayServesNineBreaks() {
        let harness = CoordinatorHarness()
        let breaks = simulateDay(harness: harness)

        XCTAssertEqual(breaks.count, 9)
        XCTAssertDate(breaks[0].start, SchedulerHarness.mondayMorning.addingTimeInterval(55 * minute), accuracy: 2)
        for (previous, current) in zip(breaks, breaks.dropFirst()) {
            XCTAssertDate(current.start, previous.end.addingTimeInterval(55 * minute), accuracy: 2)
        }
        XCTAssertDate(breaks[8].start, SchedulerHarness.mondayMorning.addingTimeInterval(8 * 3600 + 55 * minute), accuracy: 2)

        let stats = harness.history.stats(on: harness.now)
        XCTAssertEqual(stats.done, 9)
        XCTAssertEqual(harness.history.streak(on: harness.now), 9)

        XCTAssertEqual(breaks[8].routine.timeOfDay, .last, "the 17:55 break is the last of the day")
        XCTAssertEqual(
            breaks.prefix(7).map(\.routine.slot),
            [.hip, .tSpineChest, .neckShoulder, .posteriorChain, .core, .ankleFoot, .hip]
        )

        var seen: [String: Int] = [:]
        for id in breaks.flatMap(\.routine.movementIds) { seen[id, default: 0] += 1 }
        let repeated = seen.filter { $0.value > 1 }.keys.sorted()
        XCTAssertTrue(repeated.allSatisfy(RoutineContext.alwaysRepeatable.contains), "repeated \(repeated)")

        let distinctMovements = Set(breaks.flatMap(\.routine.movementIds)).count
        let lines = breaks.enumerated().map { index, entry in
            let start = TransitionLog.timeFormatter.string(from: entry.start)
            let names = entry.routine.blocks.map { "\($0.movement.id) \($0.seconds)s" }.joined(separator: ", ")
            return "\(index + 1). \(start)  \(entry.routine.subtitle.padded(to: 44))[\(entry.routine.shape.rawValue)] \(names)"
        }
        RoutineTestSupport.write(
            """
            Simulated working day — Monday 09:00 to 18:00, 55/5, every break completed

            \(lines.joined(separator: "\n"))

            done \(stats.done) · snoozed \(stats.snoozed) · skipped \(stats.skipped)
            streak \(harness.history.streak(on: harness.now))
            longest sitting bout \(AppCoordinator.duration(stats.longestBoutSeconds))
            distinct movements served \(distinctMovements)
            """,
            to: "simulated-day.txt"
        )
    }

    func testSkippingABreakResetsTheStreak() {
        let harness = CoordinatorHarness()
        let breaks = simulateDay(harness: harness, skipBreakIndex: 2, hours: 5 * 3600)
        XCTAssertGreaterThanOrEqual(breaks.count, 4)

        let today = harness.now
        XCTAssertEqual(harness.history.stats(on: today).skipped, 1)

        let records = harness.history.breaks(on: today)
        XCTAssertEqual(records[2].outcome, .skipped)
        XCTAssertEqual(records[3].outcome, .done)

        // Streak after the skip is 0, and 1 again once the next break is completed.
        let throughSkip = Array(records.prefix(3))
        XCTAssertEqual(throughSkip.last?.outcome, .skipped)
        XCTAssertEqual(harness.history.streak(on: today), records.count - 3)
    }

    func testEffectOrderForOneCompletedBreak() {
        let harness = CoordinatorHarness()
        _ = harness.run(until: { $0.isPendingFull }, limit: 60 * minute)
        harness.sink.clear()

        _ = harness.run(until: { $0.isHeadsUp }, limit: 5 * minute)
        _ = harness.run(until: { $0.isFullBreak }, limit: 5 * minute)
        XCTAssertNotNil(harness.coordinator.currentBreak)

        let blocks = harness.coordinator.currentBreak?.totalBlocks ?? 0
        harness.completeBreak()

        let interesting: Set<String> = [
            "showHeadsUp", "chime(headsUp)", "hideHeadsUp", "startFullBreak",
            "chime(transition)", "chime(completion)", "endFullBreak"
        ]
        var expected = ["showHeadsUp", "chime(headsUp)", "hideHeadsUp", "startFullBreak"]
        expected += Array(repeating: "chime(transition)", count: blocks - 1)
        expected += ["chime(completion)", "endFullBreak"]
        XCTAssertEqual(harness.sink.order(of: interesting), expected)
        XCTAssertTrue(harness.sink.names.contains("persist"))
        XCTAssertEqual(harness.history.stats(on: harness.now).done, 1)
        let served = Set(harness.history.breaks(on: harness.now).map(\.routineName))
        XCTAssertEqual(served.count, 1)
        XCTAssertGreaterThanOrEqual(harness.history.usedMovementIds(on: harness.now).count, blocks)
    }

    func testChangingThePresetMidBoutKeepsTheBout() {
        let harness = CoordinatorHarness()
        harness.run(seconds: 20 * minute)
        let boutStart = harness.scheduler.snapshot.boutStartedAt
        XCTAssertDate(boutStart, SchedulerHarness.mondayMorning)

        harness.settings.preset = .twentyFiveFive
        harness.coordinator.settingsChanged()

        XCTAssertDate(harness.scheduler.snapshot.boutStartedAt, boutStart)
        XCTAssertDate(harness.scheduler.snapshot.nextFullDueAt, boutStart.addingTimeInterval(25 * minute))
        XCTAssertNil(harness.scheduler.snapshot.nextMicroDueAt, "25/5 serves no micro-breaks")
    }

    func testChangingTheAwayThresholdTakesEffectOnTheNextIdleCheck() {
        let harness = CoordinatorHarness()
        harness.run(seconds: 10 * minute)

        harness.settings.awayThresholdMinutes = 5
        harness.coordinator.settingsChanged()

        harness.clock.advance(4 * minute)
        harness.coordinator.inject(.idle(seconds: 240))
        XCTAssertTrue(harness.state.isSitting, "four minutes is no longer away")

        harness.clock.advance(6 * minute)
        harness.coordinator.inject(.idle(seconds: 360))
        guard case .away = harness.state else { return XCTFail("six minutes should be away, got \(harness.state)") }
    }

    func testStateAndHistoryAreWrittenOnEveryChange() {
        let harness = CoordinatorHarness()
        _ = harness.run(until: { $0.isFullBreak }, limit: 90 * minute)
        harness.completeBreak()

        let persists = harness.sink.names.filter { $0 == "persist" }.count
        XCTAssertEqual(harness.snapshotStore.saveCount, persists, "one state write per persist effect")
        XCTAssertFalse(harness.scheduler.snapshot.transitions.transitions.isEmpty)

        let blocks = harness.history.data.completions.count
        let records = harness.history.data.breakRecords.count
        XCTAssertEqual(harness.historyStore.saveCount, blocks + records, "one history write per mutation")
    }

    func testMenuStateReflectsTheScheduler() {
        let harness = CoordinatorHarness()
        harness.run(seconds: 10 * minute)
        XCTAssertEqual(harness.coordinator.menuState.mode, .sitting)
        XCTAssertEqual(harness.coordinator.menuState.secondsUntilBreak ?? 0, 45 * 60, accuracy: 2)
        XCTAssertFalse(harness.coordinator.menuState.nextRoutineSubtitle.isEmpty)

        harness.coordinator.pause(forSeconds: 30 * 60)
        XCTAssertEqual(harness.coordinator.menuState.mode, .paused)
        XCTAssertNotNil(harness.coordinator.menuState.pausedUntil)

        harness.coordinator.resume()
        XCTAssertEqual(harness.coordinator.menuState.mode, .sitting)
        XCTAssertEqual(AppCoordinator.duration(4_320), "1 h 12 m")
        XCTAssertEqual(AppCoordinator.duration(1_920), "32 m")
    }

    func testThePreviewMatchesTheRoutineTheOverlayServes() {
        let harness = CoordinatorHarness()
        _ = harness.run(until: { $0.isPendingFull }, limit: 90 * minute)
        let preview = harness.coordinator.nextRoutinePreview
        XCTAssertNotNil(preview)

        _ = harness.run(until: { $0.isFullBreak }, limit: 5 * minute)
        XCTAssertEqual(harness.coordinator.currentBreak?.routine.movementIds, preview?.movementIds)
        XCTAssertEqual(harness.coordinator.menuState.nextRoutineSubtitle, preview?.subtitle)
    }

    func testACreditedAbsenceIsRecordedAndReversible() {
        let harness = CoordinatorHarness()
        harness.run(seconds: 10 * minute)

        harness.clock.advance(7 * minute)
        harness.coordinator.inject(.idle(seconds: 7 * 60))
        harness.coordinator.inject(.input(lastEventAgeSeconds: 0))
        XCTAssertEqual(harness.history.stats(on: harness.now).done, 1)
        XCTAssertEqual(harness.coordinator.toastInfo?.kind, .creditedFullBreak)

        harness.clock.advance(3)
        harness.coordinator.reverseToast()
        XCTAssertEqual(harness.history.stats(on: harness.now).done, 0)
        XCTAssertNil(harness.coordinator.toastInfo)
    }

    /// A break turned away at the heads-up never becomes a session, so the coordinator used to
    /// see nothing but `hideHeadsUp` — which sleep, idle and a pause all send too — and the
    /// day's snoozes and skips were the overlay's alone.
    func testSnoozingAndSkippingAtTheHeadsUpIsRecorded() {
        let snoozed = CoordinatorHarness()
        _ = snoozed.run(until: { $0.isHeadsUp }, limit: 90 * minute)
        let advertised = snoozed.coordinator.nextRoutinePreview?.name
        snoozed.coordinator.inject(.userSnooze)

        let snoozeStats = snoozed.history.stats(on: snoozed.now)
        XCTAssertEqual(snoozeStats.snoozed, 1)
        XCTAssertEqual(snoozeStats.done, 0)
        XCTAssertEqual(snoozed.history.breaks(on: snoozed.now).last?.routineName, advertised)

        let skipped = CoordinatorHarness()
        _ = skipped.run(until: { $0.isHeadsUp }, limit: 90 * minute)
        skipped.run(seconds: 6)
        skipped.coordinator.inject(.userSkip)

        XCTAssertEqual(skipped.history.stats(on: skipped.now).skipped, 1)
        XCTAssertEqual(skipped.history.streak(on: skipped.now), 0, "a skip ends the streak wherever it is made")
    }

    /// The region rotation is a cursor over routines actually done, not a counter that starts
    /// again each morning: two breaks a day used to mean the first two slots, for ever.
    func testTheRotationCarriesOnIntoTheNextDay() {
        let harness = CoordinatorHarness()
        var slots: [RotationSlot] = []

        for _ in 0..<2 {
            _ = harness.run(until: { $0.isFullBreak }, limit: 90 * minute)
            slots.append(harness.coordinator.currentBreak?.routine.slot ?? .hip)
            harness.completeBreak()
        }

        // Tomorrow morning, from the history the first day left behind.
        harness.clock.advance(20 * 3600)
        harness.coordinator.tick()
        slots.append(harness.coordinator.nextRoutinePreview?.slot ?? .hip)

        XCTAssertEqual(slots, [.hip, .tSpineChest, .neckShoulder])
    }
}
