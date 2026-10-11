import Foundation

/// What the floating panels can ask the app to do. Defaults do nothing, which is what the
/// snapshots and the string tests want.
struct PanelActions {
    var startNow: () -> Void = {}
    var snooze: () -> Void = {}
    var skip: () -> Void = {}
    var microStartNow: () -> Void = {}
    var microSnooze: () -> Void = {}
    var microSkip: () -> Void = {}
    var microEnded: () -> Void = {}
    var reverseToast: () -> Void = {}
    /// Take this panel off screen. The controller sets it; nothing else needs to.
    var dismiss: () -> Void = {}
}

/// Drives the three small panels — the heads-up minute, the micro-break, and the away toast.
///
/// One view model rather than three because they are the same object at different moments: a
/// countdown, a title, a body and at most three actions. The phase decides which words go in.
@MainActor
final class PanelViewModel: ObservableObject {
    enum Phase: String, Equatable {
        case headsUp
        case microCountIn
        case microRunning
        case toast
    }

    /// A break that has been waiting for a call to finish, and how long the user has been sitting.
    struct DeferredInfo: Equatable {
        var sittingFor: TimeInterval
        var reason: SuppressionReason = .microphone
    }

    /// How long Skip stays inert, so no panel is dismissed by reflex.
    static let skipDelaySeconds: TimeInterval = 3

    @Published private(set) var phase: Phase
    /// Republished on every tick; every string and ring below is a function of it.
    @Published private(set) var now: Date

    let clock: Clock
    private(set) var startedAt: Date
    private(set) var totalSeconds: Int

    // What the words are made of.
    var blockCount = 0
    var breakMinutes = 5
    var snoozesLeft = 2
    var skipsToday = 0
    var deferred: DeferredInfo?
    var micro: MicroBreak?
    /// The longest a micro-break runs, from the scheduler. The panel runs the micro-break's own
    /// length, which is shorter when it is a single movement.
    var microSeconds = 70
    /// The micro-break's one snooze. A second request is a skip.
    var microSnoozeUsed = false
    var toast: ToastInfo?

    var actions = PanelActions()
    /// Inside a micro-break the panel chimes its own transitions, as the overlay does in a full
    /// break: the scheduler never knows how a micro-break is made up.
    var chimes: ChimePlayer?
    private var microEndSent = false
    private var chimedAppearances: Set<Int> = []
    private var chimedHalfways: Set<Int> = []

    init(phase: Phase, clock: Clock, startedAt: Date, totalSeconds: Int) {
        self.phase = phase
        self.clock = clock
        self.startedAt = startedAt
        self.totalSeconds = totalSeconds
        now = clock.now
    }

    // MARK: - Time

    var elapsed: TimeInterval { max(0, now.timeIntervalSince(startedAt)) }
    var remainingExact: TimeInterval { max(0, Double(totalSeconds) - elapsed) }
    /// Whole seconds left, rounded up, so a countdown shows "1:00" for its whole first second.
    var remaining: Int { Int(remainingExact.rounded(.up)) }
    /// 1 when the panel appears, 0 when its time is up.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return remainingExact / Double(totalSeconds)
    }

    /// One tick of whichever panel is on screen.
    func tick() {
        now = clock.now
        if phase == .microRunning { chimeMicroTransitions() }
        guard remainingExact <= 0 else { return }
        switch phase {
        case .microCountIn:
            beginMicroRunning(at: now)
        case .microRunning:
            guard !microEndSent else { return }
            microEndSent = true
            actions.microEnded()
        case .toast:
            actions.dismiss()
        case .headsUp:
            // The scheduler starts the break; the panel just runs out.
            break
        }
    }

    /// The count-in is over and the movement starts. Driven by the tick, and by the scheduler's
    /// `.showMicroRunning` when the user pressed Start now.
    func beginMicroRunning(at date: Date) {
        guard phase == .microCountIn else { return }
        phase = .microRunning
        startedAt = date
        totalSeconds = micro?.totalSeconds ?? microSeconds
        now = clock.now
    }

    // MARK: - The running micro-break

    /// The block on screen: the count-in shows the first, and each later one takes over as it
    /// appears, at the start of its lead-in.
    var microBlockIndex: Int {
        guard phase == .microRunning, let micro else { return 0 }
        return micro.blocks.indices.last { Double(micro.appearsAt(block: $0)) <= elapsed } ?? 0
    }

    var microBlock: RoutineBlock? {
        guard let micro, micro.blocks.indices.contains(microBlockIndex) else { return nil }
        return micro.blocks[microBlockIndex]
    }

    /// Seconds into the running micro-break at which the block on screen starts moving.
    private var microBlockStart: Double {
        Double(micro?.startsAt(block: microBlockIndex) ?? 0)
    }

    /// The five seconds before each movement starts, the first included.
    var isMicroLeadIn: Bool { phase == .microRunning && elapsed < microBlockStart }

    /// Which side a per-side movement is on.
    var microSide: BreakSide {
        guard let block = microBlock, block.perSide else { return .none }
        return elapsed - microBlockStart >= Double(block.secondsPerSide) ? .right : .left
    }

    private var microBlockRemainingExact: Double {
        guard let block = microBlock else { return 0 }
        if isMicroLeadIn { return microBlockStart - elapsed }
        return max(0, microBlockStart + Double(block.seconds) - elapsed)
    }

    /// The transition chime as each movement appears and at a per-side movement's halfway point,
    /// as in a full break. The first one sounds as the count-in hands over to its lead-in.
    private func chimeMicroTransitions() {
        let index = microBlockIndex
        if chimedAppearances.insert(index).inserted {
            chimes?.play(.transition)
        }
        if microSide == .right, chimedHalfways.insert(index).inserted {
            chimes?.play(.transition)
        }
    }

    // MARK: - Words

    var eyebrow: String {
        switch phase {
        case .headsUp: return OverlayState.movementBreakEyebrow
        case .microCountIn: return MicroBreak.eyebrow(for: microBlock)
        case .microRunning:
            // A per-side movement says which side in the eyebrow, where it fits on one line.
            let eyebrow = MicroBreak.eyebrow(for: microBlock)
            return microSide == .none ? eyebrow : "\(eyebrow) · \(microSide.rawValue.uppercased()) SIDE"
        case .toast: return ""
        }
    }

    var title: String {
        switch phase {
        case .headsUp: return "Movement break in a minute"
        case .microCountIn: return "\(movementName) in a moment"
        case .microRunning: return movementName
        case .toast: return toastTitle
        }
    }

    var body: String {
        switch phase {
        case .headsUp: return Self.headsUpBody(minutes: breakMinutes, movements: blockCount)
        case .microCountIn: return microCountInBody
        case .microRunning: return microBlock?.movement.instructions ?? ""
        case .toast: return toastSubtitle
        }
    }

    /// The block on screen.
    var movementName: String { microBlock?.movement.name ?? "" }

    /// "Five minutes, four movements." — counts this small are spelled out.
    static func headsUpBody(minutes: Int, movements: Int) -> String {
        let minuteWord = minutes == 1 ? "minute" : "minutes"
        let movementWord = movements == 1 ? "movement" : "movements"
        let count = OverlayState.numberWord(movements).lowercased()
        return "\(OverlayState.numberWord(minutes)) \(minuteWord), \(count) \(movementWord)."
    }

    /// "One minute, standing. Starts in 21 seconds." — the seconds count down live.
    var microCountInBody: String {
        let minutes = max(1, (micro?.totalSeconds ?? microSeconds) / 60)
        let minuteWord = minutes == 1 ? "minute" : "minutes"
        let secondWord = remaining == 1 ? "second" : "seconds"
        return "\(OverlayState.numberWord(minutes)) \(minuteWord), \(posture). Starts in \(remaining) \(secondWord)."
    }

    /// A micro-break whose movements can only be done in a chair is done seated; one with anything
    /// that can be done standing is standing.
    var posture: String {
        guard let blocks = micro?.blocks, !blocks.isEmpty else { return "standing" }
        return blocks.allSatisfy { $0.movement.settings == [.chair] } ? "seated" : "standing"
    }

    /// The countdown on the disc.
    ///
    /// A count-in runs towards a break rather than through one, so it wears a minus: the heads-up
    /// minute and the micro-break's thirty seconds both count down to zero, and without it nothing
    /// tells them apart from the break time they are about to hand over to.
    var discNumerals: String {
        switch phase {
        case .microRunning:
            let seconds = Int(microBlockRemainingExact.rounded(.up))
            return isMicroLeadIn ? OverlayState.untilStart(seconds) : OverlayState.clock(seconds)
        case .headsUp, .microCountIn: return OverlayState.untilStart(remaining)
        case .toast: return ""
        }
    }

    /// The disc's ring, which runs the way the full break's does: a movement fills it as it goes,
    /// per side for a per-side one, and a lead-in or count-in drains it towards the start.
    var discProgress: Double {
        guard phase == .microRunning, let block = microBlock else { return progress }
        if isMicroLeadIn { return microBlockRemainingExact / Double(Routine.leadInSeconds) }
        guard block.perSide else { return max(0, min(1, 1 - microBlockRemainingExact / Double(max(1, block.seconds)))) }
        let half = Double(max(1, block.secondsPerSide))
        let sideRemaining = microSide == .left ? microBlockRemainingExact - half : microBlockRemainingExact
        return max(0, min(1, 1 - sideRemaining / half))
    }

    var discMode: TimerDiscMode {
        guard phase == .microRunning else { return .full }
        if isMicroLeadIn { return .leadIn }
        return microBlock?.perSide == true ? .halfShare(sideIndex: microSide.index) : .full
    }

    /// "Sitting for 1 h 35 m · break waited for your call"
    var deferredBadge: String? {
        guard let deferred else { return nil }
        let sitting = AppCoordinator.duration(Int(deferred.sittingFor))
        return "Sitting for \(sitting) · break waited for \(deferred.reason.phrase)"
    }

    var skipLabel: String { phase == .headsUp ? "Skip · \(skipsToday) today" : "Skip" }

    /// Once the snoozes are gone the button is omitted rather than disabled — a dead button is
    /// worse than no button.
    var showSnooze: Bool {
        switch phase {
        case .headsUp: return snoozesLeft > 0
        case .microCountIn, .microRunning: return true
        case .toast: return false
        }
    }

    var skipEnabled: Bool { elapsed >= Self.skipDelaySeconds }

    /// The deferred variant widens to fit its badge.
    var panelWidth: CGFloat {
        deferred == nil ? Tokens.Metric.panelWidth : Tokens.Metric.panelWidthDeferred
    }

    // MARK: - Toast words

    var toastTitle: String {
        guard let toast else { return "" }
        let credited = toast.kind == .creditedFullBreak ? "counted as your break" : "counted as a micro-break"
        return "Away \(toast.awaySeconds / 60) min · \(credited)"
    }

    var toastSubtitle: String {
        guard let next = toast?.nextBreakAt else { return "" }
        return "Next break at \(MovezClock.label(next))"
    }

    // MARK: - Actions

    func startNow() {
        switch phase {
        case .headsUp: actions.startNow()
        case .microCountIn: actions.microStartNow()
        case .microRunning, .toast: break
        }
    }

    func snooze() {
        switch phase {
        case .headsUp:
            guard snoozesLeft > 0 else { return }
            snoozesLeft -= 1
            actions.snooze()
        case .microCountIn, .microRunning:
            // One snooze puts the micro-break back in five minutes; asking twice is a skip.
            if microSnoozeUsed {
                actions.microSkip()
            } else {
                microSnoozeUsed = true
                actions.microSnooze()
            }
        case .toast:
            break
        }
    }

    func skip() {
        guard skipEnabled else { return }
        switch phase {
        case .headsUp: actions.skip()
        case .microCountIn, .microRunning: actions.microSkip()
        case .toast: break
        }
    }

    /// "I was sitting" — hand the credit back and take the toast away.
    func reverse() {
        guard phase == .toast else { return }
        actions.reverseToast()
        actions.dismiss()
    }

    /// "Dismiss" — take the toast away and keep the credit, exactly as running out of time does.
    func dismissToast() {
        guard phase == .toast else { return }
        actions.dismiss()
    }
}
