import Foundation

/// The two strength days. An A day trains squat/lunge and push, a B day hinge and pull, so each
/// pattern gets a day off between sessions.
enum StrengthDayLetter: String, Codable, CaseIterable, Hashable {
    case dayA = "A"
    case dayB = "B"

    /// The day's two patterns, in the order the day's first break serves them.
    var patterns: (first: StrengthBucket, second: StrengthBucket) {
        self == .dayA ? (.sqt, .psh) : (.hng, .pul)
    }

    /// The arm the day's arm break trains: triceps on a push day, biceps on a pull day, so the
    /// arm work lands on the day whose pattern already uses it as a helper.
    var armBucket: StrengthBucket { self == .dayA ? .tri : .bic }

    /// The pattern an arm break's warm-up is drawn from: the day's push or pull, which warms the
    /// joints the arm sets load without spending an arm move on the warm-up.
    var armWarmUpPattern: StrengthBucket { patterns.second }

    var other: StrengthDayLetter { self == .dayA ? .dayB : .dayA }

    /// How a completed break on this day is recorded in history.
    var breakKind: BreakKind { self == .dayA ? .strengthA : .strengthB }

    /// The letter a recorded break was served on, or nil when it was not a strength break. Read
    /// through `breakKind` rather than a switch so that this mapping has one definition.
    init?(kind: BreakKind) {
        guard let letter = Self.allCases.first(where: { $0.breakKind == kind }) else { return nil }
        self = letter
    }
}

/// One working set's place in a strength break: one of the day's two patterns, the core set the
/// day's first break carries in place of its third set, or one of an arm break's sets.
///
/// The builder keys repeats by slot, not by bucket: the same slot twice is the same move twice,
/// which is how an arm break serves one move for two sets and a different one for the third.
enum StrengthSetSlot: Hashable {
    case pattern(StrengthBucket)
    case core
    /// An arm break's main move, served for its first two sets.
    case arm(StrengthBucket)
    /// An arm break's third set: a different move from the same arm bucket.
    case armAlternate(StrengthBucket)

    /// Whether this slot belongs to an arm break.
    var isArm: Bool {
        switch self {
        case .arm, .armAlternate: return true
        case .pattern, .core: return false
        }
    }
}

/// What the next full break should be.
enum NextFullBreak: Hashable {
    /// The `index`-th of the day's `count` strength breaks (1-based), with its three working sets.
    case strength(letter: StrengthDayLetter, index: Int, of: Int, setOrder: [StrengthSetSlot])
    /// Every full break after the day's strength breaks are done.
    case endRange
}

/// Decides, from history alone, which kind of full break comes next in Strength mode and which
/// patterns its sets train (S22, S6).
///
/// Pure and deterministic: the coordinator hands it the break records and today's date, and the
/// same history always plans the same break, so the menu, the heads-up and the overlay agree. No
/// set order is stored; it is replayed from the completed breaks, because the order is itself a
/// function of the breaks before it.
struct StrengthDayPlanner {
    /// The calendar `HistoryStore` buckets days with, so the planner and the history agree on
    /// what "today" holds.
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    /// Whether the user's kit allows an arm break. The arm buckets have bodyweight and dumbbell
    /// moves but no kettlebell ones, and with any kit selected working sets must be vigorous, so a
    /// kettlebell-only user would have only light arm moves left; their arm break stays a normal
    /// push-pull break.
    static func armBreakPossible(equipment: Set<StrengthEquipment>) -> Bool {
        equipment.isEmpty || equipment.contains(.dumbbells)
    }

    /// Where an arm break falls in a day that is long enough to reach it: the fourth break, or the
    /// third under "More arms" (0-based 3 or 2); nil when the kit allows none.
    static func armBreakPosition(focus: StrengthFocus, armBreakPossible: Bool) -> Int? {
        guard armBreakPossible else { return nil }
        return focus == .moreArms ? 2 : 3
    }

    /// The 0-based index of today's arm break, or nil when the day has none: its position, and
    /// only when the day has more strength breaks than that. One or two a day never get one, since
    /// those breaks are all the day's pattern work.
    static func armBreakIndex(strengthBreaksPerDay: Int, focus: StrengthFocus, armBreakPossible: Bool) -> Int? {
        guard let position = armBreakPosition(focus: focus, armBreakPossible: armBreakPossible) else { return nil }
        return strengthBreaksPerDay > position ? position : nil
    }

    /// The next full break, given every break record so far, the strength breaks a day setting,
    /// the focus and whether the user's kit allows an arm break (`armBreakPossible(equipment:)`).
    func next(
        records: [BreakRecord],
        strengthBreaksPerDay: Int,
        focus: StrengthFocus,
        armBreakPossible: Bool,
        today: Date
    ) -> NextFullBreak {
        let days = strengthDays(in: records)
        let todayKey = DayKey.key(for: today, calendar: calendar)
        let letter = letter(for: todayKey, in: days)
        let completedToday = days.byKey[todayKey]?.count ?? 0
        guard completedToday < strengthBreaksPerDay else { return .endRange }

        let armIndex = Self.armBreakIndex(
            strengthBreaksPerDay: strengthBreaksPerDay, focus: focus, armBreakPossible: armBreakPossible
        )
        let priorLead = lastLead(
            before: todayKey,
            letter: letter,
            armPosition: Self.armBreakPosition(focus: focus, armBreakPossible: armBreakPossible),
            in: days
        )
        let orders = Self.replay(
            letter: letter, breaks: completedToday + 1, priorLead: priorLead, armIndex: armIndex
        ).orders
        return .strength(
            letter: letter,
            index: completedToday + 1,
            of: strengthBreaksPerDay,
            setOrder: orders[completedToday]
        )
    }

    /// Today's letter: whatever the day's first completed strength break was served as; before
    /// that, the other letter from the most recent earlier day with a completed strength break,
    /// however many days of Movement mode lie between; A when there has never been one.
    func letter(records: [BreakRecord], today: Date) -> StrengthDayLetter {
        letter(for: DayKey.key(for: today, calendar: calendar), in: strengthDays(in: records))
    }

    // MARK: - Replay

    /// The set orders of a day's first `breaks` strength breaks.
    ///
    /// The first break is fixed as first pattern · second pattern · core. Each later break leads
    /// with the pattern that has fewer sets so far today and is served lead · other · lead. A tie
    /// goes to the pattern that led less recently today; when neither has led today, to the one
    /// that did not lead last on an earlier day with this letter (`priorLead`), else the first
    /// pattern. The first break does not count as a lead: its shape is fixed, not chosen.
    ///
    /// The break at `armIndex`, when there is one, is the day's arm break, arm · arm · alternate
    /// from the letter's arm bucket. The pattern breaks step over it: its sets count toward
    /// neither pattern and it leads with neither, so the pattern breaks after it are exactly the
    /// ones the day would have had in its place, and the arm break moves no lead across days.
    static func replay(
        letter: StrengthDayLetter,
        breaks: Int,
        priorLead: StrengthBucket?,
        armIndex: Int? = nil
    ) -> (orders: [[StrengthSetSlot]], lastLead: StrengthBucket?) {
        let (first, second) = letter.patterns
        let arm = letter.armBucket
        var sets: [StrengthBucket: Int] = [first: 0, second: 0]
        var ledAt: [StrengthBucket: Int] = [:]
        var lastLead: StrengthBucket?
        var orders: [[StrengthSetSlot]] = []
        // Counts pattern breaks only, so an arm break leaves the lead's recency where it was.
        var patternBreak = 0

        for index in 0..<max(0, breaks) {
            if index == armIndex {
                orders.append([.arm(arm), .arm(arm), .armAlternate(arm)])
                continue
            }
            defer { patternBreak += 1 }
            if patternBreak == 0 {
                orders.append([.pattern(first), .pattern(second), .core])
                sets[first, default: 0] += 1
                sets[second, default: 0] += 1
                continue
            }
            let lead = chooseLead(first: first, second: second, sets: sets, ledAt: ledAt, priorLead: priorLead)
            let other = lead == first ? second : first
            orders.append([.pattern(lead), .pattern(other), .pattern(lead)])
            sets[lead, default: 0] += 2
            sets[other, default: 0] += 1
            ledAt[lead] = patternBreak
            lastLead = lead
        }
        return (orders, lastLead)
    }

    private static func chooseLead(
        first: StrengthBucket,
        second: StrengthBucket,
        sets: [StrengthBucket: Int],
        ledAt: [StrengthBucket: Int],
        priorLead: StrengthBucket?
    ) -> StrengthBucket {
        let firstSets = sets[first] ?? 0
        let secondSets = sets[second] ?? 0
        if firstSets != secondSets { return firstSets < secondSets ? first : second }
        if !ledAt.isEmpty {
            // A pattern that has not led today led less recently than one that has.
            return (ledAt[first] ?? -1) <= (ledAt[second] ?? -1) ? first : second
        }
        if let priorLead { return priorLead == first ? second : first }
        return first
    }

    // MARK: - History

    /// Each day's completed strength breaks, as the letters they were served on, in order.
    private struct StrengthDays {
        var byKey: [String: [StrengthDayLetter]] = [:]
        /// The day keys, oldest first. "yyyy-MM-dd" keys sort chronologically.
        var keys: [String] { byKey.keys.sorted() }
    }

    /// Only completed strength breaks shape the plan: a skipped or snoozed one did not happen, and
    /// Movement and end-range breaks train neither pattern.
    private func strengthDays(in records: [BreakRecord]) -> StrengthDays {
        var days = StrengthDays()
        for record in records where record.outcome.countsAsCompleted {
            guard let letter = StrengthDayLetter(kind: record.breakKind) else { continue }
            days.byKey[DayKey.key(for: record.at, calendar: calendar), default: []].append(letter)
        }
        return days
    }

    private func letter(for key: String, in days: StrengthDays) -> StrengthDayLetter {
        if let fixed = days.byKey[key]?.first { return fixed }
        guard let previous = days.keys.last(where: { $0 < key }), let letter = days.byKey[previous]?.first else {
            return .dayA
        }
        return letter.other
    }

    /// The pattern that led most recently on an earlier day with `letter`, found by replaying every
    /// such day in order, since each day's ties depend on the day before it.
    ///
    /// History records an arm break as an ordinary strength break, so an earlier day is replayed
    /// with the arm break at today's `armPosition`, whatever that day's breaks-a-day setting was:
    /// a day with a break at that position had more breaks than it, so it had its arm break there,
    /// and a shorter day never reaches it. Only a change of focus or kit since can misplace it,
    /// which moves at most one lead, and a lead only decides a tie.
    private func lastLead(
        before key: String,
        letter: StrengthDayLetter,
        armPosition: Int?,
        in days: StrengthDays
    ) -> StrengthBucket? {
        var lead: StrengthBucket?
        for dayKey in days.keys where dayKey < key {
            guard let breaks = days.byKey[dayKey], breaks.first == letter else { continue }
            let replay = Self.replay(letter: letter, breaks: breaks.count, priorLead: lead, armIndex: armPosition)
            if let dayLead = replay.lastLead {
                lead = dayLead
            }
        }
        return lead
    }
}
