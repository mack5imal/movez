import Combine
import Foundation

/// The break currently on screen, with the break it is serving attached.
///
/// The mode is the one the break was built in. It is kept with the session, not read from the
/// settings, because a switch while the break is on screen applies from the next one (S13).
struct BreakSession: Equatable {
    var planned: PlannedBreak
    var mode: BreakMode
    var startedAt: Date
    var blockIndex: Int = 0
    var completedBlocks: Int = 0
    var deferred: Bool = false

    /// The movement routine, for a Movement break; the overlay shows the others from `planned`.
    var routine: Routine? { planned.routine }
    var part: BreakPart? { planned.parts.indices.contains(blockIndex) ? planned.parts[blockIndex] : nil }
    var totalBlocks: Int { planned.parts.count }
    var isLastBlock: Bool { blockIndex >= planned.parts.count - 1 }
}

/// How the menu bar presents the scheduler right now.
enum MenuMode: String, Equatable {
    case sitting
    case paused
    case offHours
    case breaking
    /// Nobody is at the desk, or the quiet minute after a wake is still deciding what the
    /// absence meant. Either way the countdown on show belongs to an interval that is not
    /// running, so the menu counts the absence instead.
    case away
}

/// What the menu bar shows, refreshed on every effect.
struct MenuState: Equatable {
    var mode: MenuMode = .sitting
    var secondsUntilBreak: Int?
    /// How long the user has been away, while they are.
    var awaySeconds: Int?
    var nextBreakAt: Date?
    var pausedUntil: Date?
    /// The mode the next break will be built in.
    var breakMode: BreakMode = .fallback
    /// The day letter and "break n of N", for a mode that plans its day.
    var dayProgress: ModeDayProgress?
}

/// The one object that ties the pure scheduler to the world: it owns the clock, drives ticks,
/// builds the routine each break will show, records what was done, and publishes the view state
/// every surface binds to.
///
/// The split with `Scheduler` is deliberate. The scheduler knows about time and state; it does
/// not know what a movement is. The coordinator knows about movements and history; it never
/// decides when a break happens. Block transitions are the clearest case: the scheduler is told
/// `.userNextBlock` and answers with a chime, while the coordinator is what actually knows which
/// block just finished and writes it to history.
@MainActor
final class AppCoordinator: ObservableObject {
    // Published view state. Written only by the coordinator's own extensions; the UI reads it.
    @Published var menuState = MenuState()
    @Published var currentBreak: BreakSession?
    /// A break that sleep or a locked screen cut short, kept so the one that resumes is the same
    /// break rather than a fresh routine at block zero.
    var interruptedSession: BreakSession?
    @Published var currentMicro: PlannedMicro?
    /// The mode the micro-break on screen was built in.
    var currentMicroMode: BreakMode?
    @Published var headsUpInfo: HeadsUpInfo?
    @Published var toastInfo: ToastInfo?
    @Published var todayStats = DailyStats.empty
    @Published var nextBreakPreview: PlannedBreak?

    /// The running coordinator. App Intents are created by the system with no way to be handed
    /// dependencies, so the Focus Filter needs a way home.
    @MainActor private(set) static weak var shared: AppCoordinator?

    let clock: Clock
    let library: MovementLibrary
    /// Nil where no strength library was supplied, as in tests that never use Strength mode; the
    /// mode then serves Movement breaks rather than none.
    let strengthLibrary: StrengthLibrary?
    let modeBuilders: ModeBuilderTable
    /// How a strength move served today rules out its movement-library counterpart (S8).
    let crossModeUsage: CrossModeUsage?
    /// The history in use. While the debug clock runs fast this is a scratch copy, so nothing
    /// stamped in scaled time reaches the real record.
    private(set) var history: HistoryStore
    let settings: SettingsStore
    let builder: RoutineBuilder
    let microBuilder: MicroBreakBuilder
    var scheduler: Scheduler

    /// Where the state is written. While the debug clock runs fast this is a scratch store.
    private(set) var snapshotStore: SnapshotStore?
    /// The real history, state store and scheduler state, put aside while the debug clock runs
    /// fast and given back when it returns to 1× (DECISIONS 87).
    private var realWorld: RealWorld?

    /// What a scaled debug run puts aside.
    private struct RealWorld {
        var history: HistoryStore
        var snapshotStore: SnapshotStore?
        var snapshot: SchedulerSnapshot
    }
    /// The scale the clock and the timers were last set to.
    private var appliedTimeScale: Double = 1
    private var sink: EffectSink
    /// The real system monitors, attached at launch and absent in tests.
    var aggregator: SignalAggregator?
    /// Debug values held in front of the real sources. Empty unless an injector is pressed.
    let signalOverrides = SignalOverrides()
    var powerMonitor: PowerMonitor?
    private var tickTimer: DispatchSourceTimer?
    /// How often the tick timer fires, while it runs; nil when it does not.
    private(set) var tickInterval: TimeInterval?
    private var wakeCheckTimer: DispatchSourceTimer?
    /// When the state file was last written, so the heartbeat knows whether it is due.
    /// Written by `persistSnapshot()` in the effects extension.
    var lastPersistAt: Date?
    /// How long the app was not running, measured at launch and spent once by `applyLaunchGap`.
    private var launchGapSeconds: Int?
    private var cancellables: Set<AnyCancellable> = []
    /// Whether the monitors were last told to run, so `deliver` can notice a state that needs
    /// them without an effect having said so.
    private var pollingActive = true
    /// The newest transition already written to the unified log.
    private var lastLoggedTransition: Transition?

    /// Breaks already put on screen today, so the builders can avoid repeats and know whether
    /// balance has been covered.
    var breaksToday: [PlannedBreak] = []
    var routinesDayKey = ""
    var lastMicroIds: Set<String> = []
    /// The break the menu is currently advertising, kept so the overlay serves exactly what the
    /// menu promised. Rebuilt whenever anything it depends on moves.
    var cachedPreview: (key: String, planned: PlannedBreak)?
    /// The break a heads-up on screen announced, in the mode it was built in. The full break that
    /// follows serves this one, even if the mode changed while the heads-up was up.
    var headsUpBreak: (planned: PlannedBreak, mode: BreakMode)?
    /// A heads-up's break, kept for the rest of the effects that dismissed it, so that a snooze or
    /// skip records the break it turned away.
    var dismissedHeadsUpBreak: (planned: PlannedBreak, mode: BreakMode)?
    /// The day's progress the menu shows, refreshed with the preview rather than on every tick,
    /// because the planner reads the whole break history.
    var dayProgress: ModeDayProgress?

    /// How often the coordinator asks the scheduler to look at the clock.
    static let tickSeconds: TimeInterval = 2
    /// How often the state file is refreshed while nothing is transitioning.
    ///
    /// The file doubles as the app's proof of life, and transitions alone are far too sparse to
    /// serve as one — a quiet bout with micro-breaks off writes nothing for the best part of an
    /// hour. This must stay comfortably under the smallest away threshold the settings allow
    /// (two minutes, `SettingsStore.awayThresholdRange`), or a quick relaunch would look like an
    /// absence.
    static let heartbeatSeconds: TimeInterval = 30
    /// The slowest the tick may become, so a 60x debug clock still gets ticks that matter.
    static let minimumTickSeconds: TimeInterval = 0.25
    /// While paused or off-hours nothing is polled, but something still has to notice when the
    /// pause runs out or the working day opens. That is this timer, not polling.
    static let wakeCheckSeconds: TimeInterval = 30
    /// How far in the future a state file's save time may be before it is taken for clock skew
    /// rather than the few seconds two clock reads can disagree by.
    static let clockSkewToleranceSeconds: TimeInterval = 60

    init(
        library: MovementLibrary,
        strengthLibrary: StrengthLibrary? = nil,
        modeBuilders: ModeBuilderTable? = nil,
        settings: SettingsStore,
        history: HistoryStore,
        clock: Clock,
        snapshotStore: SnapshotStore? = nil,
        sink: EffectSink? = nil
    ) {
        self.library = library
        self.strengthLibrary = strengthLibrary
        self.modeBuilders = modeBuilders ?? .standard(strengthLibrary: strengthLibrary, movementLibrary: library)
        crossModeUsage = strengthLibrary.map { CrossModeUsage(movementLibrary: library, strengthLibrary: $0) }
        self.settings = settings
        self.history = history
        self.clock = clock
        self.snapshotStore = snapshotStore
        self.sink = sink ?? NoopEffectSink()
        builder = RoutineBuilder(library: library)
        microBuilder = MicroBreakBuilder(library: library)

        let config = settings.schedulerConfig
        if let restored = AppCoordinator.restore(from: snapshotStore) {
            var snapshot = restored
            // `boutStartedAt` is the fallback for a file written before movez recorded when it
            // saved. It is always earlier than the real save, so the first launch on this build
            // over-states the gap rather than under-stating it — which under a policy that only
            // ever moves the countdown outwards is the harmless direction to be wrong in.
            let aliveAt = snapshot.savedAt ?? snapshot.boutStartedAt
            snapshot.savedAt = nil
            if aliveAt > clock.now.addingTimeInterval(Self.clockSkewToleranceSeconds) {
                // Saved by a clock that ran ahead of this one: an earlier build's debug scale, or
                // a clock set back by hand. Its due times are hours away and its gap measures as
                // nothing, so nothing in it can be trusted; the session starts fresh.
                MovezLog.store.error("state was saved in the future, starting fresh")
                scheduler = Scheduler(config: config, now: clock.now)
            } else {
                launchGapSeconds = max(0, Int(clock.now.timeIntervalSince(aliveAt)))
                scheduler = Scheduler(snapshot: snapshot, config: config)
            }
        } else {
            scheduler = Scheduler(config: config, now: clock.now)
        }
        routinesDayKey = DayKey.key(for: clock.now, calendar: config.calendar)
        pollingActive = scheduler.pollingRequired
        // A restored log was written to the unified log the first time round.
        lastLoggedTransition = scheduler.snapshot.transitions.transitions.last
        refreshPublished()
    }

    /// The active mode's builder.
    var activeModeBuilder: any ModeBreakBuilding { modeBuilders.builder(for: settings.mode.rawValue) }

    /// A state file that will not parse is not worth crashing over — the day simply starts fresh
    /// — but it is worth saying so somewhere a developer can find it.
    static func restore(from store: SnapshotStore?) -> SchedulerSnapshot? {
        guard let store else { return nil }
        do {
            return try store.load()
        } catch {
            MovezLog.store.error("state could not be read, starting fresh: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Lifecycle

    /// Attaches the UI sinks. Called once at launch, after the coordinator exists.
    func register(sink: EffectSink) {
        self.sink = sink
    }

    /// Starts the timers. Head-less command-line runs never call this.
    func start() {
        AppCoordinator.shared = self
        applyTimeScale()
        // Before the timers: a tick that ran first could fire a break off a due time that belongs
        // to a session which ended whenever the app went down.
        applyLaunchGap()
        restartTimers()
        refreshPublished()
    }

    /// Hands the scheduler the stretch the app was not running for. Spent once, at launch.
    func applyLaunchGap() {
        defer { launchGapSeconds = nil }
        guard let seconds = launchGapSeconds else { return }
        deliver(scheduler.applyLaunchGap(seconds: seconds, now: clock.now))
    }

    /// Wires the real macOS monitors in. Tests drive the scheduler directly and never call this.
    func attachSystemSignals() {
        let aggregator = SignalAggregator(
            idle: OverridingIdleSource(IdleMonitor(), overrides: signalOverrides),
            mic: OverridingMicSource(MicrophoneMonitor(), overrides: signalOverrides),
            capture: OverridingCaptureSource(ScreenCaptureMonitor(), overrides: signalOverrides),
            fullscreen: OverridingFullscreenSource(FullscreenMonitor(), overrides: signalOverrides),
            clock: clock,
            settings: settings,
            overrides: signalOverrides,
            dispatch: { [weak self] event in self?.inject(event) }
        )
        self.aggregator = aggregator

        let power = PowerMonitor(
            now: { [weak self] in self?.clock.now ?? Date() },
            lastActivity: { [weak self] in self?.aggregator?.lastPollAt ?? self?.clock.now ?? Date() },
            onEvent: { [weak self] event in
                guard let self else { return }
                if case .wake = event { self.aggregator?.noteRealWake(at: self.clock.now) }
                if case .unlock = event { self.aggregator?.noteRealWake(at: self.clock.now) }
                self.inject(event)
            }
        )
        power.start()
        powerMonitor = power
        aggregator.setPolling(scheduler.pollingRequired)
    }

    func stop() {
        aggregator?.stop()
        powerMonitor?.stop()
        tickTimer?.cancel()
        tickTimer = nil
        tickInterval = nil
        wakeCheckTimer?.cancel()
        wakeCheckTimer = nil
    }

    /// One pass of the clock. Exposed so the tests can drive a whole day in milliseconds.
    func tick() {
        deliver(scheduler.handle(.tick, now: clock.now))
        // Nothing is written while paused or off hours: there is no session to be alive in, and a
        // gap in those states is ignored anyway.
        if scheduler.pollingRequired,
           clock.now.timeIntervalSince(lastPersistAt ?? .distantPast) >= Self.heartbeatSeconds {
            deliver([.persist])
        }
        // The countdown in the menu bar moves every tick even when no effect fires.
        menuState = makeMenuState(now: clock.now)
    }

    /// The signal monitors report through here.
    func report(inputAgeSeconds: Int) {
        deliver(scheduler.handle(.input(lastEventAgeSeconds: inputAgeSeconds), now: clock.now))
    }

    func report(signals: SignalSnapshot) {
        deliver(scheduler.handle(.signals(signals), now: clock.now))
        if signals.idleSeconds > 0 {
            deliver(scheduler.handle(.idle(seconds: signals.idleSeconds), now: clock.now))
        }
    }

    /// Sends any event straight through — the path the debug injectors use.
    func inject(_ event: SchedulerEvent) {
        deliver(scheduler.handle(event, now: clock.now))
    }

    /// Pushes the current settings into the scheduler without disturbing the sitting bout.
    func settingsChanged() {
        applyTimeScale()
        invalidatePreview()
        var config = settings.schedulerConfig
        config.breakSeconds = previewNextBreak(now: clock.now).plannedSeconds
        deliver(scheduler.handle(.settingsChanged(config), now: clock.now))
    }

    /// Sets the clock and the timers to the debug scale, and swaps the stores when it crosses 1×.
    ///
    /// Everything that happens while the clock runs fast is stamped in a future that never comes,
    /// so it goes to scratch: a copy of the history and an in-memory state store. Back at 1× the
    /// clock snaps to the wall, the real stores and the scheduler state from before come back,
    /// and the countdown starts again from now (DECISIONS 87).
    private func applyTimeScale() {
        let scale = max(1, settings.debugTimeScale)
        guard scale != appliedTimeScale else { return }
        let wasScaled = appliedTimeScale > 1
        appliedTimeScale = scale
        if !wasScaled, scale > 1 { enterScratch() }
        (clock as? SystemClock)?.timeScale = scale
        if wasScaled, scale == 1 { leaveScratch() }
        aggregator?.restartIfRunning()
        if tickTimer != nil || wakeCheckTimer != nil { restartTimers() }
    }

    private func enterScratch() {
        realWorld = RealWorld(history: history, snapshotStore: snapshotStore, snapshot: scheduler.snapshot)
        history = HistoryStore(data: history.data, calendar: settings.schedulerConfig.calendar)
        snapshotStore = InMemorySnapshotStore()
    }

    private func leaveScratch() {
        // Whatever is on screen belongs to the scaled run; it is taken down while the scratch
        // stores are still the ones it would write to.
        deliver(scheduler.dismissSurfaces(now: clock.now))
        guard let real = realWorld else { return }
        realWorld = nil
        history = real.history
        snapshotStore = real.snapshotStore
        scheduler = Scheduler(snapshot: real.snapshot, config: scheduler.config)
        invalidatePreview()
        switch scheduler.state {
        // A pause or off hours ends at a time the real clock still keeps.
        case .paused, .offHours:
            deliver([.persist, .menuRefresh])
        default:
            deliver(scheduler.startFreshSession(now: clock.now, reason: "debug clock back to real time"))
        }
    }

    // MARK: - Timers

    private func restartTimers() {
        tickTimer?.cancel()
        tickTimer = nil
        wakeCheckTimer?.cancel()
        wakeCheckTimer = nil

        if scheduler.pollingRequired {
            let scale = max(1, settings.debugTimeScale)
            let interval = max(Self.minimumTickSeconds, Self.tickSeconds / scale)
            tickInterval = interval
            tickTimer = makeTimer(interval: interval) { [weak self] in self?.tick() }
        } else {
            tickInterval = nil
            wakeCheckTimer = makeTimer(interval: Self.wakeCheckSeconds) { [weak self] in self?.tick() }
        }
    }

    private func makeTimer(interval: TimeInterval, action: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: action)
        timer.resume()
        return timer
    }

    // MARK: - Effect delivery

    func deliver(_ effects: [SchedulerEffect]) {
        guard !effects.isEmpty else { return }
        var pollingChanged = false
        defer { dismissedHeadsUpBreak = nil }
        for planned in effects {
            let effect = attachingBreak(to: planned)
            apply(effect)
            if case .pollingChanged = effect { pollingChanged = true }
            sink.apply(effect, coordinator: self)
        }
        // The kept session is only good while the scheduler still holds the interruption it
        // belongs to. A wake after the break's planned end settles the interruption without
        // starting a break, and a session kept past that point would stand in for the next break
        // in the preview, the break length and the next start.
        if scheduler.snapshot.interruptedBreak == nil { interruptedSession = nil }
        logNewTransitions()
        // Whether the monitors run is a fact about the state the scheduler is in, not about which
        // effects it remembered to emit on the way there. A wake that took the scheduler out of
        // off hours without `.pollingChanged` used to leave them stopped in a state that needs them.
        if scheduler.pollingRequired != pollingActive {
            if !pollingChanged { aggregator?.setPolling(scheduler.pollingRequired) }
            pollingChanged = true
        }
        pollingActive = scheduler.pollingRequired
        if pollingChanged, tickTimer != nil || wakeCheckTimer != nil { restartTimers() }
        refreshPublished()
    }

    /// Writes each transition the scheduler has just made to the unified log.
    ///
    /// The snapshot keeps only the last twenty, which a flapping microphone uses up within the
    /// hour; the unified log keeps days, which is what an overnight sleep bug needs to be read.
    private func logNewTransitions() {
        let transitions = scheduler.snapshot.transitions.transitions
        let fresh = transitions.reversed().prefix { $0 != lastLoggedTransition }.reversed()
        for transition in fresh {
            let line = "\(transition.from.name) → \(transition.to.name) (\(transition.reason))"
            MovezLog.scheduler.notice("\(line, privacy: .public)")
        }
        lastLoggedTransition = transitions.last
    }

    /// Republishes what an effect may have changed.
    ///
    /// Each assignment is guarded: `@Published` fires on every write, equal or not, and four
    /// unconditional writes here wake every view model four times for one event.
    func refreshPublished() {
        let now = clock.now
        assign(history.stats(on: now), to: \.todayStats)
        let preview = previewNextBreak(now: now)
        assign(preview, to: \.nextBreakPreview)
        dayProgress = activeModeBuilder.dayProgress(for: self, at: now)
        syncBreakLength(preview)
        menuState = makeMenuState(now: now)
    }

    /// Tells the scheduler how long the break it will start next runs.
    ///
    /// The length goes in through the config whenever the preview changes, rather than with the
    /// start of the break, because the scheduler starts a break on its own clock (the heads-up
    /// running out) and has the length to hand when it does; and it goes in through its own event
    /// rather than `.settingsChanged`, which persists and redraws for a change the user made. The
    /// preview is the break on screen while there is one, so a running break's
    /// "done at half" is measured against that break, not the one after it.
    private func syncBreakLength(_ preview: PlannedBreak) {
        guard scheduler.config.breakSeconds != preview.plannedSeconds else { return }
        deliver(scheduler.handle(.breakLength(seconds: preview.plannedSeconds), now: clock.now))
    }

    private func assign<Value: Equatable>(_ value: Value, to keyPath: ReferenceWritableKeyPath<AppCoordinator, Value>) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    /// Throws the cached preview away, so the next read rebuilds it against current settings.
    func invalidatePreview() {
        cachedPreview = nil
    }
}
