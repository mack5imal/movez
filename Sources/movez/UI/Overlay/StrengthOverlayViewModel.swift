import Foundation

/// Drives the overlay for a strength break or an end-range break: one tick a second, rendered
/// from a `StrengthSessionTimeline`.
///
/// The timeline decides where the break is; this turns that into what the overlay draws and plays
/// the two chimes a strength break has, one as a set ends and one as a per-side move changes side.
/// The rep meter is silent: a sound every three seconds would be a metronome, not a cue. An
/// end-range break keeps the movement break's chime as each block appears. Neither has an end
/// screen: when the last segment ends the session closes and the overlay dismisses itself.
///
/// It is a sibling of `OverlayViewModel` rather than a mode of it, so a Movement break's flow is
/// left exactly as it was.
@MainActor
final class StrengthOverlayViewModel: ObservableObject {
    @Published private(set) var state = StrengthOverlayState()

    private(set) var timeline: StrengthSessionTimeline
    private let clock: Clock
    private let chimes: ChimePlayer?
    /// Read from the system by the view layer and handed in; the model never asks the system.
    private let reduceMotion: Bool
    private let mode: BreakMode
    private let setCount: Int
    /// The work segments already reported through `onWorkCompleted`.
    private var reportedWork = 0
    private var pauseExpiredHandled = false
    /// The scheduler's own rules, with the length of the break on screen, so a pause that runs
    /// out ends the break the way the scheduler would judge it.
    private let config: SchedulerConfig
    /// The break ended before its timeline did: its pause ran out after it already counted.
    private var endedEarly = false

    var snoozesLeft: Int
    var skipsToday: Int

    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    /// A pause ran its five minutes.
    var onPauseExpired: (() -> Void)?
    /// The break closed itself: moves completed, moves planned, and seconds the break ran.
    var onFinished: ((Int, Int, Int) -> Void)?
    /// A warm-up, set, cool-down or end-range block finished, by its clock or by the disc, so the
    /// app can record it as the movement break records each block. It carries the 0-based index
    /// of the part that finished, in the break's part order: a view model rebuilt on a resume
    /// replays the parts already done, and the index is what lets the app record each one once.
    var onWorkCompleted: ((Int) -> Void)?

    convenience init(
        strengthBreak: StrengthBreak,
        startedAt: Date,
        clock: Clock,
        config: SchedulerConfig = SchedulerConfig(),
        chimes: ChimePlayer? = nil,
        snoozesLeft: Int = 2,
        skipsToday: Int = 0,
        reduceMotion: Bool = false,
        mode: BreakMode = .strength
    ) {
        self.init(
            timeline: StrengthSessionTimeline(strengthBreak: strengthBreak, startedAt: startedAt),
            clock: clock, config: config, chimes: chimes, snoozesLeft: snoozesLeft, skipsToday: skipsToday,
            reduceMotion: reduceMotion, mode: mode
        )
    }

    convenience init(
        endRangeBreak: EndRangeBreak,
        startedAt: Date,
        clock: Clock,
        config: SchedulerConfig = SchedulerConfig(),
        chimes: ChimePlayer? = nil,
        snoozesLeft: Int = 2,
        skipsToday: Int = 0,
        reduceMotion: Bool = false,
        mode: BreakMode = .strength
    ) {
        self.init(
            timeline: StrengthSessionTimeline(endRangeBreak: endRangeBreak, startedAt: startedAt),
            clock: clock, config: config, chimes: chimes, snoozesLeft: snoozesLeft, skipsToday: skipsToday,
            reduceMotion: reduceMotion, mode: mode
        )
    }

    private init(
        timeline: StrengthSessionTimeline,
        clock: Clock,
        config: SchedulerConfig,
        chimes: ChimePlayer?,
        snoozesLeft: Int,
        skipsToday: Int,
        reduceMotion: Bool,
        mode: BreakMode
    ) {
        self.timeline = timeline
        self.mode = mode
        self.clock = clock
        self.config = config
        self.chimes = chimes
        self.snoozesLeft = snoozesLeft
        self.skipsToday = skipsToday
        self.reduceMotion = reduceMotion
        setCount = timeline.segments.filter { if case .set = $0.kind { return true } else { return false } }.count
        refresh()
    }

    // MARK: - Derived values

    var isClosed: Bool { timeline.isClosed || endedEarly }

    /// True once the break counts, by the scheduler's rule: half the moves, or half the time.
    var doneAvailable: Bool {
        Scheduler.meetsCompletionRule(
            completed: timeline.completedWork,
            total: timeline.totalWork,
            elapsed: elapsedSeconds,
            config: config
        )
    }
    var isPaused: Bool { timeline.isPaused }
    var startedAt: Date { timeline.startedAt }

    /// Whole seconds the break has run, pauses excluded.
    var elapsedSeconds: Int { Int(timeline.elapsed(at: clock.now)) }

    var skipEnabled: Bool { timeline.elapsed(at: clock.now) >= OverlayViewModel.skipDelaySeconds }

    /// Body crossfades follow the system's Reduce Motion setting, as the movement break's do.
    var animationsEnabled: Bool { !reduceMotion }

    /// The meter as it stands this instant. The state moves once a second with the tick; the smooth
    /// meter reads this every frame so its fill rises and falls rather than stepping.
    func livePacer() -> RepPacerState? {
        guard let current = timeline.current, case .set = current.kind, let pacer = current.pacer else {
            return state.pacer
        }
        let elapsed = min(timeline.segmentElapsed(at: clock.now), TimeInterval(current.seconds))
        return pacer.state(at: elapsed, paused: isPaused, stepped: reduceMotion)
    }

    /// Whole seconds before the current pause ends the break, rounded up.
    var pauseRemaining: Int {
        guard let pausedAt = timeline.pausedAt else { return 0 }
        return Self.wholeSeconds(OverlayViewModel.pauseLimitSeconds - clock.now.timeIntervalSince(pausedAt))
    }

    // MARK: - The tick

    func tick() {
        guard !isClosed else { return }
        if let pausedAt = timeline.pausedAt {
            if clock.now.timeIntervalSince(pausedAt) >= OverlayViewModel.pauseLimitSeconds {
                pauseExpired()
            } else {
                refresh()
            }
            return
        }
        handle(timeline.update(at: clock.now))
        refresh()
    }

    // MARK: - Actions

    /// The disc and Space: Done on a set, Next on the warm-up, the cool-down and an end-range
    /// block, skip on a rest. The timeline decides which moments ignore it.
    func done() {
        handle(timeline.press(at: clock.now))
        refresh()
    }

    /// A key pressed while the break is on screen: Space, → and Return press the disc, and every
    /// other key does nothing. Returns whether the key acted.
    @discardableResult
    func handleKey(_ keyCode: UInt16) -> Bool {
        guard OverlayKeyMap.timeline(keyCode) == .disc else { return false }
        done()
        return true
    }

    /// The Pause button. Space is Done on a strength break, so it does not pause.
    func togglePause() {
        guard !isClosed else { return }
        if timeline.isPaused {
            timeline.resume(at: clock.now)
        } else {
            timeline.pause(at: clock.now)
        }
        refresh()
    }

    func snooze() {
        guard !isClosed, snoozesLeft > 0 else { return }
        onSnooze?()
    }

    func skip() {
        guard !isClosed, skipEnabled else { return }
        onSkip?()
    }

    /// Five minutes paused. As on a movement break (DECISIONS 38), a break that already counts
    /// ends as done; any other ends as snoozed.
    private func pauseExpired() {
        guard !pauseExpiredHandled else { return }
        pauseExpiredHandled = true
        timeline.resume(at: clock.now)
        if doneAvailable {
            endedEarly = true
            chimes?.play(.completion)
            onFinished?(timeline.completedWork, timeline.totalWork, elapsedSeconds)
        } else {
            onPauseExpired?()
        }
        refresh()
    }

    private func handle(_ events: [StrengthSessionTimeline.Event]) {
        // Each finished move is reported before the close, so the last one is recorded before
        // the break ends.
        while reportedWork < timeline.completedWork {
            let index = reportedWork
            reportedWork += 1
            onWorkCompleted?(index)
        }
        for event in events {
            switch event {
            case .setEnded, .sideSwitched:
                chimes?.play(.transition)
            case .started(.leadIn) where timeline.flow == .endRange:
                chimes?.play(.transition)
            case .closed:
                // The overlay owns the break's sound, so the scheduler's completion chime is
                // dropped while it is on screen; a break that runs to its end plays it here.
                chimes?.play(.completion)
                onFinished?(timeline.completedWork, timeline.totalWork, elapsedSeconds)
            case .started:
                break
            }
        }
    }

    // MARK: - State

    func refresh() {
        var state = StrengthOverlayState()
        state.mode = mode.definition
        state.eyebrow = mode.definition.breakEyebrow
        state.reduceMotion = reduceMotion
        state.skipsToday = skipsToday
        state.strip = strip()
        guard let current = timeline.current else {
            state.isClosed = true
            self.state = state
            return
        }
        let now = clock.now
        state.segment = current.kind
        state.isPaused = isPaused
        state.headerTrailing = isPaused
            ? "PAUSED · ENDS IN \(OverlayState.clock(pauseRemaining))"
            : "\(OverlayState.clock(Self.wholeSeconds(timeline.breakRemaining(at: now)))) LEFT"
        fillBody(&state, current: current, now: now)
        fillDisc(&state, current: current, now: now)
        state.snoozeAvailable = snoozesLeft > 0
        state.skipEnabled = skipEnabled
        self.state = state
    }

    /// A lead-in and a rest show what they lead into; everything else shows itself.
    private func fillBody(_ state: inout StrengthOverlayState, current: StrengthSessionTimeline.Segment, now: Date) {
        let waiting = current.movement == nil
        let shown = waiting ? (timeline.following ?? current) : current
        let dose = DoseText(shown.dose)

        state.movementName = shown.movement?.name ?? ""
        state.instruction = shown.movement?.instructions ?? ""
        state.dose = dose.line
        state.doseModifier = dose.modifier
        state.kicker = kicker(for: shown.kind)
        state.isSideBlock = shown.movement?.perSide == true
        state.side = side(current: current)

        if case .rest = current.kind {
            state.headline = StrengthOverlayState.restHeadline
            state.upNext = StrengthOverlayState.upNext(movement: state.movementName, dose: dose.line)
            return
        }
        // The lead-in before a set shows its meter empty at Rep 1, ready to rise.
        if case .set = shown.kind, let pacer = shown.pacer {
            let elapsed = waiting ? 0 : timeline.segmentElapsed(at: now)
            let pacerState = pacer.state(at: elapsed, paused: isPaused, stepped: reduceMotion)
            state.pacer = pacerState
            state.counter = pacerState.counter
        }
    }

    private func fillDisc(_ state: inout StrengthOverlayState, current: StrengthSessionTimeline.Segment, now: Date) {
        let remaining = timeline.segmentRemaining(at: now)
        let seconds = Double(max(1, current.seconds))
        switch current.kind {
        case .leadIn, .rest:
            state.discNumerals = OverlayState.untilStart(Self.wholeSeconds(remaining))
            state.discProgress = remaining / seconds
            state.discMode = .leadIn
            state.discLabel = current.kind == .leadIn ? "GET READY" : "REST"
        case .set:
            state.discNumerals = OverlayState.clock(Self.wholeSeconds(remaining))
            state.discProgress = min(1, timeline.segmentElapsed(at: now) / seconds)
            state.discMode = .full
            state.discLabel = "DONE"
        case .warmUp, .coolDown, .block:
            state.discNumerals = OverlayState.clock(Self.wholeSeconds(remaining))
            let fraction = min(1, timeline.segmentElapsed(at: now) / seconds)
            if current.movement?.perSide == true {
                // The ring shows only the half that is running, as in a movement break.
                let half = state.side == .left ? fraction * 2 : (fraction - 0.5) * 2
                state.discProgress = max(0, min(1, half))
                state.discMode = .halfShare(sideIndex: state.side.index)
                state.discLabel = state.side == .left ? "THEN RIGHT" : "NEXT →"
            } else {
                state.discProgress = fraction
                state.discMode = .full
                state.discLabel = "NEXT →"
            }
        }
        if isPaused { state.discLabel = "PAUSED" }
    }

    private func kicker(for kind: StrengthSessionTimeline.Kind) -> String {
        switch kind {
        case .warmUp: return StrengthOverlayState.warmUpKicker
        case let .set(number), let .rest(beforeSet: number): return StrengthOverlayState.setKicker(number, of: setCount)
        case .coolDown: return StrengthOverlayState.coolDownKicker
        case .leadIn, .block: return ""
        }
    }

    /// A per-side move runs its left side first; a lead-in or rest before one shows left.
    private func side(current: StrengthSessionTimeline.Segment) -> BreakSide {
        let shown = current.movement == nil ? timeline.following : current
        guard shown?.movement?.perSide == true else { return .none }
        return current.movement != nil && timeline.sideSwitched ? .right : .left
    }

    /// Five columns for a strength break (warm-up, the sets, cool-down), one per block for an
    /// end-range break. The column a lead-in or rest leads into is the current one.
    private func strip() -> [StripItem] {
        let currentColumn = timeline.current?.column ?? timeline.columns
        let currentSide = timeline.current.map { side(current: $0) } ?? BreakSide.none
        return (0..<timeline.columns).map { column in
            let itemState: StripItem.State = column < currentColumn
                ? .done
                : (column == currentColumn ? .current : .upcoming)
            return StripItem(
                number: column + 1,
                name: stripName(column: column),
                state: itemState,
                sideIndex: itemState == .current && currentSide != .none ? currentSide.index : nil,
                title: stripTitle(column: column)
            )
        }
    }

    /// A strength column's label: "Warm-up", "Set 1" … "Cool-down". End-range columns are numbered.
    private func stripTitle(column: Int) -> String? {
        switch timeline.flow {
        case .workingSets:
            if column == 0 { return StrengthOverlayState.warmUpKicker }
            if column == timeline.columns - 1 { return StrengthOverlayState.coolDownKicker }
            return "Set \(column)"
        case .endRange:
            return nil
        }
    }

    /// The move under the column's label. An end-range name carries " /side" as a movement
    /// break's does; a strength set says it on its dose line instead.
    private func stripName(column: Int) -> String {
        guard let movement = timeline.segments.first(where: { $0.column == column && $0.movement != nil })?
            .movement else { return "" }
        switch timeline.flow {
        case .workingSets: return movement.name
        case .endRange: return OverlayViewModel.stripName(name: movement.name, perSide: movement.perSide)
        }
    }

    /// Whole seconds, rounded up, so a countdown reads 0:05 the moment a five-second segment
    /// appears and 0:00 only as it ends.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        max(0, Int(seconds.rounded(.up)))
    }
}
