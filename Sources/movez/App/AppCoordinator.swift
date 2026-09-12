import Combine
import Foundation

/// The break currently on screen, with the routine attached.
struct BreakSession: Equatable {
    var routine: Routine
    var startedAt: Date
    var blockIndex: Int = 0
    var completedBlocks: Int = 0
    var deferred: Bool = false

    var block: RoutineBlock? { routine.blocks.indices.contains(blockIndex) ? routine.blocks[blockIndex] : nil }
    var totalBlocks: Int { routine.blocks.count }
    var isLastBlock: Bool { blockIndex >= routine.blocks.count - 1 }
}

/// How the menu bar presents the scheduler right now.
enum MenuMode: String, Equatable {
    case sitting
    case paused
    case offHours
    case breaking
}

/// What the menu bar shows, refreshed on every effect.
struct MenuState: Equatable {
    var mode: MenuMode = .sitting
    var secondsUntilBreak: Int?
    var nextBreakAt: Date?
    var pausedUntil: Date?
    var nextRoutineSubtitle: String = ""
    var statsLine: String = "Today · 0 done · 0 snoozed · 0 skipped"
    var longestBoutLine: String = "Longest sitting bout 0 m"
    var streak: Int = 0
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
    @Published var currentMicro: MicroBreak?
    @Published var headsUpInfo: HeadsUpInfo?
    @Published var toastInfo: ToastInfo?
    @Published var todayStats = DailyStats.empty
    @Published var streak = 0
    @Published var nextRoutinePreview: Routine?

    /// The running coordinator. App Intents are created by the system with no way to be handed
    /// dependencies, so the Focus Filter needs a way home.
    @MainActor private(set) static weak var shared: AppCoordinator?

    let clock: Clock
    let library: MovementLibrary
    let history: HistoryStore
    let settings: SettingsStore
    let builder: RoutineBuilder
    let microBuilder: MicroBreakBuilder
    var scheduler: Scheduler

    let snapshotStore: SnapshotStore?
    private var sink: EffectSink
    /// The real system monitors, attached at launch and absent in tests.
    var aggregator: SignalAggregator?
    var powerMonitor: PowerMonitor?
    private var tickTimer: DispatchSourceTimer?
    private var wakeCheckTimer: DispatchSourceTimer?
    private var cancellables: Set<AnyCancellable> = []

    /// Routines already served today, so the builder can avoid repeats and know whether balance
    /// has been covered.
    var routinesToday: [Routine] = []
    var routinesDayKey = ""
    var lastMicroIds: Set<String> = []
    /// The routine the menu is currently advertising, kept so the overlay serves exactly what the
    /// menu promised. Rebuilt whenever anything it depends on moves.
    var cachedPreview: (key: String, routine: Routine)?

    /// How often the coordinator asks the scheduler to look at the clock.
    static let tickSeconds: TimeInterval = 2
    /// The slowest the tick may become, so a 60x debug clock still gets ticks that matter.
    static let minimumTickSeconds: TimeInterval = 0.25
    /// While paused or off-hours nothing is polled, but something still has to notice when the
    /// pause runs out or the working day opens. That is this timer, not polling.
    static let wakeCheckSeconds: TimeInterval = 30

    init(
        library: MovementLibrary,
        settings: SettingsStore,
        history: HistoryStore,
        clock: Clock,
        snapshotStore: SnapshotStore? = nil,
        sink: EffectSink? = nil
    ) {
        self.library = library
        self.settings = settings
        self.history = history
        self.clock = clock
        self.snapshotStore = snapshotStore
        self.sink = sink ?? NoopEffectSink()
        builder = RoutineBuilder(library: library)
        microBuilder = MicroBreakBuilder(library: library)

        let config = settings.schedulerConfig
        if let restored = try? snapshotStore?.load() ?? nil {
            scheduler = Scheduler(snapshot: restored, config: config)
        } else {
            scheduler = Scheduler(config: config, now: clock.now)
        }
        routinesDayKey = DayKey.key(for: clock.now, calendar: config.calendar)
        refreshPublished()
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
        restartTimers()
        refreshPublished()
    }

    /// Wires the real macOS monitors in. Tests drive the scheduler directly and never call this.
    func attachSystemSignals() {
        let aggregator = SignalAggregator(
            idle: IdleMonitor(),
            mic: MicrophoneMonitor(),
            capture: ScreenCaptureMonitor(),
            fullscreen: FullscreenMonitor(),
            clock: clock,
            settings: settings,
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
        wakeCheckTimer?.cancel()
        wakeCheckTimer = nil
    }

    /// One pass of the clock. Exposed so the tests can drive a whole day in milliseconds.
    func tick() {
        deliver(scheduler.handle(.tick, now: clock.now))
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
        deliver(scheduler.handle(.settingsChanged(settings.schedulerConfig), now: clock.now))
    }

    private func applyTimeScale() {
        (clock as? SystemClock)?.timeScale = max(1, settings.debugTimeScale)
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
            tickTimer = makeTimer(interval: interval) { [weak self] in self?.tick() }
        } else {
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
        for effect in effects {
            apply(effect)
            if case .pollingChanged = effect { pollingChanged = true }
            sink.apply(effect, coordinator: self)
        }
        if pollingChanged, tickTimer != nil || wakeCheckTimer != nil { restartTimers() }
        refreshPublished()
    }

    func refreshPublished() {
        let now = clock.now
        todayStats = history.stats(on: now)
        streak = history.streak(on: now)
        nextRoutinePreview = previewNextRoutine(now: now)
        menuState = makeMenuState(now: now)
    }

    /// Throws the cached preview away, so the next read rebuilds it against current settings.
    func invalidatePreview() {
        cachedPreview = nil
    }
}
