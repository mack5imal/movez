import XCTest
@testable import movez

/// The edges of a Strength day the polish pass checks end to end through the coordinator: a
/// bodyweight-only setup, a mode switch during the session kinds the other tests do not cover, a
/// relaunch part-way through the day, the four-strength-break day and the arm break.
@MainActor
final class StrengthEdgeTests: XCTestCase {
    private let minute: TimeInterval = 60

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

    // MARK: - Bodyweight only

    /// The setup may be confirmed with nothing ticked and the wall off; every break that day is
    /// still built, in full, from bodyweight moves that need no wall.
    func testABodyweightOnlySetupWithTheWallOffBuildsEveryBreakOfTheDay() throws {
        let harness = strengthHarness(perDay: 4) { settings in
            settings.strengthEquipment = []
            settings.strengthSolidWallNearby = false
        }
        let library = RoutineTestSupport.strengthLibrary
        for index in 0..<6 {
            let session = try XCTUnwrap(takeBreak(harness), "break \(index + 1) was never offered")
            let ids = session.planned.movementIds
            XCTAssertFalse(ids.isEmpty, "break \(index + 1) is empty")
            for id in ids {
                let movement = try XCTUnwrap(library.movement(id: id))
                XCTAssertTrue(movement.isBodyweight, "\(id) needs equipment the user does not own")
                XCTAssertFalse(movement.settings.contains(.wall), "\(id) needs a wall the user does not have")
            }
            if let strengthBreak = session.planned.strengthBreak {
                XCTAssertEqual(strengthBreak.sets.count, 3)
            } else {
                XCTAssertEqual(session.planned.endRangeBreak?.blocks.count, 4)
            }
        }
        XCTAssertEqual(kinds(harness), [.strengthA, .strengthA, .strengthA, .strengthA, .endRange, .endRange])
    }

    // MARK: - A switch during each kind of session

    func testSwitchingDuringAnEndRangeBreakKeepsTheBreakOnScreen() throws {
        let harness = strengthHarness(perDay: 1)
        takeBreak(harness)
        XCTAssertTrue(harness.run(until: { $0.isHeadsUp }))
        harness.coordinator.startNow()
        let session = try XCTUnwrap(harness.coordinator.currentBreak)
        XCTAssertNotNil(session.planned.endRangeBreak)
        harness.clock.advance(60)
        harness.coordinator.nextBlock()

        switchMode(harness, to: .movement)
        harness.coordinator.tick()

        let current = try XCTUnwrap(harness.coordinator.currentBreak)
        XCTAssertEqual(current.planned, session.planned)
        XCTAssertEqual(current.mode, .strength)
        harness.completeBreak()

        let next = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(next.mode, .movement)
        XCTAssertEqual(kinds(harness), [.strengthA, .endRange, .movement])
    }

    func testSwitchingDuringAStrengthMicroBreakKeepsItAndTheNextOneIsMovement() throws {
        let harness = strengthHarness(micro: true)
        XCTAssertTrue(harness.run(until: { $0.isMicroCountIn }, limit: 40 * minute))
        let micro = try XCTUnwrap(harness.coordinator.currentMicro)
        XCTAssertNotNil(micro.strengthMicro)
        XCTAssertEqual(harness.coordinator.currentMicroMode, .strength)

        switchMode(harness, to: .movement)
        XCTAssertTrue(harness.run(until: { $0.isMicroRunning }, limit: minute))
        XCTAssertEqual(harness.coordinator.currentMicro, micro)
        XCTAssertEqual(harness.coordinator.currentMicroMode, .strength)
        harness.clock.advance(70)
        harness.coordinator.microEnded()
        XCTAssertNil(harness.coordinator.currentMicro)

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
        XCTAssertNotNil(next.movementMicro, "the next micro-break is built in the new mode")
        XCTAssertEqual(harness.coordinator.currentMicroMode, .movement)
    }

    // MARK: - Relaunch

    /// A relaunch after two of the day's three strength breaks keeps the day's letter and count:
    /// the third break is still a strength break, and the fourth is end-range.
    func testARelaunchMidDayKeepsTheLetterAndTheCount() throws {
        let harness = strengthHarness(perDay: 3)
        takeBreak(harness)
        takeBreak(harness)
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.breakNumber, 3)

        harness.relaunch()

        let progress = try XCTUnwrap(harness.coordinator.menuState.dayProgress)
        XCTAssertEqual(progress.dayLetter, .dayA)
        XCTAssertEqual(progress.breakNumber, 3)
        XCTAssertEqual(progress.breaksPerDay, 3)
        let third = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(third.planned.kind, .strengthA)
        XCTAssertNil(harness.coordinator.menuState.dayProgress?.breakNumber, "the day's strength breaks are done")
        let fourth = try XCTUnwrap(takeBreak(harness))
        XCTAssertEqual(fourth.planned.kind, .endRange)
    }

    // MARK: - Four strength breaks

    func testAFourStrengthBreakDayServesFourStrengthBreaksThenEndRange() throws {
        let harness = strengthHarness(perDay: 4)
        var progress: [Int?] = []
        var shapes: [[StrengthBucket]] = []
        for _ in 0..<5 {
            progress.append(harness.coordinator.menuState.dayProgress?.breakNumber)
            let session = try XCTUnwrap(takeBreak(harness))
            if let sets = session.planned.strengthBreak?.sets { shapes.append(sets.map(\.movement.bucket)) }
        }
        XCTAssertEqual(kinds(harness), [.strengthA, .strengthA, .strengthA, .strengthA, .endRange])
        XCTAssertEqual(progress, [1, 2, 3, 4, nil])
        XCTAssertEqual(shapes.first, [.sqt, .psh, .cor], "the first break ends on core")
        XCTAssertEqual(shapes.last, [.tri, .tri, .tri], "the fourth is the push day's arm break")
        for shape in shapes.dropFirst().dropLast() {
            XCTAssertEqual(shape.first, shape.last, "a later break repeats its lead pattern: \(shape)")
            XCTAssertEqual(Set(shape), [.sqt, .psh])
        }
    }

    // MARK: - Arm break

    /// At four a day the fourth break is the arm break, recorded like any other A-day break.
    func testAFourBreakDaysFourthBreakIsTheTricepsArmBreak() throws {
        let harness = strengthHarness(perDay: 4)
        var sessions: [BreakSession] = []
        for _ in 0..<4 { sessions.append(try XCTUnwrap(takeBreak(harness))) }
        XCTAssertEqual(kinds(harness), Array(repeating: .strengthA, count: 4))

        let sets = try XCTUnwrap(sessions[3].planned.strengthBreak?.sets).map(\.movement)
        XCTAssertEqual(sets.map(\.bucket), [.tri, .tri, .tri])
        XCTAssertEqual(sets[0].id, sets[1].id)
        // At the default Beginner cap with no kit TRI-05 is the triceps bucket's one move, so the
        // third set repeats it rather than serving a move above the cap, and says so (DECISIONS 82).
        XCTAssertEqual(sets.map(\.id), ["TRI-05", "TRI-05", "TRI-05"])
        XCTAssertTrue(sets.allSatisfy { $0.difficulty <= SettingsStore.strengthDifficultyDefault })
        let relaxed = try XCTUnwrap(sessions[3].planned.strengthBreak?.relaxed)
        XCTAssertTrue(relaxed.contains(StrengthRelaxation(slot: .set(3), rule: .armAlternate)), "\(relaxed)")
        XCTAssertEqual(sessions[3].planned.strengthBreak?.warmUp.movement.bucket, .psh)
        for session in sessions.prefix(3) {
            let buckets = try XCTUnwrap(session.planned.strengthBreak?.sets).map(\.movement.bucket)
            XCTAssertTrue(Set(buckets).isSubset(of: [.sqt, .psh, .cor]), "\(buckets)")
        }
    }

    func testMoreArmsMakesAThreeBreakDaysThirdBreakTheArmBreak() throws {
        let harness = strengthHarness(perDay: 3) { $0.strengthFocus = .moreArms }
        var sessions: [BreakSession] = []
        for _ in 0..<3 { sessions.append(try XCTUnwrap(takeBreak(harness))) }
        XCTAssertEqual(kinds(harness), Array(repeating: .strengthA, count: 3))
        let buckets = try XCTUnwrap(sessions[2].planned.strengthBreak?.sets).map(\.movement.bucket)
        XCTAssertEqual(buckets, [.tri, .tri, .tri])
        XCTAssertEqual(harness.coordinator.menuState.dayProgress?.breakNumber, nil, "the day's strength breaks are done")
    }

    /// The micro-break after a switch still leaves the previous one's regions alone, whichever
    /// library that one came from (S7, LIB-15).
    func testAMicroBreakAfterASwitchKnowsThePreviousOnesRegions() throws {
        let harness = strengthHarness(micro: true)
        let coordinator = harness.coordinator
        let shoulder = try XCTUnwrap(RoutineTestSupport.library.microEligible.first { $0.regions == [.shoulder] })
        coordinator.lastMicroIds = [shoulder.id]
        let builder = StrengthModeBuilder(
            library: RoutineTestSupport.strengthLibrary,
            usage: CrossModeUsage(movementLibrary: RoutineTestSupport.library, strengthLibrary: RoutineTestSupport.strengthLibrary)
        )
        var context = builder.microContext(for: coordinator, at: harness.now, nextFullBreakIds: [])
        XCTAssertEqual(context.lastMicroRegions, [.shoulder])
        for seed in 0..<100 {
            context.seed = UInt64(seed)
            let micro = StrengthMicroBuilder(library: RoutineTestSupport.strengthLibrary).build(context: context)
            XCTAssertFalse(micro.blocks.contains { $0.movement.regions.contains(.shoulder) }, "\(micro.movementIds)")
        }

        // And the other way: a Movement micro-break after a strength one leaves its `same` twin alone.
        let twin = try XCTUnwrap(RoutineTestSupport.strengthLibrary.movements.first { $0.bucket == .end && $0.v4Overlap?.kind == .same })
        coordinator.lastMicroIds = [twin.id]
        XCTAssertTrue(coordinator.lastMicroMovementIds().contains(try XCTUnwrap(twin.v4Overlap?.id)))
    }
}
