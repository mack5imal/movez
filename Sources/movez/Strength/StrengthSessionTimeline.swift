import Foundation

/// What a strength or end-range break is doing at each second, as a value driven only by the
/// times it is handed.
///
/// The overlay's view model owns one and asks it where the break is; the views only render the
/// answer. Keeping it free of the clock, the chimes and AppKit is what lets a whole break replay in
/// a test, pauses and early presses included (S11).
///
/// A strength break runs lead-in → warm-up → lead-in → set 1 → rest → set 2 → rest → set 3 →
/// cool-down, then closes. A rest's last five seconds are the next set's lead-in, so a set after a
/// rest has no lead-in of its own, and the cool-down runs straight on from the last set. An
/// end-range break is the movement-break flow: each block after its own lead-in.
struct StrengthSessionTimeline: Equatable {
    /// How long a press keeps the disc from acting again. A double click, or Space pressed twice,
    /// is one intention: it ends the set, and must not also skip the rest the set just earned.
    static let pressGuardSeconds: TimeInterval = 1

    /// The shape of the session, not the app's mode: a break of working sets, or the end-range
    /// break's movement-style blocks.
    enum Flow: Equatable {
        case workingSets
        case endRange
    }

    enum Kind: Equatable {
        /// The moment to read what comes next; the segment after it is what it leads into.
        case leadIn
        case warmUp
        /// A working set, 1-based.
        case set(Int)
        /// The rest before the given set, 1-based.
        case rest(beforeSet: Int)
        case coolDown
        /// An end-range block, 1-based.
        case block(Int)

        /// The segments that are a move being done, which are what a break counts as completed.
        var isWork: Bool {
            switch self {
            case .warmUp, .set, .coolDown, .block: return true
            case .leadIn, .rest: return false
            }
        }
    }

    struct Segment: Equatable {
        let kind: Kind
        let seconds: Int
        /// The move being done, or nil for a lead-in or a rest, which show the next segment's.
        let movement: StrengthMovement?
        /// The library's dose text; empty for the warm-up, which has no rep target.
        let dose: String
        /// The rep meter, on a working set whose dose it can count.
        let pacer: RepPacer?
        /// Seconds into the segment at which a per-side move changes to its second side.
        let sideSwitchAt: TimeInterval?
        /// The strip column the segment belongs to, 0-based.
        let column: Int
    }

    enum Event: Equatable {
        /// A segment began; `.leadIn` included.
        case started(Kind)
        /// A working set ended, by its clock or by Done.
        case setEnded(Int)
        case sideSwitched
        case closed
    }

    let flow: Flow
    let segments: [Segment]
    let startedAt: Date
    /// The number of strip columns: warm-up, the sets and the cool-down, or the end-range blocks.
    let columns: Int

    private(set) var index = 0
    /// Session seconds at which the current segment began.
    private(set) var segmentStart: TimeInterval = 0
    private(set) var sideSwitched = false
    private(set) var completedWork = 0
    private(set) var pausedAt: Date?
    /// Every finished pause added together; the session's own time is the wall clock less this.
    private(set) var pausedTotal: TimeInterval = 0
    /// Session seconds of the last press that did something.
    private var lastPressAt: TimeInterval?

    // MARK: - Building

    init(strengthBreak: StrengthBreak, startedAt: Date) {
        var segments: [Segment] = []
        let warmUp = strengthBreak.warmUp
        segments.append(Self.leadIn(column: 0))
        segments.append(Segment(
            kind: .warmUp, seconds: warmUp.seconds, movement: warmUp.movement, dose: "", pacer: nil,
            sideSwitchAt: warmUp.perSide ? TimeInterval(warmUp.secondsPerSide) : nil, column: 0
        ))
        for (offset, set) in strengthBreak.sets.enumerated() {
            let column = offset + 1
            if offset == 0 {
                segments.append(Self.leadIn(column: column))
            } else {
                segments.append(Segment(
                    kind: .rest(beforeSet: set.setNumber), seconds: StrengthTiming.restSeconds, movement: nil,
                    dose: "", pacer: nil, sideSwitchAt: nil, column: column
                ))
            }
            segments.append(Self.workingSet(set, column: column))
        }
        let coolDown = strengthBreak.coolDown
        segments.append(Segment(
            kind: .coolDown, seconds: coolDown.seconds, movement: coolDown.movement, dose: coolDown.movement.dose,
            pacer: nil, sideSwitchAt: coolDown.perSide ? TimeInterval(coolDown.secondsPerSide) : nil,
            column: strengthBreak.sets.count + 1
        ))
        self.init(flow: .workingSets, segments: segments, columns: strengthBreak.sets.count + 2, startedAt: startedAt)
    }

    init(endRangeBreak: EndRangeBreak, startedAt: Date) {
        let segments = endRangeBreak.blocks.enumerated().flatMap { offset, block in
            [
                Self.leadIn(column: offset),
                Segment(
                    kind: .block(offset + 1), seconds: block.seconds, movement: block.movement,
                    dose: block.movement.dose, pacer: nil,
                    sideSwitchAt: block.perSide ? TimeInterval(block.secondsPerSide) : nil, column: offset
                )
            ]
        }
        self.init(flow: .endRange, segments: segments, columns: endRangeBreak.blocks.count, startedAt: startedAt)
    }

    private init(flow: Flow, segments: [Segment], columns: Int, startedAt: Date) {
        self.flow = flow
        self.segments = segments
        self.columns = columns
        self.startedAt = startedAt
    }

    private static func leadIn(column: Int) -> Segment {
        Segment(
            kind: .leadIn, seconds: StrengthTiming.leadInSeconds, movement: nil, dose: "", pacer: nil,
            sideSwitchAt: nil, column: column
        )
    }

    /// A set's length is the one its builder planned, so the overlay and the scheduler agree.
    private static func workingSet(_ set: StrengthSet, column: Int) -> Segment {
        let pacer = RepPacer(
            reps: set.reps,
            perSide: set.perSide,
            holdSeconds: set.holdSeconds,
            paceSeconds: StrengthTiming.repPaceSeconds,
            switchSidesSeconds: StrengthTiming.switchSidesSeconds
        )
        let switchAt: TimeInterval?
        if set.perSide {
            // With a meter the sides change as the cue starts; without one, halfway.
            switchAt = pacer?.sideSeconds ?? TimeInterval(set.plannedSeconds) / 2
        } else {
            switchAt = nil
        }
        return Segment(
            kind: .set(set.setNumber), seconds: set.plannedSeconds, movement: set.movement, dose: set.dose,
            pacer: pacer, sideSwitchAt: switchAt, column: column
        )
    }

    // MARK: - Reading

    var isClosed: Bool { index >= segments.count }
    var isPaused: Bool { pausedAt != nil }
    var current: Segment? { segments.indices.contains(index) ? segments[index] : nil }
    /// The segment after the current one, which a lead-in or a rest shows.
    var following: Segment? { segments.indices.contains(index + 1) ? segments[index + 1] : nil }
    var totalWork: Int { segments.filter(\.kind.isWork).count }
    var totalSeconds: Int { segments.reduce(0) { $0 + $1.seconds } }

    /// The session's own seconds: they stand still while paused.
    func elapsed(at now: Date) -> TimeInterval {
        max(0, (pausedAt ?? now).timeIntervalSince(startedAt) - pausedTotal)
    }

    func segmentElapsed(at now: Date) -> TimeInterval {
        max(0, elapsed(at: now) - segmentStart)
    }

    func segmentRemaining(at now: Date) -> TimeInterval {
        guard let current else { return 0 }
        return max(0, TimeInterval(current.seconds) - segmentElapsed(at: now))
    }

    /// The rest of the segment on screen, then every later one as planned.
    func breakRemaining(at now: Date) -> TimeInterval {
        guard !isClosed else { return 0 }
        let later = segments.dropFirst(index + 1).reduce(0) { $0 + $1.seconds }
        return segmentRemaining(at: now) + TimeInterval(later)
    }

    /// True in a lead-in, and in a rest's last five seconds, which are the next set's lead-in.
    func isLeadIn(at now: Date) -> Bool {
        guard let current else { return false }
        switch current.kind {
        case .leadIn: return true
        case .rest: return segmentRemaining(at: now) <= TimeInterval(StrengthTiming.leadInSeconds)
        default: return false
        }
    }

    // MARK: - Driving

    /// Catches the session up to `now`. A segment that has run out hands over at its planned end,
    /// not at the moment this noticed, so late updates never stretch the break; an update late
    /// enough to cover several segments walks through each.
    mutating func update(at now: Date) -> [Event] {
        guard !isPaused else { return [] }
        var events: [Event] = []
        let time = elapsed(at: now)
        while let current, time >= segmentStart + TimeInterval(current.seconds) {
            events += finishSegment(nextStartsAt: segmentStart + TimeInterval(current.seconds))
        }
        if let current, let switchAt = current.sideSwitchAt, !sideSwitched, time - segmentStart >= switchAt {
            sideSwitched = true
            events.append(.sideSwitched)
        }
        return events
    }

    /// The disc, and Space on a strength break.
    ///
    /// On a set it ends the set and starts the rest at once; on a rest it skips to the rest's last
    /// five seconds, so the next set still gets its lead-in; on the warm-up and the cool-down it
    /// moves on. A lead-in ignores it, because those seconds are for reading what comes next. On
    /// an end-range break it is the movement break's Next. Paused, nothing moves.
    mutating func press(at now: Date) -> [Event] {
        guard !isPaused, !isClosed else { return [] }
        let pressedOn = index
        var events = update(at: now)
        // A catch-up that ran the segment on screen out means the press was aimed at a segment
        // that has already ended, so it must not act on the next one, which the user never saw.
        guard index == pressedOn, let current else { return events }
        let time = elapsed(at: now)
        if let lastPressAt, time - lastPressAt < Self.pressGuardSeconds { return events }

        switch (flow, current.kind) {
        case (.workingSets, .leadIn):
            return events
        case (.workingSets, .rest):
            let lead = TimeInterval(StrengthTiming.leadInSeconds)
            guard segmentRemaining(at: now) > lead else { return events }
            segmentStart = time + lead - TimeInterval(current.seconds)
        case (.endRange, .leadIn):
            // As in a movement break, Next during a lead-in passes the block it leads into.
            events += finishSegment(nextStartsAt: time)
            events += finishSegment(nextStartsAt: time)
        default:
            events += finishSegment(nextStartsAt: time)
        }
        lastPressAt = time
        return events
    }

    mutating func pause(at now: Date) {
        guard !isPaused, !isClosed else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    private mutating func finishSegment(nextStartsAt time: TimeInterval) -> [Event] {
        guard let current else { return [] }
        var events: [Event] = []
        if current.kind.isWork { completedWork += 1 }
        if case let .set(number) = current.kind { events.append(.setEnded(number)) }
        index += 1
        segmentStart = time
        sideSwitched = false
        events.append(self.current.map { .started($0.kind) } ?? .closed)
        return events
    }
}
