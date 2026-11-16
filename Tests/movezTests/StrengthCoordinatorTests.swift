import XCTest
@testable import movez

/// Modes at app level (S13, S22, S23, S8): the coordinator builds, previews, starts and records
/// breaks through the mode in use when each one is built, and a session already on screen keeps
/// the mode it started in.
@MainActor
final class StrengthCoordinatorTests: XCTestCase {
    private let minute: TimeInterval = 60

    // MARK: - Support

    /// A coordinator in Strength mode, set up, with always-on hours so a whole day fits.
    private func strengthHarness(
        perDay: Int = 3,
        micro: Bool = false,
        configure: (SettingsStore) -> Void = { _ in }
    ) -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn) { settings in
            settings.microEnabled = micro
            settings.strengthSetUp = true
            settings.strengthBreaksPerDay = perDay
            settings.mode = .strength
            configure(settings)
        }
    }

    /// Runs to the next heads-up, starts the break and works through every part of it.
    @discardableResult
    private func takeBreak(_ harness: CoordinatorHarness) -> BreakSession? {
        guard harness.run(until: { $0.isHeadsUp }) else { return nil }
        harness.coordinator.startNow()
        let session = harness.coordinator.currentBreak
        harness.completeBreak()
        return session
    }

    private func switchMode(_ harness: CoordinatorHarness, to mode: BreakMode) {
        harness.coordinator.settings.mode = mode
        harness.coordinator.settingsChanged()
    }

    private func kinds(_ harness: CoordinatorHarness) -> [BreakKind] {
        harness.coordinator.history.data.breakRecords.filter { !$0.outcome.isAbsence }.map(\.breakKind)
    }

    // MARK: - A switch applies from the next session (S13)

    func testSwitchingDuringAHeadsUpKeepsTheAnnouncedBreak() throws {
        let harness = strengthHarness()
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        let announced = try XCTUnwrap(harness.coordinator.headsUpBreak)
        XCTAssertEqual(announced.mode, .strength)
        XCTAssertEqual(announced.planned.kind, .strengthA)
        let info = try XCTUnwrap(harness.coordinator.headsUpInfo)
        XCTAssertEqual(info.breakKind, .strengthA, "the heads-up says what kind of break is coming")
        XCTAssertEqual(info.breakMinutes, Int((Double(announced.planned.plannedSeconds) / 60).rounded()))

        switchMode(harness, to: .movement)
        harness.coordinator.startNow()

        let session = try XCTUnwrap(harness.coordinator.currentBreak)
        XCTAssertEqual(session.planned, announced.planned, "the break the heads-up announced is the one served")
        XCTAssertEqual(session.mode, .strength)
        XCTAssertEqual(harness.scheduler.config.breakSeconds, announced.planned.plannedSeconds)
        harness.completeBreak()
        XCTAssertEqual(kinds(harness), [.strengthA])

        let next = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(next.mode, .movement, "the next session is built in the new mode")
        XCTAssertNotNil(next.routine)
        XCTAssertEqual(kinds(harness), [.strengthA, .movement])
    }

    func testSwitchingDuringAFullBreakKeepsTheBreakOnScreen() throws {
        let harness = strengthHarness()
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let session = try XCTUnwrap(harness.coordinator.currentBreak)
        harness.clock.advance(60)
        harness.coordinator.nextBlock()

        switchMode(harness, to: .movement)
        harness.coordinator.tick()

        let current = try XCTUnwrap(harness.coordinator.currentBreak)
        XCTAssertEqual(current.planned, session.planned)
        XCTAssertEqual(current.mode, .strength)
        XCTAssertEqual(current.completedBlocks, 1)
        XCTAssertEqual(harness.coordinator.nextBreakPreview, session.planned, "the menu shows the break on screen")
        XCTAssertEqual(
            harness.scheduler.config.breakSeconds,
            session.planned.plannedSeconds,
            "done at half is still measured against the break on screen"
        )
        harness.completeBreak()
        XCTAssertEqual(kinds(harness), [.strengthA])

        let next = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(next.mode, .movement)
        XCTAssertEqual(next.planned.kind, .movement)
        XCTAssertEqual(harness.scheduler.config.breakSeconds, SchedulerConfig().breakSeconds)
    }

    func testSwitchingDuringAMicroBreakKeepsTheMicroBreakOnScreen() throws {
        let harness = CoordinatorHarness(workingHours: .alwaysOn) { $0.strengthSetUp = true }
        XCTAssertTrue(harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute))
        let micro = try XCTUnwrap(harness.coordinator.currentMicro)
        XCTAssertNotNil(micro.movementMicro)
        XCTAssertEqual(harness.coordinator.currentMicroMode, .movement)

        switchMode(harness, to: .strength)
        XCTAssertTrue(harness.run(until: { $0.isMicroRunning }, limit: minute))
        XCTAssertEqual(harness.coordinator.currentMicro, micro)
        XCTAssertEqual(harness.coordinator.currentMicroMode, .movement)
        harness.clock.advance(70)
        harness.coordinator.microEnded()
        XCTAssertNil(harness.coordinator.currentMicro)

        // The next micro-break comes after the full break the countdown reaches first.
        var nextMicro: PlannedMicro?
        for _ in 0..<4 where nextMicro == nil {
            XCTAssertTrue(harness.run(until: { $0.isMicroCountIn || $0.isHeadsUp }))
            if harness.state.isHeadsUp {
                harness.coordinator.startNow()
                harness.completeBreak()
            } else {
                nextMicro = harness.coordinator.currentMicro
            }
        }
        let next = try XCTUnwrap(nextMicro)
        XCTAssertNotNil(next.strengthMicro, "the next micro-break is built in the new mode")
        XCTAssertEqual(harness.coordinator.currentMicroMode, .strength)
    }

    /// A wake after the slept-through break's planned end settles that break without resuming
    /// it, so the session kept for a resume must not stand in for the next break: not in the
    /// preview, not in the length the scheduler measures, and not in the break that starts.
    func testAWakeAfterTheBreakWasDueToEndDropsTheKeptSession() throws {
        let harness = strengthHarness()
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let stale = try XCTUnwrap(harness.coordinator.currentBreak)
        harness.clock.advance(60)
        harness.coordinator.nextBlock()
        harness.coordinator.inject(.sleep)
        XCTAssertNotNil(harness.coordinator.interruptedSession)

        switchMode(harness, to: .movement)
        let gap = TimeInterval(stale.planned.plannedSeconds) + 10 * minute
        harness.clock.advance(gap)
        harness.coordinator.inject(.wake(gapSeconds: Int(gap)))
        harness.run(seconds: 90)

        XCTAssertNil(harness.coordinator.interruptedSession, "the interruption is settled")
        let preview = harness.coordinator.previewNextBreak(now: harness.now)
        XCTAssertNotEqual(preview, stale.planned, "the menu no longer shows the slept-through break")
        XCTAssertEqual(preview.kind, .movement, "and the next break is built in the mode in use now")
        XCTAssertEqual(harness.scheduler.config.breakSeconds, preview.plannedSeconds)

        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        let announced = try XCTUnwrap(harness.coordinator.headsUpBreak)
        harness.coordinator.startNow()
        let served = try XCTUnwrap(harness.coordinator.currentBreak)
        XCTAssertEqual(served.planned, announced.planned, "the break served is the one the heads-up announced")
        XCTAssertEqual(served.mode, .movement)
        XCTAssertEqual(served.completedBlocks, 0)
    }

    // MARK: - Relaunch

    func testARelaunchKeepsTheModeAndTheNextBreak() throws {
        let harness = strengthHarness()
        takeBreak(harness)
        let before = harness.coordinator.previewNextBreak(now: harness.now)
        XCTAssertEqual(before.kind, .strengthA)

        harness.relaunch()

        XCTAssertEqual(harness.coordinator.settings.mode, .strength)
        XCTAssertEqual(harness.coordinator.previewNextBreak(now: harness.now), before)
        XCTAssertEqual(harness.scheduler.config.breakSeconds, before.plannedSeconds)
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.breakNumber, 2)

        let served = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(served.planned, before, "the break the menu advertised before the relaunch is served")
    }

    // MARK: - The day plan through the coordinator (S22)

    func testAFiveBreakStrengthDayRecordsThreeStrengthBreaksThenEndRange() throws {
        let harness = strengthHarness(perDay: 3)
        var progress: [Int?] = []
        for _ in 0..<5 {
            progress.append(harness.coordinator.menuState.dayProgress?.breakNumber)
            let preview = harness.coordinator.previewNextBreak(now: harness.now)
            XCTAssertEqual(harness.scheduler.config.breakSeconds, preview.plannedSeconds)
            let session = try XCTUnwrap(takeBreak(harness))
            XCTAssertEqual(session.planned, preview, "the preview is the break that starts")
        }
        XCTAssertEqual(kinds(harness), [.strengthA, .strengthA, .strengthA, .endRange, .endRange])
        XCTAssertEqual(progress, [1, 2, 3, nil, nil])
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.dayLetter, .dayA)
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.breaksPerDay, 3)
        XCTAssertEqual(harness.coordinator.menuState.breakMode, .strength)

        // Every set is a completion, so the planner, recency and the unlock can read them.
        let records = harness.coordinator.history.data.breakRecords
        XCTAssertEqual(records.map(\.completedBlocks), [5, 5, 5, 4, 4])
        XCTAssertEqual(harness.coordinator.history.data.completions.count, 5 * 3 + 4 * 2)
    }

    func testASkippedFirstStrengthBreakLeavesTheNextOneAStrengthBreak() throws {
        let harness = strengthHarness()
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        harness.clock.advance(10)
        harness.coordinator.skip()
        XCTAssertEqual(kinds(harness), [.strengthA])
        XCTAssertEqual(harness.coordinator.history.data.breakRecords.map(\.outcome), [.skipped])

        let next = try XCTUnwrap(takeBreak(harness))
        let sets = try XCTUnwrap(next.planned.strengthBreak?.sets)
        XCTAssertEqual(sets.map(\.movement.bucket), [.sqt, .psh, .cor], "still the day's first-break shape")
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.breakNumber, 2)
    }

    func testAMovementBreakMidDayCountsNoneOfTheDaysStrengthBreaks() throws {
        let harness = strengthHarness(perDay: 3)
        takeBreak(harness)
        takeBreak(harness)
        switchMode(harness, to: .movement)
        takeBreak(harness)
        switchMode(harness, to: .strength)
        takeBreak(harness)
        takeBreak(harness)
        XCTAssertEqual(kinds(harness), [.strengthA, .strengthA, .movement, .strengthA, .endRange])
    }

    // MARK: - Preview cache

    func testThePreviewKeyMovesWithTheModeTheDayLetterAndEveryStrengthSetting() throws {
        let harness = strengthHarness()
        let coordinator = harness.coordinator
        let settings = coordinator.settings
        var keys: [String] = [coordinator.previewKey(at: harness.now)]
        func changed(_ what: String) {
            let key = coordinator.previewKey(at: harness.now)
            XCTAssertFalse(keys.contains(key), "\(what) leaves the key unchanged")
            keys.append(key)
        }

        settings.mode = .movement
        changed("mode")
        settings.mode = .strength
        XCTAssertEqual(coordinator.previewKey(at: harness.now), keys[0])

        settings.strengthEquipment = [.dumbbells]
        changed("equipment")
        settings.strengthSolidWallNearby.toggle()
        changed("solid wall")
        settings.strengthBreaksPerDay = 2
        changed("breaks a day")
        settings.strengthDifficultyCap = 2
        changed("difficulty cap")
        settings.strengthFocus = .moreCore
        changed("focus")
        settings.strengthBreaksPerDay = 3
        settings.strengthFocus = .moreArms
        changed("focus that moves the arm break")
        settings.strengthExcludedIds = ["SQT-01"]
        changed("exclusions")

        let yesterday = harness.now.addingTimeInterval(-24 * 3600)
        coordinator.history.record(breakRecord: BreakRecord(
            at: yesterday, routineName: BreakRecord.movementBreakName, outcome: .done,
            completedBlocks: 5, totalBlocks: 5, kind: .strengthA
        ))
        changed("day letter")
        XCTAssertEqual(coordinator.nextBreak(at: harness.now).strengthBreak?.letter, .dayB)

        let preview = coordinator.previewNextBreak(now: harness.now)
        coordinator.settingsChanged()
        let session = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(session.planned, preview, "the preview equals the started break")
    }

    // MARK: - Cross-mode used-today (S8)

    func testAMovementServedTodayRulesItsSameCounterpartOutOfStrength() {
        // Yesterday was an A day, so today is B: hinge, whose HNG-01 is the same exercise as
        // STR-01. FLX-26's counterpart END-08 is micro-eligible.
        let harness = strengthHarness(perDay: 3, micro: true) { settings in
            settings.strengthEquipment = [.dumbbells, .kettlebell]
            settings.strengthDifficultyCap = 2
        }
        let coordinator = harness.coordinator
        let start = harness.now
        coordinator.history.record(breakRecord: BreakRecord(
            at: start.addingTimeInterval(-24 * 3600), routineName: BreakRecord.movementBreakName,
            outcome: .done, completedBlocks: 5, totalBlocks: 5, kind: .strengthA
        ))
        for id in ["STR-01", "FLX-26"] {
            coordinator.history.record(completion: MovementCompletion(movementId: id, at: start, seconds: 60, routineId: nil))
        }
        coordinator.history.record(breakRecord: BreakRecord(
            at: start, routineName: BreakRecord.movementBreakName, outcome: .done,
            completedBlocks: 5, totalBlocks: 5, kind: .movement
        ))
        coordinator.invalidatePreview()

        let builder = StrengthModeBuilder(
            library: RoutineTestSupport.strengthLibrary,
            usage: CrossModeUsage(movementLibrary: RoutineTestSupport.library, strengthLibrary: RoutineTestSupport.strengthLibrary)
        )
        let used = builder.usedStrengthIds(for: coordinator, at: harness.now)
        XCTAssertTrue(used.isSuperset(of: ["HNG-01", "END-08"]))

        // "While the pool allows": a draw that ran today's pool dry says so on the break, and
        // only such a draw may bring a used move back.
        var micros = 0
        var fullBreaks: [PlannedBreak] = []
        var offenders: [String] = []
        func check(_ ids: [String], relaxed: [StrengthRelaxation], what: String) {
            let repeated = ids.filter { $0 == "HNG-01" || $0 == "END-08" }
            if !repeated.isEmpty, !relaxed.contains(where: { $0.rule == .servedToday }) {
                offenders.append("\(what): \(repeated)")
            }
        }
        while fullBreaks.count < 6 {
            guard harness.run(until: { $0.isMicroCountIn || $0.isHeadsUp }) else { break }
            if harness.state.isHeadsUp {
                coordinator.startNow()
                if let planned = coordinator.currentBreak?.planned {
                    fullBreaks.append(planned)
                    let relaxed = planned.strengthBreak?.relaxed ?? planned.endRangeBreak?.relaxed ?? []
                    check(planned.movementIds, relaxed: relaxed, what: "break \(fullBreaks.count)")
                }
                harness.completeBreak()
            } else {
                micros += 1
                let micro = coordinator.currentMicro?.strengthMicro
                XCTAssertNotNil(micro)
                check(micro?.movementIds ?? [], relaxed: micro?.relaxed ?? [], what: "micro \(micros)")
                harness.clock.advance(70)
                coordinator.microEnded()
            }
        }
        XCTAssertEqual(fullBreaks.map(\.kind), [.strengthB, .strengthB, .strengthB, .endRange, .endRange, .endRange])
        XCTAssertGreaterThan(micros, 0)
        XCTAssertFalse(fullBreaks[0].movementIds.contains("HNG-01"), "the same exercise as this morning's STR-01")
        XCTAssertEqual(offenders, [], "a same-exercise counterpart served without the pool running dry")
    }

    // MARK: - Absences (S23)

    /// Everything an absence produced, with the next break's kind taken out of any heads-up, since
    /// that is the one thing that should differ by mode.
    private struct AbsenceOutcome: Equatable {
        var effects: [SchedulerEffect]
        var records: [BreakRecord]
        var toastTitle: String
        var toastBody: String
    }

    private func absence(mode: BreakMode, behaviour: AwayBehaviour, sitMinutes: Double, awayMinutes: Double) -> AbsenceOutcome {
        let harness = strengthHarness { settings in
            settings.mode = mode
            settings.awayBehaviour = behaviour
        }
        harness.run(seconds: sitMinutes * minute)
        harness.sink.clear()

        var idle = 0
        while Double(idle) < awayMinutes * minute {
            harness.clock.advance(2)
            idle += 2
            harness.coordinator.inject(.input(lastEventAgeSeconds: idle))
            harness.coordinator.inject(.idle(seconds: idle))
            harness.coordinator.tick()
        }
        harness.clock.advance(2)
        harness.coordinator.inject(.input(lastEventAgeSeconds: 0))
        let toast = PanelViewModel(phase: .toast, clock: harness.clock, startedAt: harness.now, totalSeconds: 15)
        toast.toast = harness.coordinator.toastInfo
        harness.run(seconds: 30)

        let effects = harness.sink.effects.map { effect -> SchedulerEffect in
            guard case .showHeadsUp(var info) = effect else { return effect }
            info.breakKind = nil
            info.breakMinutes = nil
            return .showHeadsUp(info)
        }
        return AbsenceOutcome(
            effects: effects,
            records: harness.coordinator.history.data.breakRecords,
            toastTitle: toast.title,
            toastBody: toast.body
        )
    }

    func testAbsencesHaveTheSameEffectsInBothModes() {
        struct Scenario {
            let name: String
            let sit: Double
            let away: Double
        }
        let scenarios = [
            Scenario(name: "40 min spanning the due time", sit: 35, away: 40),
            Scenario(name: "10 min before the due time", sit: 30, away: 10)
        ]
        for behaviour in AwayBehaviour.allCases {
            for scenario in scenarios {
                let movement = absence(mode: .movement, behaviour: behaviour, sitMinutes: scenario.sit, awayMinutes: scenario.away)
                let strength = absence(mode: .strength, behaviour: behaviour, sitMinutes: scenario.sit, awayMinutes: scenario.away)
                let label = "\(behaviour) · \(scenario.name)"
                XCTAssertEqual(movement, strength, label)
                XCTAssertEqual(movement.records.map(\.outcome), [BreakResult(behaviour)], label)
                XCTAssertTrue(movement.toastTitle.hasPrefix("Away \(Int(scenario.away)) min"), "\(label): \(movement.toastTitle)")
                XCTAssertEqual(movement.effects.filter { $0.name == "showToast" }.count, 1, label)
            }
        }
    }

    // MARK: - The scheduler's planned length

    /// Ends a break after `elapsed` seconds with no part done; true when it counted as done.
    private func endsAsDone(plannedSeconds: Int, elapsed: Int) -> Bool {
        let harness = SchedulerHarness()
        harness.send(.breakLength(seconds: plannedSeconds))
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.send(.userStartNow)
        harness.send(.breakEnded(completedBlocks: 0, totalBlocks: 5, elapsed: elapsed))
        XCTAssertTrue(harness.state.isSitting)
        XCTAssertEqual(harness.snapshot.doneToday + harness.snapshot.skipsToday, 1, "the break is one or the other")
        return harness.snapshot.doneToday == 1
    }

    private func completionAt(plannedSeconds: Int) -> (refusedAt: Int, acceptedAt: Int) {
        let half = plannedSeconds / 2
        XCTAssertFalse(endsAsDone(plannedSeconds: plannedSeconds, elapsed: half - 1), "a skip before half of \(plannedSeconds) s")
        XCTAssertTrue(endsAsDone(plannedSeconds: plannedSeconds, elapsed: half), "done at half of \(plannedSeconds) s")
        return (half - 1, half)
    }

    func testA290SecondBreakCountsAtHalfItsLength() {
        XCTAssertEqual(completionAt(plannedSeconds: 290).acceptedAt, 145)
    }

    func testA325SecondBreakCountsAtHalfItsLength() {
        XCTAssertEqual(completionAt(plannedSeconds: 325).acceptedAt, 162)
    }

    /// The length is not a setting: it re-plans nothing, so a skip's fresh interval stands.
    func testABreakLengthLeavesTheDueTimesAlone() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.clock.advance(5)
        harness.send(.userSkip)
        let due = harness.snapshot.nextFullDueAt
        XCTAssertEqual(harness.send(.breakLength(seconds: 290)), [])
        XCTAssertEqual(harness.snapshot.nextFullDueAt, due)
        XCTAssertEqual(harness.scheduler.config.breakSeconds, 290)
    }
}

// MARK: - A resumed break

/// Kept apart from the class body, which is at its length limit.
extension StrengthCoordinatorTests {
    /// A wake rebuilds the overlay, which replays the parts already done from the backdated
    /// start. Each part is written once, in order, and the cool-down is not written again for
    /// every part the replay reports.
    func testAResumedStrengthBreakRecordsEachPartOnceInOrder() throws {
        let harness = strengthHarness()
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let session = try XCTUnwrap(harness.coordinator.currentBreak)
        let strengthBreak = try XCTUnwrap(session.planned.strengthBreak)
        let breakId = session.planned.id

        func overlay(for session: BreakSession) -> StrengthOverlayViewModel {
            let viewModel = StrengthOverlayViewModel(
                strengthBreak: strengthBreak, startedAt: session.startedAt, clock: harness.clock
            )
            viewModel.onWorkCompleted = { [weak coordinator = harness.coordinator] index in
                coordinator?.recordOverlayPart(index: index)
            }
            viewModel.onFinished = { [weak coordinator = harness.coordinator] completed, total, elapsed in
                coordinator?.finishOverlayBreak(completed: completed, total: total, elapsed: elapsed)
            }
            return viewModel
        }
        func recorded() -> [String] {
            harness.coordinator.history.data.completions.filter { $0.routineId == breakId }.map(\.movementId)
        }

        let first = overlay(for: session)
        while (harness.coordinator.currentBreak?.completedBlocks ?? 0) < 2 {
            harness.clock.advance(1)
            first.tick()
        }
        harness.coordinator.inject(.sleep)
        XCTAssertNotNil(harness.coordinator.interruptedSession)

        harness.clock.advance(60)
        harness.coordinator.inject(.wake(gapSeconds: 60))
        harness.run(seconds: 90)
        let resumed = try XCTUnwrap(harness.coordinator.currentBreak, "the break resumes")
        XCTAssertEqual(resumed.planned.id, breakId)
        XCTAssertEqual(resumed.completedBlocks, 2)

        let second = overlay(for: resumed)
        second.tick()
        XCTAssertEqual(recorded(), session.planned.parts.prefix(2).map(\.movementId),
                       "the replay of the parts already done writes nothing ahead of time")
        while harness.coordinator.currentBreak != nil, !second.isClosed {
            harness.clock.advance(1)
            second.tick()
        }

        XCTAssertEqual(recorded(), session.planned.parts.map(\.movementId),
                       "each part once, in order, with no extra cool-down records")
    }
}

// MARK: - Cross-mode used-today, strength first (S8, S18)

/// The reverse direction of S8: a strength move served today rules its same counterpart, and
/// that counterpart's whole family, out of the day's Movement breaks.
extension StrengthCoordinatorTests {
    func testAStrengthMoveServedTodayRulesItsSameCounterpartsFamilyOutOfMovement() {
        // HNG-01 is `same` as the movement library's STR-01, whose glute-bridge family is
        // STR-01, STR-02 and STR-03 (movement-library-v4.json).
        let glutebridge: Set<String> = ["STR-01", "STR-02", "STR-03"]
        let harness = CoordinatorHarness(workingHours: .alwaysOn) { settings in
            settings.microEnabled = true
            settings.strengthSetUp = true
            settings.mode = .strength
        }
        let coordinator = harness.coordinator
        let start = harness.now
        coordinator.history.record(completion: MovementCompletion(movementId: "HNG-01", at: start, seconds: 60, routineId: nil))
        coordinator.history.record(breakRecord: BreakRecord(
            at: start, routineName: BreakRecord.movementBreakName, outcome: .done,
            completedBlocks: 3, totalBlocks: 3, kind: .strengthB
        ))
        switchMode(harness, to: .movement)
        coordinator.invalidatePreview()

        let used = coordinator.movementIdsUsedToday(at: harness.now)
        XCTAssertTrue(used.isSuperset(of: glutebridge), "the whole family of HNG-01's counterpart")
        XCTAssertTrue(used.contains("HNG-01"), "what was served stays served")

        // The Movement builders report no relaxation, so no draw is excepted: within the first
        // breaks of the day the pool is far from dry and none of the family may come back.
        var micros = 0
        var fullBreaks: [PlannedBreak] = []
        var offenders: [String] = []
        while fullBreaks.count < 3 {
            guard harness.run(until: { $0.isMicroCountIn || $0.isHeadsUp }) else { break }
            if harness.state.isHeadsUp {
                coordinator.startNow()
                if let planned = coordinator.currentBreak?.planned {
                    fullBreaks.append(planned)
                    let repeated = planned.movementIds.filter(glutebridge.contains)
                    if !repeated.isEmpty { offenders.append("break \(fullBreaks.count): \(repeated)") }
                }
                harness.completeBreak()
            } else {
                micros += 1
                let ids = coordinator.currentMicro?.movementIds ?? []
                XCTAssertFalse(ids.isEmpty, "micro \(micros) serves movements")
                let repeated = ids.filter(glutebridge.contains)
                if !repeated.isEmpty { offenders.append("micro \(micros): \(repeated)") }
                harness.clock.advance(70)
                coordinator.microEnded()
            }
        }
        XCTAssertEqual(fullBreaks.map(\.kind), [.movement, .movement, .movement])
        XCTAssertGreaterThan(micros, 0)
        XCTAssertEqual(offenders, [], "a glute bridge served after this morning's HNG-01")
    }

    func testWithNoStrengthMoveServedMovementSeesExactlyWhatWasServed() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn) { settings in
            settings.microEnabled = false
            settings.mode = .movement
        }
        let coordinator = harness.coordinator
        XCTAssertEqual(coordinator.movementIdsUsedToday(at: harness.now), coordinator.idsServedToday(at: harness.now))
        coordinator.history.record(completion: MovementCompletion(movementId: "STR-01", at: harness.now, seconds: 60, routineId: nil))
        XCTAssertNotNil(takeBreak(harness))
        let served = coordinator.idsServedToday(at: harness.now)
        XCTAssertTrue(served.contains("STR-01"))
        XCTAssertGreaterThan(served.count, 1)
        XCTAssertEqual(coordinator.movementIdsUsedToday(at: harness.now), served, "S18: Movement is unaffected")
    }

}
