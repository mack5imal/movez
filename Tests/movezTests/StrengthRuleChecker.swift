import Foundation
@testable import movez

/// Checks built strength breaks, end-range breaks and micro-breaks against the rule list in
/// `scripts/strength-rules.json`, the same list `scripts/simulate_strength.py` checks, so the
/// simulation and this cross-check agree on what a violation is.
///
/// It is written against the rules, not the builders: a hard rule is broken whenever a break
/// breaks it, and a where-possible rule only when another move that keeps it, and keeps every other
/// rule the served move keeps, was available for the same slot. Running short of moves late in a
/// long day is what the builders' relaxation ladders are for, and is not a violation.
struct StrengthRuleChecker {
    /// Every rule id this checker can report; `StrengthSimulationCrossCheckTests` holds it to the
    /// JSON's list.
    static let implemented: [String] = [
        "s6-shape", "s6-day-patterns", "s6-lead", "s6-same-move-twice", "s6-distinct",
        "s6-warm-up-pattern", "s6-warm-up-shape", "s6-warm-up-timing", "s6-cool-down-end",
        "s6-cool-down-region", "s6-per-side-limit", "s6-floor-limit", "s6-grip-limit", "s6-equipment",
        "s6-wall", "s6-served-today", "s6-excluded", "s6-difficulty", "s6-dose",
        "s6-arm-break", "s6-arm-alternate", "s6-vigorous-sets",
        "s7-end-only", "s7-no-floor", "s7-wall", "s7-distinct", "s7-shape", "s7-same-posture",
        "s7-previous-region", "s7-next-break-region", "s7-served-today", "s7-excluded", "s7-difficulty",
        "s22-letter", "s22-count", "s22-end-range-shape", "s22-end-range-distinct", "s22-end-range-wall",
        "s22-end-range-served-today", "s22-end-range-worked-regions", "s22-end-range-excluded",
        "s22-end-range-difficulty", "s22-arm-break-position"
    ]

    /// One where-possible rule: its id and whether a move keeps it.
    struct Rule {
        let id: String
        let keeps: (StrengthMovement) -> Bool
    }

    let library: StrengthLibrary
    let equipment: Set<StrengthEquipment>
    let solidWallNearby: Bool

    /// The where-possible rules `pick` broke needlessly: those some other move in `universe` keeps
    /// together with every rule `pick` keeps. `usable` narrows which such moves count.
    static func needlessBreaks(
        _ pick: StrengthMovement,
        universe: [StrengthMovement],
        rules: [Rule],
        usable: ((StrengthMovement, [Rule]) -> Bool)? = nil
    ) -> [String] {
        let kept = rules.filter { $0.keeps(pick) }
        return rules.filter { !$0.keeps(pick) }.compactMap { rule in
            let need = kept + [rule]
            let found = universe.contains { candidate in
                candidate.id != pick.id && need.allSatisfy { $0.keeps(candidate) } && (usable?(candidate, need) ?? true)
            }
            return found ? rule.id : nil
        }
    }

    private func isPossible(_ movement: StrengthMovement, equipment: Set<StrengthEquipment>? = nil) -> Bool {
        StrengthEligibility.isPossible(movement, equipment: equipment ?? self.equipment, solidWallNearby: solidWallNearby)
    }

    private func shared(_ prefix: String, used: Set<String>, excluded: Set<String>, cap: Int, unlocked: Set<StrengthBucket>) -> [Rule] {
        [
            Rule(id: "\(prefix)-served-today") { !used.contains($0.id) },
            Rule(id: "\(prefix)-excluded") { !excluded.contains($0.id) },
            Rule(id: "\(prefix)-difficulty") { Self.isWithinDifficulty($0, cap: cap, unlocked: unlocked) }
        ]
    }

    // MARK: - The rules' own predicates

    // Written out from the rule text in strength-rules.json, not borrowed from the builders, so a
    // bug in a builder's predicate shows up here as a violation instead of agreeing with itself.

    /// s6-difficulty, s7-difficulty, s22-end-range-difficulty: "Difficulty at most the cap, and
    /// difficulty 3 only in an unlocked pattern."
    static func isWithinDifficulty(_ movement: StrengthMovement, cap: Int, unlocked: Set<StrengthBucket>) -> Bool {
        movement.difficulty <= cap && (movement.difficulty < 3 || unlocked.contains(movement.bucket))
    }

    /// s6-warm-up-shape: "The warm-up is bodyweight, not on the floor, difficulty 1 and two-sided."
    static func isWarmUpShaped(_ movement: StrengthMovement) -> Bool {
        movement.equipment.isEmpty && !movement.onFloor && movement.difficulty == 1 && !movement.perSide
    }

    /// s7-same-posture: a move done from a chair is seated; anything else is standing.
    static func isSeated(_ movement: StrengthMovement) -> Bool {
        movement.settings.contains(.chair)
    }

    /// A micro-break's second move: a different move, two-sided, in the first one's posture.
    static func isPartner(_ candidate: StrengthMovement, of first: StrengthMovement) -> Bool {
        candidate.id != first.id && !candidate.perSide && isSeated(candidate) == isSeated(first)
    }

    // MARK: - Strength breaks

    /// The regions an arm break's cool-down may stretch, written out from the rule rather than
    /// read from the builder.
    static let armCoolDownRegions: Set<Region> = [.shoulder, .chest, .arm, .wristForearm]

    /// The pattern a break's warm-up must come from: the first set's, or for an arm break the
    /// day's push (A) or pull (B).
    private static func warmUpBucket(_ strengthBreak: StrengthBreak, isArmBreak: Bool) -> StrengthBucket? {
        isArmBreak ? (strengthBreak.letter == .dayA ? .psh : .pul) : strengthBreak.sets.first?.movement.bucket
    }

    /// `setOrder` is the plan's slots the break was built from; an arm break is told by them.
    func check(_ strengthBreak: StrengthBreak, setOrder: [StrengthSetSlot], context: StrengthContext) -> [String] {
        hardViolations(strengthBreak, setOrder: setOrder) + softViolations(strengthBreak, setOrder: setOrder, context: context)
    }

    private func hardViolations(_ strengthBreak: StrengthBreak, setOrder: [StrengthSetSlot]) -> [String] {
        var out: [String] = []
        let warmUp = strengthBreak.warmUp
        let coolDown = strengthBreak.coolDown
        let moves = strengthBreak.sets.map(\.movement)
        let isArmBreak = setOrder.contains(where: \.isArm)
        if moves.count != 3 { out.append("s6-shape") }
        out += slotViolations(moves, setOrder: setOrder)
        let ids = [warmUp.movement.id] + distinct(moves).map(\.id) + [coolDown.movement.id]
        if Set(ids).count != ids.count { out.append("s6-distinct") }
        if warmUp.movement.bucket != Self.warmUpBucket(strengthBreak, isArmBreak: isArmBreak) {
            out.append("s6-warm-up-pattern")
        }
        if warmUp.seconds != 30 { out.append("s6-warm-up-timing") }
        if coolDown.movement.bucket != .end || coolDown.seconds != 30 { out.append("s6-cool-down-end") }
        for movement in [warmUp.movement, coolDown.movement] + moves {
            if !movement.isBodyweight, equipment.isDisjoint(with: movement.equipment) { out.append("s6-equipment") }
            if !solidWallNearby, movement.settings.contains(.wall) { out.append("s6-wall") }
        }
        // `StrengthSet.init` copies the library's dose, so this holds by construction and is
        // kept as the rule list's record of S4 rather than as a check that could catch a builder.
        if strengthBreak.sets.contains(where: { $0.dose != library.movement(id: $0.movement.id)?.dose }) {
            out.append("s6-dose")
        }
        return out
    }

    /// The same slot twice is the same move and two different slots are two different moves; an
    /// arm break's third set is a different move from its first two's bucket.
    private func slotViolations(_ moves: [StrengthMovement], setOrder: [StrengthSetSlot]) -> [String] {
        var out: [String] = []
        let pairs = moves.indices.flatMap { first in moves.indices.filter { $0 > first }.map { (first, $0) } }
        if setOrder.count != moves.count
            || pairs.contains(where: { (setOrder[$0.0] == setOrder[$0.1]) != (moves[$0.0].id == moves[$0.1].id) }) {
            out.append("s6-same-move-twice")
        }
        if setOrder.contains(where: \.isArm),
           moves.count != 3 || moves[2].bucket != moves[0].bucket || moves[2].id == moves[0].id {
            out.append("s6-arm-alternate")
        }
        return out
    }

    private func softViolations(
        _ strengthBreak: StrengthBreak, setOrder: [StrengthSetSlot], context: StrengthContext
    ) -> [String] {
        let shared = shared(
            "s6", used: context.usedStrengthIdsToday, excluded: context.excluded,
            cap: context.difficultyCap, unlocked: context.unlockedBuckets
        )
        let warmUp = strengthBreak.warmUp.movement
        let moves = strengthBreak.sets.map(\.movement)
        let isArmBreak = setOrder.contains(where: \.isArm)
        let warmUpBucket = Self.warmUpBucket(strengthBreak, isArmBreak: isArmBreak) ?? warmUp.bucket
        var out = Self.needlessBreaks(
            warmUp,
            universe: library.movements(in: warmUpBucket).filter { isPossible($0) },
            rules: [Rule(id: "s6-warm-up-shape", keeps: Self.isWarmUpShaped)] + shared
        )
        // With any kit selected a working set should be vigorous; bodyweight-only has no such rule.
        let vigorous = equipment.isEmpty ? [] : [Rule(id: "s6-vigorous-sets") { $0.vigorous }]
        var earlier: [StrengthMovement] = []
        for movement in distinct(moves) {
            let taken = Set(earlier.map(\.id)).union([warmUp.id])
            let chosen = earlier
            let limits = [
                Rule(id: "s6-per-side-limit") { !($0.perSide && chosen.contains(where: \.perSide)) },
                Rule(id: "s6-floor-limit") { !($0.onFloor && chosen.contains(where: \.onFloor)) },
                Rule(id: "s6-grip-limit") { !($0.gripDemand && chosen.contains(where: \.gripDemand)) }
            ]
            let universe = library.movements(in: movement.bucket).filter { isPossible($0) && !taken.contains($0.id) }
            out += Self.needlessBreaks(movement, universe: universe, rules: limits + vigorous + shared)
            earlier.append(movement)
        }
        let worked = isArmBreak ? Self.armCoolDownRegions : Set(moves.flatMap(\.regions))
        let taken = Set(moves.map(\.id)).union([warmUp.id])
        let coolUniverse = library.movements(in: .end).filter { isPossible($0) && !taken.contains($0.id) }
        let region = Rule(id: "s6-cool-down-region") { !worked.isDisjoint(with: $0.regions) }
        out += Self.needlessBreaks(strengthBreak.coolDown.movement, universe: coolUniverse, rules: [region] + shared)
        return out
    }

    private func distinct(_ moves: [StrengthMovement]) -> [StrengthMovement] {
        var seen = Set<String>()
        return moves.filter { seen.insert($0.id).inserted }
    }

    // MARK: - End-range breaks

    func check(_ endRange: EndRangeBreak, context: StrengthContext, workedToday: Set<Region>) -> [String] {
        var out: [String] = []
        let moves = endRange.blocks.map(\.movement)
        if moves.count != 4 || endRange.blocks.contains(where: { $0.movement.bucket != .end || $0.seconds != 60 }) {
            out.append("s22-end-range-shape")
        }
        if Set(moves.map(\.id)).count != moves.count { out.append("s22-end-range-distinct") }
        if !solidWallNearby, moves.contains(where: { $0.settings.contains(.wall) }) { out.append("s22-end-range-wall") }
        let rules = shared(
            "s22-end-range", used: context.usedStrengthIdsToday, excluded: context.excluded,
            cap: context.difficultyCap, unlocked: context.unlockedBuckets
        ) + [Rule(id: "s22-end-range-worked-regions") { workedToday.isDisjoint(with: $0.regions) }]
        for (index, movement) in moves.enumerated() {
            let taken = Set(moves.prefix(index).map(\.id))
            let universe = library.movements(in: .end).filter { isPossible($0, equipment: []) && !taken.contains($0.id) }
            out += Self.needlessBreaks(movement, universe: universe, rules: rules)
        }
        return out
    }

    // MARK: - Micro-breaks

    func check(_ micro: StrengthMicroBreak, context: StrengthMicroContext) -> [String] {
        let moves = micro.blocks.map(\.movement)
        var out: [String] = []
        if moves.contains(where: { $0.bucket != .end }) { out.append("s7-end-only") }
        if moves.contains(where: \.onFloor) { out.append("s7-no-floor") }
        if !solidWallNearby, moves.contains(where: { $0.settings.contains(.wall) }) { out.append("s7-wall") }
        if Set(moves.map(\.id)).count != moves.count { out.append("s7-distinct") }
        if moves.count == 2, Self.isSeated(moves[0]) != Self.isSeated(moves[1]) { out.append("s7-same-posture") }
        guard let first = moves.first else { return out + ["s7-shape"] }

        let pool = library.microEligible.filter { $0.bucket == .end && !$0.onFloor && isPossible($0, equipment: []) }
        let ladder = microLadderRules(context)
        let upcoming = regions(of: context.nextFullBreakIds)
        let rules = ladder + [Rule(id: "s7-next-break-region") { upcoming.isDisjoint(with: $0.regions) }]
        let ladderIds = Set(ladder.map(\.id))
        // A first move is only an alternative when it makes a whole micro-break: per-side, or with
        // a partner keeping the same rules, the next-break preference aside.
        let opener: (StrengthMovement, [Rule]) -> Bool = { candidate, need in
            let kept = need.filter { ladderIds.contains($0.id) }
            return candidate.perSide || pool.contains { partner in
                Self.isPartner(partner, of: candidate) && kept.allSatisfy { $0.keeps(partner) }
            }
        }
        out += Self.needlessBreaks(first, universe: pool, rules: rules, usable: opener)
        out += shapeViolations(micro, pool: pool, ladder: ladder)
        if moves.count == 2 {
            let partners = pool.filter { Self.isPartner($0, of: first) }
            out += Self.needlessBreaks(moves[1], universe: partners, rules: rules)
        }
        return out
    }

    private func microLadderRules(_ context: StrengthMicroContext) -> [Rule] {
        let previous = regions(of: context.lastMicroMovementIds)
        return [
            Rule(id: "s7-served-today") { !context.usedStrengthIdsToday.contains($0.id) },
            Rule(id: "s7-previous-region") { previous.isDisjoint(with: $0.regions) },
            Rule(id: "s7-excluded") { !context.excluded.contains($0.id) },
            Rule(id: "s7-difficulty") {
                Self.isWithinDifficulty($0, cap: context.difficultyCap, unlocked: context.unlockedBuckets)
            }
        ]
    }

    private func shapeViolations(_ micro: StrengthMicroBreak, pool: [StrengthMovement], ladder: [Rule]) -> [String] {
        let blocks = micro.blocks
        guard let first = blocks.first?.movement else { return [] }
        switch blocks.count {
        case 1:
            guard blocks[0].seconds == 60 else { return ["s7-shape"] }
            guard !first.perSide else { return [] }
            // Alone for the minute only when nothing could have made a proper micro-break.
            let kept = ladder.filter { $0.keeps(first) }
            let better = pool.contains { candidate in
                (candidate.perSide || Self.isPartner(candidate, of: first)) && kept.allSatisfy { $0.keeps(candidate) }
            }
            return better ? ["s7-shape"] : []
        case 2:
            let twoSided = blocks.allSatisfy { !$0.movement.perSide && $0.seconds == 30 }
            return twoSided ? [] : ["s7-shape"]
        default:
            return ["s7-shape"]
        }
    }

    private func regions(of ids: Set<String>) -> Set<Region> {
        Set(ids.compactMap { library.movement(id: $0) }.flatMap(\.regions))
    }
}

/// The planner rules (S22 letters, counts and the arm break's place, S6 set orders), judged from
/// the completed breaks alone rather than by asking the planner again.
struct StrengthPlanChecker {
    /// Where an arm break falls, from the rules alone: the fourth break, or the third under More
    /// arms, and none for a kit with equipment but no dumbbells.
    let armPosition: Int?
    private var letters: [Int: StrengthDayLetter] = [:]
    /// Each pattern's last lead, as the index of the completed break that led with it.
    private var lastLed: [StrengthBucket: Int] = [:]
    private var completed = 0
    private var day = 0
    private var perDay = 0
    private var doneToday = 0
    /// Today's completed pattern breaks, and their sets: an arm break counts toward neither.
    private var patternBreaksToday = 0
    private var setsToday: [StrengthBucket: Int] = [:]

    init(focus: StrengthFocus, equipment: Set<StrengthEquipment>) {
        let possible = equipment.isEmpty || equipment.contains(.dumbbells)
        armPosition = possible ? (focus == .moreArms ? 2 : 3) : nil
    }

    mutating func startDay(_ day: Int, perDay: Int) {
        self.day = day
        self.perDay = perDay
        doneToday = 0
        patternBreaksToday = 0
        setsToday = [:]
    }

    func expectedLetter() -> StrengthDayLetter {
        if let letter = letters[day] { return letter }
        guard let previous = letters.keys.filter({ $0 < day }).max(), let letter = letters[previous] else { return .dayA }
        return letter.other
    }

    /// Today's arm break index: the position, only when the day has more breaks than it.
    private var armIndex: Int? {
        guard let armPosition, perDay > armPosition else { return nil }
        return armPosition
    }

    /// The planner rules `plan` breaks, `sets` being the patterns of the break built from it.
    func check(_ plan: NextFullBreak, sets: [StrengthBucket]) -> [String] {
        guard case let .strength(letter, _, _, setOrder) = plan else {
            return doneToday < perDay ? ["s22-count"] : []
        }
        var out: [String] = []
        if doneToday >= perDay { out.append("s22-count") }
        let expected = expectedLetter()
        if letter != expected { out.append("s22-letter") }
        let isArmBreak = setOrder.contains(where: \.isArm)
        if isArmBreak != (doneToday == armIndex) { out.append("s22-arm-break-position") }
        if isArmBreak {
            let arm: StrengthBucket = expected == .dayA ? .tri : .bic
            let shaped = setOrder == [.arm(arm), .arm(arm), .armAlternate(arm)] && sets == [arm, arm, arm]
            return shaped ? out : out + ["s6-arm-break"]
        }
        let (first, second) = expected.patterns
        if patternBreaksToday == 0 {
            return sets == [first, second, .cor] ? out : out + ["s6-day-patterns"]
        }
        guard sets.count == 3, sets[0] == sets[2], Set(sets.prefix(2)) == [first, second] else {
            return out + ["s6-day-patterns"]
        }
        return out + leadViolations(lead: sets[0], other: sets[1], first: first)
    }

    /// A later break leads with the pattern that has fewer sets so far today; a tie goes to the
    /// one that led less recently, and to the day's first pattern when neither has ever led.
    private func leadViolations(lead: StrengthBucket, other: StrengthBucket, first: StrengthBucket) -> [String] {
        let leadSets = setsToday[lead] ?? 0
        let otherSets = setsToday[other] ?? 0
        if leadSets != otherSets { return leadSets > otherSets ? ["s6-lead"] : [] }
        let led = lastLed[lead] ?? -1
        let otherLed = lastLed[other] ?? -1
        return led > otherLed || (led == otherLed && lead != first) ? ["s6-lead"] : []
    }

    /// Records a completed break. An arm break leads with nothing and its sets count toward
    /// neither pattern, so only the pattern breaks move the leads and the set counts.
    mutating func recordCompleted(letter: StrengthDayLetter, setOrder: [StrengthSetSlot], sets: [StrengthBucket]) {
        if letters[day] == nil { letters[day] = letter }
        completed += 1
        doneToday += 1
        guard !setOrder.contains(where: \.isArm) else { return }
        if patternBreaksToday > 0, let lead = sets.first { lastLed[lead] = completed - 1 }
        patternBreaksToday += 1
        for bucket in sets { setsToday[bucket, default: 0] += 1 }
    }
}
