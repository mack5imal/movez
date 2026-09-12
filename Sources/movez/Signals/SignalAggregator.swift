import AppKit
import Foundation

/// Polls the system signals and hands them to the coordinator.
///
/// It runs only while the scheduler can act on what it would learn: nothing is polled while the
/// user has paused movez or is outside working hours. That is the whole of the app's idle CPU
/// story.
@MainActor
final class SignalAggregator {
    /// How often the real app samples the signals.
    static let pollSeconds: TimeInterval = 2
    static let minimumPollSeconds: TimeInterval = 0.25
    /// A gap larger than this between polls means the machine was asleep, not busy.
    static let tickGapThresholdSeconds: TimeInterval = 10
    /// A synthesized wake this close to a real one is a duplicate.
    static let wakeCoalesceSeconds: TimeInterval = 5

    private let idle: IdleSource
    private let mic: MicSource
    private let capture: CaptureSource
    private let fullscreen: FullscreenSource
    private let clock: Clock
    private let settings: SettingsStore
    private let dispatch: (SchedulerEvent) -> Void

    private var timer: DispatchSourceTimer?
    private(set) var pollCount = 0
    private(set) var lastPollAt: Date?
    private(set) var lastWakeAt: Date?
    private(set) var lastSnapshot = SignalSnapshot.quiet

    init(
        idle: IdleSource,
        mic: MicSource,
        capture: CaptureSource,
        fullscreen: FullscreenSource,
        clock: Clock,
        settings: SettingsStore,
        dispatch: @escaping (SchedulerEvent) -> Void
    ) {
        self.idle = idle
        self.mic = mic
        self.capture = capture
        self.fullscreen = fullscreen
        self.clock = clock
        self.settings = settings
        self.dispatch = dispatch
    }

    // MARK: - Lifecycle

    /// How often the sources are sampled, which the debug time scale speeds up.
    var pollInterval: TimeInterval {
        max(Self.minimumPollSeconds, Self.pollSeconds / max(1, settings.debugTimeScale))
    }

    func start() {
        guard timer == nil else { return }
        lastPollAt = clock.now
        let interval = pollInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lastPollAt = nil
    }

    var isRunning: Bool { timer != nil }

    /// Called by the coordinator when the scheduler's polling requirement changes.
    func setPolling(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    /// Picks up a new `pollInterval` — the debug time scale changing is the only thing that moves
    /// it, and a 60x session polled every two seconds would miss most of what it is meant to see.
    func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    // MARK: - Polling

    /// One sample. Exposed so tests can drive it on a manual clock.
    func poll() {
        let now = clock.now
        detectTickGap(now: now)
        lastPollAt = now
        pollCount += 1

        let snapshot = read(now: now)
        lastSnapshot = snapshot

        dispatch(.input(lastEventAgeSeconds: snapshot.idleSeconds))
        dispatch(.idle(seconds: snapshot.idleSeconds))
        dispatch(.signals(snapshot))
    }

    /// Reads every source, then lets the settings veto each signal.
    ///
    /// Each source is asked only when the setting that would act on it is on. The fullscreen one
    /// matters most: its reading is a window-server round trip that bridges every on-screen
    /// window on the machine, and it used to happen twice a second whether the toggle was on or
    /// not — the frontmost app's own bundle id is all the snapshot needs otherwise.
    func read(now: Date) -> SignalSnapshot {
        let reading = settings.suppressFullscreen
            ? fullscreen.reading(exceptions: Set(settings.fullscreenExceptions))
            : FullscreenReading(isFullscreen: false, bundleId: frontmostBundleId())
        return SignalSnapshot(
            idleSeconds: max(0, Int(idle.idleSeconds())),
            microphoneActive: settings.suppressMic && mic.isInUse(),
            screenCaptureActive: settings.suppressCapture && capture.isCaptured(),
            fullscreenActive: reading.isFullscreen,
            frontmostBundleId: reading.bundleId
        )
    }

    private func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// A long gap between polls means the process was suspended — the machine slept without the
    /// notification arriving, or arriving late.
    private func detectTickGap(now: Date) {
        guard let last = lastPollAt else { return }
        let gap = now.timeIntervalSince(last)
        guard gap > Self.tickGapThresholdSeconds else { return }
        if let lastWake = lastWakeAt, now.timeIntervalSince(lastWake) < Self.wakeCoalesceSeconds { return }
        lastWakeAt = now
        dispatch(.gapDetected(seconds: Int(gap)))
    }

    /// Records that a real wake notification arrived, so the next poll does not synthesize one.
    func noteRealWake(at date: Date) {
        lastWakeAt = date
    }
}
