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

/// One working set's place in a strength break: one of the day's two patterns, or the core set
/// the day's first break carries in place of its third set.
enum StrengthSetSlot: Hashable {
    case pattern(StrengthBucket)
    case core
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

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The next full break, given every break record so far and the strength breaks a day setting.
    func next(records: [BreakRecord], strengthBreaksPerDay: Int, today: Date) -> NextFullBreak {
        let days = strengthDays(in: records)
        let todayKey = DayKey.key(for: today, calendar: calendar)
        let letter = letter(for: todayKey, in: days)
        let completedToday = days.byKey[todayKey]?.count ?? 0
        guard completedToday < strengthBreaksPerDay else { return .endRange }

        let priorLead = lastLead(before: todayKey, letter: letter, in: days)
        let orders = Self.replay(letter: letter, breaks: completedToday + 1, priorLead: priorLead).orders
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
    static func replay(
        letter: StrengthDayLetter,
        breaks: Int,
        priorLead: StrengthBucket?
    ) -> (orders: [[StrengthSetSlot]], lastLead: StrengthBucket?) {
        let (first, second) = letter.patterns
        var sets: [StrengthBucket: Int] = [first: 0, second: 0]
        var ledAt: [StrengthBucket: Int] = [:]
        var lastLead: StrengthBucket?
        var orders: [[StrengthSetSlot]] = []

        for index in 0..<max(0, breaks) {
            if index == 0 {
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
            ledAt[lead] = index
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
    private func lastLead(before key: String, letter: StrengthDayLetter, in days: StrengthDays) -> StrengthBucket? {
        var lead: StrengthBucket?
        for dayKey in days.keys where dayKey < key {
            guard let breaks = days.byKey[dayKey], breaks.first == letter else { continue }
            if let dayLead = Self.replay(letter: letter, breaks: breaks.count, priorLead: lead).lastLead {
                lead = dayLead
            }
        }
        return lead
    }
}
