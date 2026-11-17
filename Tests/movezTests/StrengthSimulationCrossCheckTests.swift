import XCTest
@testable import movez

/// The Swift half of the strength simulation (S10): the real planner and builders, run over 200
/// fixed seeds in every equipment configuration and at the app's defaults, checked by
/// `StrengthRuleChecker` against the rule list `scripts/simulate_strength.py` uses, must break no
/// rule.
///
/// Each seed is one day of six full breaks with a micro-break before each, the strength breaks a
/// day cycling 1–4 and one strength break in ten skipped; seeds run as 5-day weeks from a fresh
/// history, so the letters, the set orders and the no-repeat rules all meet their edge cases.
final class StrengthSimulationCrossCheckTests: XCTestCase {
    private static let seeds = 200
    private static let daysPerWeek = 5

    func testTheRuleListMatchesTheSimulation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/strength-rules.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rules = try XCTUnwrap(json["rules"] as? [[String: Any]])
        let ids = rules.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, rules.count)
        XCTAssertEqual(Set(ids), Set(StrengthRuleChecker.implemented))
        XCTAssertEqual(ids.count, StrengthRuleChecker.implemented.count)
    }

    func testTwoHundredSeedsBreakNoRuleInAnyConfiguration() {
        XCTAssertEqual(StrengthSimulationRun.Configuration.all.count, 16)
        for configuration in StrengthSimulationRun.Configuration.all + [.appDefaults] {
            var outcome = StrengthSimulationRun.Outcome()
            for weekStart in stride(from: 0, to: Self.seeds, by: Self.daysPerWeek) {
                let run = StrengthSimulationRun(configuration: configuration, outcome: outcome)
                run.week(seeds: weekStart..<min(weekStart + Self.daysPerWeek, Self.seeds))
                outcome = run.outcome
            }
            XCTAssertEqual(outcome.violations, [:], "\(configuration): \(outcome.firstExample)")
            XCTAssertGreaterThan(outcome.strengthBreaks, Self.seeds, "\(configuration)")
            XCTAssertGreaterThan(outcome.endRangeBreaks, Self.seeds, "\(configuration)")
            XCTAssertEqual(outcome.microBreaks, Self.seeds * StrengthSimulationRun.fullBreaksPerDay, "\(configuration)")
        }
    }
}

/// One simulated week from a fresh history, driving the planner and the three builders the way
/// the coordinator will and checking every break they build.
private final class StrengthSimulationRun {
    static let fullBreaksPerDay = 6

    /// One configuration: equipment owned, the wall, the difficulty cap and the patterns whose
    /// difficulty-3 moves are unlocked.
    struct Configuration: CustomStringConvertible {
        let equipment: Set<StrengthEquipment>
        let wall: Bool
        let cap: Int
        var unlocked = Set(StrengthBucket.allCases)

        var description: String {
            let kit = equipment.map(\.rawValue).sorted().joined(separator: " + ")
            return "\(kit.isEmpty ? "bodyweight" : kit), \(wall ? "wall" : "no wall"), cap \(cap)"
        }

        /// The app's defaults: no equipment, a wall, Beginner, nothing unlocked. Its pools are the
        /// smallest, so it is where a long day runs out of moves and the ladders are tested hardest.
        static let appDefaults = Configuration(
            equipment: [], wall: true, cap: SettingsStore.strengthDifficultyDefault, unlocked: []
        )

        /// Dumbbells × kettlebell × wall at caps 2 and 3, every difficulty-3 pattern unlocked.
        static var all: [Configuration] {
            let kits: [Set<StrengthEquipment>] = [[], [.dumbbells], [.kettlebell], [.dumbbells, .kettlebell]]
            return [2, 3].flatMap { cap in
                kits.flatMap { kit in [true, false].map { Configuration(equipment: kit, wall: $0, cap: cap) } }
            }
        }
    }

    /// What a configuration's runs came to.
    struct Outcome {
        var violations: [String: Int] = [:]
        var firstExample: [String: String] = [:]
        var strengthBreaks = 0
        var endRangeBreaks = 0
        var microBreaks = 0

        mutating func add(_ rules: [String], _ example: @autoclosure () -> String) {
            for rule in rules {
                violations[rule, default: 0] += 1
                if firstExample[rule] == nil { firstExample[rule] = example() }
            }
        }
    }

    /// The state a day carries from break to break.
    private struct Day {
        let index: Int
        let perDay: Int
        let recency: [String: Double]
        var served: Set<String> = []
        var lastMicro: Set<String> = []
        var worked: Set<Region> = []
    }

    /// A full break as built, with the context it was built from.
    private struct Full {
        let context: StrengthContext
        var strength: StrengthBreak?
        var endRange: EndRangeBreak?

        var ids: [String] { strength?.movementIds ?? endRange?.movementIds ?? [] }
    }

    let configuration: Configuration
    private(set) var outcome: Outcome
    private let library = StrengthTestSupport.library
    private let calendar = Calendar.current
    private let usage: CrossModeUsage
    private let checker: StrengthRuleChecker
    private var records: [BreakRecord] = []
    private var plans = StrengthPlanChecker()
    private var servedByDay: [Int: [String: Int]] = [:]

    init(configuration: Configuration, outcome: Outcome) {
        self.configuration = configuration
        self.outcome = outcome
        usage = CrossModeUsage(movementLibrary: RoutineTestSupport.library, strengthLibrary: library)
        checker = StrengthRuleChecker(library: library, equipment: configuration.equipment, solidWallNearby: configuration.wall)
    }

    func week(seeds: Range<Int>) {
        for (offset, seed) in seeds.enumerated() {
            var day = Day(index: offset, perDay: 1 + seed % 4, recency: recency(before: offset))
            plans.startDay(offset, perDay: day.perDay)
            for slot in 0..<Self.fullBreaksPerDay {
                let breakSeed = UInt64(seed) &* 1_000_003 &+ UInt64(slot) &* 7_919
                let at = date(day: offset).addingTimeInterval(Double(slot) * 3600)
                fullBreakSlot(seed: breakSeed, at: at, day: &day)
            }
        }
    }

    /// A micro-break that avoids a preview of the next full break, then that full break.
    private func fullBreakSlot(seed: UInt64, at: Date, day: inout Day) {
        let plan = StrengthDayPlanner(calendar: calendar).next(records: records, strengthBreaksPerDay: day.perDay, today: at)
        let preview = buildFull(plan, seed: seed, day: day)
        microBreak(seed: seed &+ 1, nextFullBreakIds: Set(preview.ids), day: &day)

        let full = buildFull(plan, seed: seed, day: day)
        let sets = full.strength?.sets.map(\.movement.bucket) ?? []
        outcome.add(plans.check(plan, sets: sets), full.ids.joined(separator: " · "))
        if let strengthBreak = full.strength {
            outcome.add(checker.check(strengthBreak, context: full.context), full.ids.joined(separator: " · "))
            complete(strengthBreak, skipped: (seed >> 3) % 10 == 0, at: at, day: &day)
        } else if let endRange = full.endRange {
            outcome.add(checker.check(endRange, context: full.context, workedToday: day.worked), full.ids.joined(separator: " · "))
            outcome.endRangeBreaks += 1
            serve(endRange.movementIds, day: &day)
            records.append(record(at: at, kind: .endRange))
        }
    }

    private func microBreak(seed: UInt64, nextFullBreakIds: Set<String>, day: inout Day) {
        var context = StrengthMicroContext()
        context.usedStrengthIdsToday = widened(day.served)
        context.lastMicroMovementIds = day.lastMicro
        context.nextFullBreakIds = nextFullBreakIds
        context.solidWallNearby = configuration.wall
        context.difficultyCap = configuration.cap
        context.unlockedBuckets = configuration.unlocked
        context.recency = day.recency
        context.seed = seed
        let micro = StrengthMicroBuilder(library: library).build(context: context)
        outcome.microBreaks += 1
        outcome.add(checker.check(micro, context: context), micro.movementIds.joined(separator: " · "))
        serve(micro.movementIds, day: &day)
        day.lastMicro = Set(micro.movementIds)
    }

    /// Records a strength break as skipped, or as completed and served.
    private func complete(_ strengthBreak: StrengthBreak, skipped: Bool, at: Date, day: inout Day) {
        let kind = strengthBreak.letter.breakKind
        guard !skipped else {
            records.append(record(at: at, kind: kind, outcome: .skipped))
            return
        }
        outcome.strengthBreaks += 1
        records.append(record(at: at, kind: kind))
        plans.recordCompleted(letter: strengthBreak.letter, sets: strengthBreak.sets.map(\.movement.bucket))
        day.worked.formUnion(strengthBreak.workedRegions)
        serve(strengthBreak.movementIds, day: &day)
    }

    private func buildFull(_ plan: NextFullBreak, seed: UInt64, day: Day) -> Full {
        var context = StrengthContext()
        context.usedStrengthIdsToday = widened(day.served)
        context.equipment = configuration.equipment
        context.solidWallNearby = configuration.wall
        context.difficultyCap = configuration.cap
        context.unlockedBuckets = configuration.unlocked
        context.recency = day.recency
        context.seed = seed
        var full = Full(context: context)
        if case let .strength(letter, _, _, setOrder) = plan {
            full.strength = StrengthBreakBuilder(library: library).build(letter: letter, setOrder: setOrder, context: context)
        } else {
            full.endRange = EndRangeBreakBuilder(library: library).build(context: context, avoidingRegions: day.worked)
        }
        return full
    }

    private func widened(_ served: Set<String>) -> Set<String> {
        usage.used(movementIds: [], strengthIds: served).strengthIds
    }

    private func serve(_ ids: [String], day: inout Day) {
        day.served.formUnion(ids)
        for id in ids { servedByDay[day.index, default: [:]][id, default: 0] += 1 }
    }

    /// Recency scores as the app keeps them: each serving in the last three days, most for
    /// yesterday.
    private func recency(before day: Int) -> [String: Double] {
        var scores: [String: Double] = [:]
        for back in 1...Recency.horizonDays {
            for (id, count) in servedByDay[day - back] ?? [:] {
                scores[id, default: 0] += Double(count) * Recency.weight(daysAgo: back)
            }
        }
        return scores
    }

    private func date(day offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: SchedulerHarness.mondayMorning) ?? SchedulerHarness.mondayMorning
    }

    private func record(at: Date, kind: BreakKind, outcome: BreakResult = .done) -> BreakRecord {
        BreakRecord(at: at, routineName: BreakRecord.movementBreakName, outcome: outcome, completedBlocks: 1, totalBlocks: 1, kind: kind)
    }
}
