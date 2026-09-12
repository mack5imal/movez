import Foundation

/// Settable stand-ins for the four system sources, used by the tests and by the debug injectors
/// in the settings window.
final class FakeIdleSource: IdleSource {
    var seconds: TimeInterval = 0
    func idleSeconds() -> TimeInterval { seconds }
}

final class FakeMicSource: MicSource {
    var inUse = false
    func isInUse() -> Bool { inUse }
}

final class FakeCaptureSource: CaptureSource {
    var captured = false
    func isCaptured() -> Bool { captured }
}

final class FakeFullscreenSource: FullscreenSource {
    var isFullscreen = false
    var bundleId: String?

    func reading(exceptions: Set<String>) -> FullscreenReading {
        if let bundleId, exceptions.contains(bundleId) {
            return FullscreenReading(isFullscreen: false, bundleId: bundleId)
        }
        return FullscreenReading(isFullscreen: isFullscreen, bundleId: bundleId)
    }
}

/// The events the debug panel's injector buttons send. Kept as one list so the panel, the tests
/// and the documentation cannot drift apart.
enum SignalInjector: String, CaseIterable, Identifiable {
    case idle
    case sleep
    case wake
    case lock
    case unlock
    case micOn
    case micOff
    case captureOn
    case captureOff
    case fullscreenOn
    case fullscreenOff
    case fireFullBreak
    case fireMicro
    case simulateFourHourGap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle: return "Idle 200 s"
        case .sleep: return "Sleep"
        case .wake: return "Wake"
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .micOn: return "Mic on"
        case .micOff: return "Mic off"
        case .captureOn: return "Capture on"
        case .captureOff: return "Capture off"
        case .fullscreenOn: return "Fullscreen on"
        case .fullscreenOff: return "Fullscreen off"
        case .fireFullBreak: return "Fire full break now"
        case .fireMicro: return "Fire micro now"
        case .simulateFourHourGap: return "Simulate 4 h gap"
        }
    }

    /// The event this injector sends. `fireMicro` has no event of its own — the coordinator
    /// re-anchors the micro-break instead — so it is the one case that returns nil.
    func event(now: Date) -> SchedulerEvent? {
        powerEvent ?? suppressionEvent
    }

    /// Idle, sleep, wake, lock, unlock and the two "do it now" shortcuts.
    private var powerEvent: SchedulerEvent? {
        switch self {
        case .idle: return .idle(seconds: 200)
        case .sleep: return .sleep
        case .wake: return .wake(gapSeconds: 120)
        case .lock: return .lock
        case .unlock: return .unlock(gapSeconds: 15)
        case .fireFullBreak: return .userTakeBreakNow
        case .simulateFourHourGap: return .wake(gapSeconds: 4 * 3600)
        default: return nil
        }
    }

    /// The three suppression signals, on and off.
    private var suppressionEvent: SchedulerEvent? {
        switch self {
        case .micOn: return .signals(SignalSnapshot(microphoneActive: true))
        case .captureOn: return .signals(SignalSnapshot(screenCaptureActive: true))
        case .fullscreenOn: return .signals(SignalSnapshot(fullscreenActive: true))
        case .micOff, .captureOff, .fullscreenOff: return .signals(.quiet)
        default: return nil
        }
    }
}
