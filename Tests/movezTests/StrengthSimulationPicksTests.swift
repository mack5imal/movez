import XCTest
@testable import movez

/// Holds `scripts/simulate_strength.py` to the app: the script writes, for four days of every
/// configuration it simulates, each break's explicit context and the moves it drew, and this
/// rebuilds every one with the Swift planner and builders. The plan, the moves in order and the
/// rules let go must all be the same, so a change to a builder, a ladder, the focus weight or the
/// planner that the script does not mirror fails here rather than leaving
/// `docs/strength-simulation.md` describing code that no longer exists (TST-1).
///
/// The fixture is the script's output, not a record to protect: after a deliberate change to the
/// strength rules, re-run `python3 -I scripts/simulate_strength.py` (or `make simulate`) and commit
/// what it writes. `make simulate-check` fails when the committed fixture or report is stale.
final class StrengthSimulationPicksTests: XCTestCase {
    struct Fixture: Decodable {
        let configurations: [Configuration]
    }

    struct Configuration: Decodable {
        let name: String
        let equipment: [String]
        let wall: Bool
        let cap: Int
        let unlocked: [String]
        let focus: String
        let days: [Day]
    }

    struct Day: Decodable {
        let day: Int
        let perDay: Int
        let recency: [String: Double]
        let events: [Event]
    }

    struct Event: Decodable {
        let kind: String
        let seed: String
        let used: [String]
        let ids: [String]
        let relaxed: [String]
        var lastMicro: [String]?
        var nextFull: [String]?
        var plan: String?
        var avoiding: [String]?
        var skipped: Bool?
    }

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("strength-simulation-picks.json")

    private let library = StrengthTestSupport.library
    private let calendar = Calendar.current

    func testTheSimulationDrawsWhatTheAppDraws() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        XCTAssertGreaterThanOrEqual(fixture.configurations.count, 20)
        var compared = 0
        var arms = 0
        for configuration in fixture.configurations {
            var mismatches: [String] = []
            compared += try replay(configuration, mismatches: &mismatches, arms: &arms)
            XCTAssertEqual(mismatches, [], configuration.name)
        }
        XCTAssertGreaterThan(compared, 500)
        XCTAssertGreaterThan(arms, 0, "the fixture reaches the arm break")
    }

    /// Replays one configuration's days in order, writing a record for each full break the way
    /// the script counts it, so the planner reads the same history. Returns the breaks compared.
    private func replay(_ configuration: Configuration, mismatches: inout [String], arms: inout Int) throws -> Int {
        let equipment = Set(try configuration.equipment.map { try XCTUnwrap(StrengthEquipment(rawValue: $0)) })
        let unlocked = Set(try configuration.unlocked.map { try XCTUnwrap(StrengthBucket(rawValue: $0)) })
        let focus = try XCTUnwrap(StrengthFocus(rawValue: configuration.focus))
        var records: [BreakRecord] = []
        var compared = 0
        for day in configuration.days {
            let date = calendar.date(byAdding: .day, value: day.day, to: SchedulerHarness.mondayMorning) ?? SchedulerHarness.mondayMorning
            var slot = 0
            for event in day.events {
                let seed = try XCTUnwrap(UInt64(event.seed))
                let label = "day \(day.day) \(event.kind) \(compared)"
                compared += 1
                if event.kind == "micro" {
                    let micro = microBreak(event, seed: seed, day: day, configuration: configuration, unlocked: unlocked)
                    compare(label, micro.blocks.map(\.movement.id), micro.relaxed, event, &mismatches)
                    continue
                }

                let at = date.addingTimeInterval(Double(slot) * 3600)
                slot += 1
                let plan = StrengthDayPlanner(calendar: calendar).next(
                    records: records,
                    strengthBreaksPerDay: day.perDay,
                    focus: focus,
                    armBreakPossible: StrengthDayPlanner.armBreakPossible(equipment: equipment),
                    today: at
                )
                if Self.code(plan) != event.plan { mismatches.append("\(label): plan \(Self.code(plan)) ≠ \(event.plan ?? "")") }

                var context = StrengthContext()
                context.usedStrengthIdsToday = Set(event.used)
                context.equipment = equipment
                context.solidWallNearby = configuration.wall
                context.difficultyCap = configuration.cap
                context.unlockedBuckets = unlocked
                context.focus = focus
                context.recency = day.recency
                context.seed = seed
                if case let .strength(letter, _, _, setOrder) = plan {
                    if setOrder.contains(where: \.isArm) { arms += 1 }
                    let built = StrengthBreakBuilder(library: library).build(letter: letter, setOrder: setOrder, context: context)
                    let ids = [built.warmUp.movement.id] + built.sets.map(\.movement.id) + [built.coolDown.movement.id]
                    compare(label, ids, built.relaxed, event, &mismatches)
                    let outcome: BreakResult = event.skipped == true ? .skipped : .done
                    records.append(record(at: at, kind: letter.breakKind, outcome: outcome))
                } else {
                    let avoiding = Set(try (event.avoiding ?? []).map { try XCTUnwrap(Region(rawValue: $0)) })
                    let built = EndRangeBreakBuilder(library: library).build(context: context, avoidingRegions: avoiding)
                    compare(label, built.blocks.map(\.movement.id), built.relaxed, event, &mismatches)
                    records.append(record(at: at, kind: .endRange, outcome: .done))
                }
            }
        }
        return compared
    }

    private func microBreak(
        _ event: Event, seed: UInt64, day: Day, configuration: Configuration, unlocked: Set<StrengthBucket>
    ) -> StrengthMicroBreak {
        var context = StrengthMicroContext()
        context.usedStrengthIdsToday = Set(event.used)
        context.lastMicroMovementIds = Set(event.lastMicro ?? [])
        context.nextFullBreakIds = Set(event.nextFull ?? [])
        context.solidWallNearby = configuration.wall
        context.difficultyCap = configuration.cap
        context.unlockedBuckets = unlocked
        context.recency = day.recency
        context.seed = seed
        return StrengthMicroBuilder(library: library).build(context: context)
    }

    private func compare(
        _ label: String,
        _ ids: [String],
        _ relaxed: [StrengthRelaxation],
        _ event: Event,
        _ mismatches: inout [String]
    ) {
        if ids != event.ids { mismatches.append("\(label): drew \(ids), the script \(event.ids)") }
        let codes = relaxed.map(Self.code)
        if codes != event.relaxed { mismatches.append("\(label): let go \(codes), the script \(event.relaxed)") }
    }

    /// A plan as the script writes it: "endRange", or the letter and the set order.
    static func code(_ plan: NextFullBreak) -> String {
        guard case let .strength(letter, _, _, setOrder) = plan else { return "endRange" }
        return ([letter.rawValue] + setOrder.map(code)).joined(separator: " ")
    }

    static func code(_ slot: StrengthSetSlot) -> String {
        switch slot {
        case let .pattern(bucket): return "pattern:\(bucket.rawValue)"
        case .core: return "core"
        case let .arm(bucket): return "arm:\(bucket.rawValue)"
        case let .armAlternate(bucket): return "armAlternate:\(bucket.rawValue)"
        }
    }

    /// A relaxation as the script writes it: "set2:breakLimits".
    static func code(_ relaxation: StrengthRelaxation) -> String {
        let slot: String
        switch relaxation.slot {
        case .warmUp: slot = "warmUp"
        case let .set(number): slot = "set\(number)"
        case .coolDown: slot = "coolDown"
        case let .block(number): slot = "block\(number)"
        }
        return "\(slot):\(relaxation.rule.rawValue)"
    }

    private func record(at: Date, kind: BreakKind, outcome: BreakResult) -> BreakRecord {
        BreakRecord(at: at, routineName: BreakRecord.movementBreakName, outcome: outcome, completedBlocks: 1, totalBlocks: 1, kind: kind)
    }
}
