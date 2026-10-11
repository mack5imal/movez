import Foundation

/// Drives the overlay: one tick a second, block by block, with the rules about what the user may
/// do at each moment.
///
/// Every block opens with a five-second lead-in, the first included, so the movement can be read
/// before its clock starts. The transition chime plays as a movement appears, at the start of its
/// lead-in; the first one appears with the overlay and needs no chime.
///
/// It owns nothing except the break in front of it. Ending, snoozing and skipping are reported
/// through `OverlayActions`; recording what was done is the coordinator's job.
@MainActor
final class OverlayViewModel: ObservableObject {
    /// How long Skip stays inert at the start of a break, so nobody dismisses it by reflex.
    static let skipDelaySeconds: TimeInterval = 3
    /// How long one pause may last before the break ends on its own. A pause is for reading a
    /// movement, not for parking the break; after five minutes it has been abandoned.
    static let pauseLimitSeconds: TimeInterval = 300

    @Published private(set) var state = OverlayState()

    let routine: Routine
    let startedAt: Date
    private let clock: Clock
    private let chimes: ChimePlayer?
    /// The scheduler's own rules, so the overlay and the state machine agree about what counts.
    private let config: SchedulerConfig
    private let reduceMotion: Bool

    private(set) var blockIndex = 0
    private(set) var completedBlocks = 0
    private(set) var side: BreakSide = .none
    private(set) var phase: OverlayState.Phase = .running
    /// When the current block appeared, which is when its lead-in began.
    private var blockStartedAt: Date
    private var halfwayChimed = false
    /// When the current pause began, if the break is paused.
    private var pausedAt: Date?
    /// Every finished pause added together. The break's own time is the wall clock less this.
    private var pausedTotal: TimeInterval = 0
    private var pauseExpiredHandled = false
    /// The strip only changes when the block or the side does, not on every tick.
    private var cachedStrip: [StripItem] = []

    var snoozesLeft: Int
    var skipsToday: Int
    var streak: Int
    var nextBreakAt: Date?

    /// Callbacks into the app. Set by the window controller; inert for snapshots and unit tests
    /// that only care about the state.
    var onBlockCompleted: ((RoutineBlock, Int) -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    /// A pause ran its five minutes and the break did not yet count.
    var onPauseExpired: (() -> Void)?
    /// Blocks completed, blocks planned, and seconds the break ran.
    var onFinished: ((Int, Int, Int) -> Void)?

    init(
        routine: Routine,
        startedAt: Date,
        clock: Clock,
        config: SchedulerConfig = SchedulerConfig(),
        chimes: ChimePlayer? = nil,
        snoozesLeft: Int = 2,
        skipsToday: Int = 0,
        streak: Int = 0,
        nextBreakAt: Date? = nil,
        reduceMotion: Bool = false
    ) {
        self.routine = routine
        self.startedAt = startedAt
        self.clock = clock
        self.config = config
        self.chimes = chimes
        self.snoozesLeft = snoozesLeft
        self.skipsToday = skipsToday
        self.streak = streak
        self.nextBreakAt = nextBreakAt
        self.reduceMotion = reduceMotion
        blockStartedAt = startedAt
        side = routine.blocks.first?.perSide == true ? .left : .none
        rebuildStrip()
        refresh()
    }

    // MARK: - Derived values

    var block: RoutineBlock? { routine.blocks.indices.contains(blockIndex) ? routine.blocks[blockIndex] : nil }
    var totalBlocks: Int { routine.blocks.count }
    var isLastBlock: Bool { blockIndex >= totalBlocks - 1 }

    /// Animations are the first thing to go when the user has asked the system for less motion.
    var animationsEnabled: Bool { !reduceMotion }

    /// The break's own time. Every countdown on screen reads this one value, so a pause stops
    /// them all at once: while paused it stands still, and afterwards it runs behind the wall
    /// clock by however long the pauses lasted.
    private var now: Date { (pausedAt ?? clock.now).addingTimeInterval(-pausedTotal) }

    var isPaused: Bool { pausedAt != nil }

    /// Whole seconds before the current pause ends the break, rounded up.
    var pauseRemaining: Int {
        guard let pausedAt else { return 0 }
        return max(0, Int((Self.pauseLimitSeconds - clock.now.timeIntervalSince(pausedAt)).rounded(.up)))
    }

    /// When the movement itself starts, after its lead-in.
    var movementStartsAt: Date { blockStartedAt.addingTimeInterval(TimeInterval(Routine.leadInSeconds)) }
    /// When the block on screen is planned to end.
    var blockEndsAt: Date { movementStartsAt.addingTimeInterval(TimeInterval(block?.seconds ?? 0)) }
    var isLeadIn: Bool { now < movementStartsAt }
    /// Whole seconds of lead-in left, rounded up like the panels' count-ins, so it reads 0:05 the
    /// moment the movement appears.
    var leadInRemaining: Int { max(0, Int(movementStartsAt.timeIntervalSince(now).rounded(.up))) }

    /// Seconds of the movement itself that have run; zero throughout the lead-in.
    var blockElapsed: Int { max(0, Int(now.timeIntervalSince(movementStartsAt))) }
    var blockRemaining: Int { max(0, (block?.seconds ?? 0) - blockElapsed) }

    /// What is left of the break: the rest of the block on screen, then every block after it as
    /// planned, lead-ins included.
    ///
    /// It is worked out from the plan rather than from when the break started. Measured from the
    /// start, it drifted from the movement's own countdown by up to a second a block — each block
    /// began on whichever tick noticed the last one end — and pressing Next never moved it at all.
    /// Rounded up the way the disc is, so the two always differ by exactly the blocks still to come.
    var breakRemaining: Int {
        guard phase == .running, block != nil else { return 0 }
        let current = max(0, blockEndsAt.timeIntervalSince(now)).rounded(.up)
        let later = routine.blocks.dropFirst(blockIndex + 1).reduce(0) { $0 + Routine.leadInSeconds + $1.seconds }
        return Int(current) + later
    }

    /// Done replaces Snooze once the break has actually been done: half the blocks, or half the
    /// planned time.
    ///
    /// It asks the scheduler's own rule rather than restating it. The two used to disagree —
    /// the overlay offered Done at half the *routine*, the scheduler counted half the configured
    /// break — so on a short routine the user could press Done and be recorded as having skipped.
    var doneAvailable: Bool {
        Scheduler.meetsCompletionRule(
            completed: completedBlocks,
            total: totalBlocks,
            elapsed: elapsedSeconds,
            config: config
        )
    }

    /// Whole seconds the break has been running.
    var elapsedSeconds: Int { max(0, Int(now.timeIntervalSince(startedAt))) }

    var skipEnabled: Bool {
        now.timeIntervalSince(startedAt) >= Self.skipDelaySeconds
    }

    // MARK: - The tick

    /// One second of the break. The overlay's whole clock is this method.
    ///
    /// A block that has run out hands over at its planned end, not at the tick that noticed: the
    /// next one is already that much under way. A tick late enough to cover several blocks (the
    /// debug time scale) walks through each of them.
    func tick() {
        guard phase == .running else { return }
        // Paused, nothing moves and nothing chimes; the only thing that can happen is the limit.
        if let pausedAt {
            if clock.now.timeIntervalSince(pausedAt) >= Self.pauseLimitSeconds {
                pauseExpired()
            } else {
                refresh()
            }
            return
        }
        while block != nil, now >= blockEndsAt {
            advance(recordCompletion: true, nextStartsAt: blockEndsAt)
            guard phase == .running else { return }
        }
        guard let block, !isLeadIn else {
            refresh()
            return
        }

        if block.perSide, !halfwayChimed, blockElapsed >= block.seconds / 2 {
            halfwayChimed = true
            side = .right
            rebuildStrip()
            chimes?.play(.transition)
        }
        refresh()
    }

    // MARK: - Actions

    /// The disc, → and Return all land here, in a lead-in as much as in a movement. There is
    /// deliberately no way back.
    ///
    /// Paused, it does nothing: the pause is there so the movement can be read, and a stray
    /// Return should not move on from it.
    func next() {
        guard phase == .running, !isPaused else { return }
        advance(recordCompletion: true, nextStartsAt: now)
    }

    func snooze() {
        guard phase == .running, snoozesLeft > 0, !doneAvailable else { return }
        onSnooze?()
    }

    func skip() {
        guard phase == .running, skipEnabled else { return }
        onSkip?()
    }

    func done() {
        guard phase == .running, doneAvailable else { return }
        finish()
    }

    /// The Pause button and Space. Snooze, Skip and Done still work while paused.
    func togglePause() {
        guard phase == .running else { return }
        if let pausedAt {
            pausedTotal += clock.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        } else {
            pausedAt = clock.now
        }
        refresh()
    }

    /// Five minutes paused. A break that already counts ends as done, as Done would have ended
    /// it; any other ends as snoozed, whether or not a snooze is left, because it is coming back
    /// rather than being skipped.
    private func pauseExpired() {
        guard !pauseExpiredHandled else { return }
        pauseExpiredHandled = true
        togglePause()
        if doneAvailable {
            finish()
        } else {
            onPauseExpired?()
        }
    }

    func choose(side newSide: BreakSide) {
        guard block?.perSide == true else { return }
        side = newSide
        rebuildStrip()
        refresh()
    }

    // MARK: - Progression

    private func advance(recordCompletion: Bool, nextStartsAt: Date) {
        if recordCompletion, let block {
            completedBlocks += 1
            onBlockCompleted?(block, blockIndex)
        }

        guard !isLastBlock else {
            finish()
            return
        }

        blockIndex += 1
        blockStartedAt = nextStartsAt
        halfwayChimed = false
        side = block?.perSide == true ? .left : .none
        rebuildStrip()
        chimes?.play(.transition)
        refresh()
    }

    private func finish() {
        phase = .complete
        rebuildStrip()
        chimes?.play(.completion)
        onFinished?(completedBlocks, totalBlocks, elapsedSeconds)
        refresh()
    }

    // MARK: - State

    /// Rebuilds the plain value the view draws from.
    func refresh() {
        var state = OverlayState()
        state.phase = phase
        state.strip = cachedStrip
        state.streak = streak
        state.skipsToday = skipsToday

        guard phase == .running else {
            state.eyebrow = "\(OverlayState.movementBreakEyebrow) · COMPLETE"
            state.headerTrailing = nextBreakAt.map { "NEXT BREAK \(MovezClock.label($0))" } ?? ""
            state.completionTitle = "Break done"
            state.endSummary = OverlayState.summary(
                movements: completedBlocks,
                nextBreakAt: nextBreakAt.map(MovezClock.label) ?? "the usual time"
            )
            self.state = state
            return
        }

        state.eyebrow = OverlayState.movementBreakEyebrow
        state.headerTrailing = isPaused
            ? "PAUSED · ENDS IN \(OverlayState.clock(pauseRemaining))"
            : "\(OverlayState.clock(breakRemaining)) LEFT"
        if isLeadIn {
            state.discNumerals = OverlayState.untilStart(leadInRemaining)
            state.discProgress = movementStartsAt.timeIntervalSince(now) / Double(Routine.leadInSeconds)
            state.discMode = .leadIn
            state.discLabel = "GET READY"
        } else {
            state.discNumerals = OverlayState.clock(blockRemaining)
            state.discProgress = discProgress
            state.discMode = block?.perSide == true ? .halfShare(sideIndex: side.index) : .full
            state.discLabel = block?.perSide == true && side == .left ? "THEN RIGHT" : "NEXT →"
        }
        if isPaused { state.discLabel = "PAUSED" }
        state.isPaused = isPaused
        state.movementName = block?.movement.name ?? ""
        state.instruction = block?.movement.instructions ?? ""
        state.isSideBlock = block?.perSide == true
        state.side = side
        state.snoozeAvailable = snoozesLeft > 0 && !doneAvailable
        state.doneAvailable = doneAvailable
        state.skipEnabled = skipEnabled
        self.state = state
    }

    /// The fraction of the current block that has run. A per-side block's ring shows only the
    /// half it is in.
    private var discProgress: Double {
        guard let block, block.seconds > 0 else { return 0 }
        let elapsed = Double(blockElapsed) / Double(block.seconds)
        guard block.perSide else { return min(1, elapsed) }
        let halfElapsed = side == .left ? elapsed * 2 : (elapsed - 0.5) * 2
        return max(0, min(1, halfElapsed))
    }

    private func rebuildStrip() {
        cachedStrip = routine.blocks.enumerated().map { index, block in
            let itemState: StripItem.State = phase == .complete
                ? .done
                : (index < blockIndex ? .done : (index == blockIndex ? .current : .upcoming))
            return StripItem(
                number: index + 1,
                name: Self.stripName(block),
                state: itemState,
                sideIndex: itemState == .current && block.perSide ? side.index : nil
            )
        }
    }

    /// The strip abbreviates per-side movements the way the handoff does: "Hip flexor /side".
    static func stripName(_ block: RoutineBlock) -> String {
        guard block.perSide else { return block.movement.name }
        let words = block.movement.name.split(separator: " ")
        let short = words.count > 2 ? words.dropFirst().prefix(2).joined(separator: " ") : block.movement.name
        return "\(short.prefix(1).uppercased())\(short.dropFirst()) /side"
    }

}
