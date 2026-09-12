import Foundation

/// Drives the overlay: one tick a second, block by block, with the rules about what the user may
/// do at each moment.
///
/// It owns nothing except the break in front of it. Ending, snoozing and skipping are reported
/// through `OverlayActions`; recording what was done is the coordinator's job.
@MainActor
final class OverlayViewModel: ObservableObject {
    /// How long Skip stays inert at the start of a break, so nobody dismisses it by reflex.
    static let skipDelaySeconds: TimeInterval = 3

    @Published private(set) var state = OverlayState()

    let routine: Routine
    let startedAt: Date
    private let clock: Clock
    private let chimes: ChimePlayer?
    private var collapsed: Set<String>
    private let persistCollapsed: (String, Bool) -> Void
    private let reduceMotion: Bool

    private(set) var blockIndex = 0
    private(set) var completedBlocks = 0
    private(set) var side: BreakSide = .none
    private(set) var phase: OverlayState.Phase = .running
    private var blockStartedAt: Date
    private var halfwayChimed = false

    var snoozesLeft: Int
    var skipsToday: Int
    var streak: Int
    var nextBreakAt: Date?

    /// Callbacks into the app. Set by the window controller; inert for snapshots and unit tests
    /// that only care about the state.
    var onBlockCompleted: ((RoutineBlock, Int) -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    var onFinished: ((Int, Int) -> Void)?

    init(
        routine: Routine,
        startedAt: Date,
        clock: Clock,
        chimes: ChimePlayer? = nil,
        collapsed: Set<String> = [],
        snoozesLeft: Int = 2,
        skipsToday: Int = 0,
        streak: Int = 0,
        nextBreakAt: Date? = nil,
        reduceMotion: Bool = false,
        persistCollapsed: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self.routine = routine
        self.startedAt = startedAt
        self.clock = clock
        self.chimes = chimes
        self.collapsed = collapsed
        self.snoozesLeft = snoozesLeft
        self.skipsToday = skipsToday
        self.streak = streak
        self.nextBreakAt = nextBreakAt
        self.reduceMotion = reduceMotion
        self.persistCollapsed = persistCollapsed
        blockStartedAt = startedAt
        side = routine.blocks.first?.perSide == true ? .left : .none
        refresh()
    }

    // MARK: - Derived values

    var block: RoutineBlock? { routine.blocks.indices.contains(blockIndex) ? routine.blocks[blockIndex] : nil }
    var totalBlocks: Int { routine.blocks.count }
    var isLastBlock: Bool { blockIndex >= totalBlocks - 1 }

    /// Animations are the first thing to go when the user has asked the system for less motion.
    var animationsEnabled: Bool { !reduceMotion }

    var blockElapsed: Int { max(0, Int(clock.now.timeIntervalSince(blockStartedAt))) }
    var blockRemaining: Int { max(0, (block?.seconds ?? 0) - blockElapsed) }
    var breakRemaining: Int {
        let planned = routine.totalSeconds
        return max(0, planned - Int(clock.now.timeIntervalSince(startedAt)))
    }

    /// Done replaces Snooze once the break has actually been done: half the blocks, or half the
    /// planned time.
    var doneAvailable: Bool {
        completedBlocks >= Int((Double(totalBlocks) * 0.5).rounded(.up))
            || Int(clock.now.timeIntervalSince(startedAt)) >= routine.totalSeconds / 2
    }

    var skipEnabled: Bool {
        clock.now.timeIntervalSince(startedAt) >= Self.skipDelaySeconds
    }

    var instructionCollapsed: Bool {
        block.map { collapsed.contains($0.movement.id) } ?? false
    }

    // MARK: - The tick

    /// One second of the break. The overlay's whole clock is this method.
    func tick() {
        guard phase == .running, let block else { return }

        if block.perSide, !halfwayChimed, blockElapsed >= block.seconds / 2 {
            halfwayChimed = true
            side = .right
            chimes?.play(.transition)
        }

        if blockElapsed >= block.seconds {
            advance(recordCompletion: true)
            return
        }
        refresh()
    }

    // MARK: - Actions

    /// The disc, → and Return all land here. There is deliberately no way back.
    func next() {
        guard phase == .running else { return }
        advance(recordCompletion: true)
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

    func toggleCollapsed() {
        guard let block else { return }
        let id = block.movement.id
        let nowCollapsed = !collapsed.contains(id)
        if nowCollapsed { collapsed.insert(id) } else { collapsed.remove(id) }
        persistCollapsed(id, nowCollapsed)
        refresh()
    }

    func choose(side newSide: BreakSide) {
        guard block?.perSide == true else { return }
        side = newSide
        refresh()
    }

    // MARK: - Progression

    private func advance(recordCompletion: Bool) {
        if recordCompletion, let block {
            completedBlocks += 1
            onBlockCompleted?(block, blockIndex)
        }

        guard !isLastBlock else {
            finish()
            return
        }

        blockIndex += 1
        blockStartedAt = clock.now
        halfwayChimed = false
        side = block?.perSide == true ? .left : .none
        chimes?.play(.transition)
        refresh()
    }

    private func finish() {
        phase = .complete
        chimes?.play(.completion)
        onFinished?(completedBlocks, totalBlocks)
        refresh()
    }

    // MARK: - State

    /// Rebuilds the plain value the view draws from.
    func refresh() {
        var state = OverlayState()
        state.phase = phase
        state.strip = stripItems()
        state.streak = streak
        state.skipsToday = skipsToday

        guard phase == .running else {
            state.eyebrow = "\(routine.name) · complete".uppercased()
            state.headerTrailing = nextBreakAt.map { "NEXT BREAK \(Self.timeLabel($0))" } ?? ""
            state.completionTitle = routine.completionTitle
            state.endSummary = OverlayState.summary(
                movements: completedBlocks,
                nextBreakAt: nextBreakAt.map(Self.timeLabel) ?? "the usual time"
            )
            self.state = state
            return
        }

        state.eyebrow = routine.eyebrow
        state.headerTrailing = "\(OverlayState.clock(breakRemaining)) LEFT"
        state.discNumerals = OverlayState.clock(blockRemaining)
        state.discProgress = discProgress
        state.discMode = block?.perSide == true ? .halfShare(sideIndex: side.index) : .full
        state.discLabel = block?.perSide == true && side == .left ? "THEN RIGHT" : "NEXT →"
        state.movementName = block?.movement.name ?? ""
        state.instruction = block?.movement.instructions ?? ""
        state.instructionCollapsed = instructionCollapsed
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

    private func stripItems() -> [StripItem] {
        routine.blocks.enumerated().map { index, block in
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

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }
}
