import Foundation

/// Every length a strength break is timed with, in one place so that they can be tuned together.
///
/// These are judgement rather than research findings (`research/session-structure.md
/// §Implications`): alternating patterns with a short rest keeps a set's muscles fresh for its next
/// set without stretching a desk break past what fits between meetings.
enum StrengthTiming {
    /// One rep of the rep meter: 1.5 s up and 1.5 s down (S25).
    static let repPaceSeconds = 3
    /// The grace after the meter stops, so the last rep is never cut off by the clock.
    static let setGraceSeconds = 5
    /// The switch-sides cue between the two halves of a per-side set.
    static let switchSidesSeconds = 3
    /// The rest between working sets. Its last five seconds are the next set's lead-in, so the
    /// sets after the first have no lead-in of their own.
    static let restSeconds = 45
    static let warmUpSeconds = 30
    static let coolDownSeconds = 30
    /// The moment to read what is coming before the clock starts, as in movement mode.
    static let leadInSeconds = 5
    /// An end-range break block, thirty seconds a side on a per-side move.
    static let endRangeBlockSeconds = 60
    /// Half a strength micro-break: one two-sided move, or one side of a per-side move.
    static let microHalfSeconds = 30

    /// The smallest rep targets the library's working doses use (S4): ten for a two-sided or
    /// alternating dose, eight a side for a per-side one. A rep dose below them is one of the slow
    /// multi-part moves the library kept short on purpose, which run on their own `block_seconds`
    /// with no meter, because three seconds a rep would rush them.
    static let twoSidedRepFloor = 10
    static let perSideRepFloor = 8
}

/// A strength-library dose, read for its numbers.
///
/// The library's text is kept as written for display; the numbers are only what the timer and the
/// rep meter need. A dose the meter cannot count (a time, a hold, "5 of each") has no reps.
struct StrengthDose: Hashable {
    let text: String
    /// Reps the meter counts, a side for a per-side dose, or nil when the set has no meter.
    let reps: Int?
    let perSide: Bool
    /// The pause at the top of each rep, for doses such as "12 reps, alternating, 2 s hold".
    let holdSeconds: Int?

    init(text: String) {
        self.text = text
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let head = parts.first ?? ""
        let hold = parts.dropFirst().lazy.compactMap { Self.number(in: $0, suffix: " s hold") }.first

        var reps: Int?
        var perSide = false
        if let count = Self.number(in: head, suffix: " reps") {
            reps = count >= StrengthTiming.twoSidedRepFloor ? count : nil
        } else if let count = Self.number(in: head, suffix: "/side") {
            perSide = true
            reps = count >= StrengthTiming.perSideRepFloor ? count : nil
        }
        self.reps = reps
        self.perSide = perSide
        self.holdSeconds = reps == nil ? nil : hold
    }

    /// True when the set is counted rep by rep rather than run on the movement's own length.
    var hasMeter: Bool { reps != nil }

    /// The whole number in front of `suffix`, or nil when the text is anything else ("25 s/side"
    /// is a time, not a rep count).
    private static func number(in text: String, suffix: String) -> Int? {
        guard text.hasSuffix(suffix) else { return nil }
        return Int(text.dropLast(suffix.count))
    }
}

/// One strength move with the seconds it is given: a warm-up, a cool-down, an end-range block or
/// half a micro-break.
struct StrengthBlock: Hashable, Identifiable {
    let movement: StrengthMovement
    let seconds: Int

    var id: String { movement.id }
    var perSide: Bool { movement.perSide }

    /// Seconds given to each side of a per-side move.
    var secondsPerSide: Int { perSide ? seconds / 2 : seconds }

    /// The dose a block shows. A block's length is set by its builder (the 30 s cool-down, the
    /// minute of an end-range block or a lone micro-break move), not by the library, so a dose
    /// that is only a time ("25 s/side", "30 s") is shown as the time the block runs; otherwise
    /// the card would read "25 s each side" over a disc that switches sides at 15 s. A rep dose,
    /// or a time with reps in it ("6 × 4 s"), is shown as the library writes it.
    var shownDose: String {
        guard Self.isTimeOnly(movement.dose) else { return movement.dose }
        return perSide ? "\(secondsPerSide) s/side" : "\(seconds) s"
    }

    /// "30 s" or "25 s/side", and nothing else.
    private static func isTimeOnly(_ dose: String) -> Bool {
        dose.range(of: #"^\d+ s(/side)?$"#, options: .regularExpression) != nil
    }
}

/// One working set of a strength break.
struct StrengthSet: Hashable {
    let movement: StrengthMovement
    /// The set's place in the break, 1 to 3: "Set 2 of 3".
    let setNumber: Int
    /// The library's dose text, unchanged.
    let dose: String
    /// Reps the meter counts (a side, on a per-side set), or nil for a set with no meter.
    let reps: Int?
    let perSide: Bool
    let holdSeconds: Int?
    let plannedSeconds: Int

    init(movement: StrengthMovement, setNumber: Int) {
        let parsed = StrengthDose(text: movement.dose)
        self.movement = movement
        self.setNumber = setNumber
        self.dose = movement.dose
        self.reps = parsed.reps
        self.perSide = movement.perSide
        self.holdSeconds = parsed.holdSeconds
        self.plannedSeconds = Self.plannedSeconds(for: parsed, movement: movement)
    }

    var hasMeter: Bool { reps != nil }

    /// Reps × (3 s + any hold) + the 5 s grace, both sides and the switch cue for a per-side set;
    /// a set with no meter runs for the movement's own `block_seconds`.
    static func plannedSeconds(for dose: StrengthDose, movement: StrengthMovement) -> Int {
        guard let reps = dose.reps else { return movement.blockSeconds }
        let perRep = StrengthTiming.repPaceSeconds + (dose.holdSeconds ?? 0)
        let sides = movement.perSide ? 2 : 1
        let switchCue = movement.perSide ? StrengthTiming.switchSidesSeconds : 0
        return reps * perRep * sides + switchCue + StrengthTiming.setGraceSeconds
    }
}

/// Which rule a builder had to let go of to fill a slot, recorded so that the simulation can
/// report how often a context runs a pool dry rather than hiding it.
struct StrengthRelaxation: Hashable {
    enum Slot: Hashable {
        case warmUp
        case set(Int)
        case coolDown
        case block(Int)
    }

    /// The rungs, in the order each builder lets them go.
    enum Rule: String, Hashable {
        /// At most one per-side, one floor and one grip working move.
        case breakLimits
        /// Bodyweight, non-floor, difficulty 1, two-sided.
        case warmUpShape
        /// A cool-down that stretches a region the sets worked.
        case coolDownRegion
        /// Nothing served today in either mode.
        case servedToday
        /// With any kit selected, a working set is a vigorous move.
        case vigorous
        /// No region shared with the previous micro-break.
        case previousMicroRegion
        case excluded
        /// The difficulty cap and the difficulty-3 unlock.
        case difficulty
        /// Anything in the slot's pattern the user can physically do.
        case anything
        /// A two-sided micro move with no same-posture partner runs the whole minute alone.
        case microShape
    }

    let slot: Slot
    let rule: Rule
}

/// One strength break: a warm-up, three working sets and a cool-down (S6).
struct StrengthBreak: Hashable, Identifiable {
    let id: UUID
    let letter: StrengthDayLetter
    let warmUp: StrengthBlock
    let sets: [StrengthSet]
    let coolDown: StrengthBlock
    let relaxed: [StrengthRelaxation]

    /// A lead-in before the warm-up and before the first set, the warm-up, the sets, a rest between
    /// each pair of sets and the cool-down. Later sets and the cool-down take their lead-in out of
    /// the rest or run straight on, so they add nothing of their own.
    var plannedSeconds: Int {
        StrengthTiming.leadInSeconds + warmUp.seconds
            + StrengthTiming.leadInSeconds + sets.reduce(0) { $0 + $1.plannedSeconds }
            + StrengthTiming.restSeconds * max(0, sets.count - 1)
            + coolDown.seconds
    }

    /// Each move once, in the order served; the repeated pattern's move appears once.
    var movementIds: [String] {
        var seen = Set<String>()
        let ids = [warmUp.movement.id] + sets.map(\.movement.id) + [coolDown.movement.id]
        return ids.filter { seen.insert($0).inserted }
    }

    /// The regions the working sets loaded, which the cool-down stretches and the day's end-range
    /// breaks leave alone.
    var workedRegions: Set<Region> {
        Set(sets.flatMap(\.movement.regions))
    }
}

/// The break served once the day's strength breaks are done: four END moves of a minute each
/// (S22).
struct EndRangeBreak: Hashable, Identifiable {
    let id: UUID
    let blocks: [StrengthBlock]
    let relaxed: [StrengthRelaxation]

    /// Every block after its lead-in: 4 × 65 s.
    var plannedSeconds: Int {
        blocks.reduce(0) { $0 + StrengthTiming.leadInSeconds + $1.seconds }
    }

    var movementIds: [String] { blocks.map(\.movement.id) }
}

/// A strength micro-break: one per-side END move for the minute, thirty seconds a side, or two
/// two-sided END moves of thirty seconds each, each after its lead-in (S7).
///
/// A sibling of `MicroBreak` rather than a reuse, because `MicroBreak`'s blocks hold movement-
/// library `Movement`s; the timing is the same.
struct StrengthMicroBreak: Hashable, Identifiable {
    let id: UUID
    let blocks: [StrengthBlock]
    let relaxed: [StrengthRelaxation]

    /// 65 s for one move, 70 s for two, as in movement mode.
    var totalSeconds: Int {
        blocks.reduce(0) { $0 + StrengthTiming.leadInSeconds + $1.seconds }
    }

    var movementIds: [String] { blocks.map(\.movement.id) }
}

extension UUID {
    /// A UUID fixed by a builder's seed, so the same context builds an identical break, id
    /// included, and a relaunch regenerates the break the menu already advertised.
    static func seeded(_ seed: UInt64, salt: UInt64) -> UUID {
        var rng = SplitMix64(seed: seed ^ salt)
        let high = rng.next()
        let low = rng.next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (index * 8))
            bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (index * 8))
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
