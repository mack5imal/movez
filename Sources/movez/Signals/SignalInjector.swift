import Foundation

/// The events the debug panel's injector buttons send. Kept as one list so the panel, the tests
/// and the documentation cannot drift apart.
enum SignalInjector: String, CaseIterable, Identifiable {
    case idleFour
    case idleSeven
    case sleep
    case wake
    case wakeFiveHours
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
        case .idleFour: return "Idle 4 min"
        case .idleSeven: return "Idle 7 min"
        case .sleep: return "Sleep"
        case .wake: return "Wake +2 min"
        case .wakeFiveHours: return "Wake +5 h"
        case .lock: return "Lock"
        case .unlock: return "Unlock +15 s"
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
    ///
    /// `holds` is what the panel is holding on, so a suppression event carries every held signal
    /// and not only this one.
    func event(now: Date, holding holds: SignalOverrides) -> SchedulerEvent? {
        powerEvent ?? suppressionEvent(holding: holds)
    }

    /// Idle, sleep, wake, lock, unlock and the two "do it now" shortcuts.
    private var powerEvent: SchedulerEvent? {
        switch self {
        case .idleFour: return .idle(seconds: 4 * 60)
        case .idleSeven: return .idle(seconds: 7 * 60)
        case .sleep: return .sleep
        case .wake: return .wake(gapSeconds: 120)
        case .wakeFiveHours: return .wake(gapSeconds: 5 * 3600)
        case .lock: return .lock
        case .unlock: return .unlock(gapSeconds: 15)
        case .fireFullBreak: return .userTakeBreakNow
        case .simulateFourHourGap: return .wake(gapSeconds: 4 * 3600)
        default: return nil
        }
    }

    /// The override this injector holds until its opposite is pressed. A held signal survives
    /// every poll in between, which is the whole point of injecting one.
    ///
    /// Idle is deliberately not held: being away is a stretch of time that ends when the user
    /// types, not a switch that stays flipped.
    var hold: SignalHold? {
        switch self {
        case .micOn: return .mic(true)
        case .micOff: return .mic(false)
        case .captureOn: return .capture(true)
        case .captureOff: return .capture(false)
        case .fullscreenOn: return .fullscreen(true)
        case .fullscreenOff: return .fullscreen(false)
        default: return nil
        }
    }

    /// True for the buttons that drive the scheduler rather than a signal.
    var isSchedulerAction: Bool {
        switch self {
        case .fireFullBreak, .fireMicro, .simulateFourHourGap: return true
        default: return false
        }
    }

    /// The three suppression signals, on and off. The snapshot is built from every held signal
    /// with this injector's own one set as it says: "Mic off" used to send a quiet snapshot, which
    /// ended a suppression that a capture still held on should have kept.
    private func suppressionEvent(holding holds: SignalOverrides) -> SchedulerEvent? {
        guard let hold else { return nil }
        var snapshot = SignalSnapshot(
            microphoneActive: holds.micInUse == true,
            screenCaptureActive: holds.captured == true,
            fullscreenActive: holds.fullscreen == true
        )
        switch hold {
        case .mic(let on): snapshot.microphoneActive = on
        case .capture(let on): snapshot.screenCaptureActive = on
        case .fullscreen(let on): snapshot.fullscreenActive = on
        }
        return .signals(snapshot)
    }
}

/// What an injector holds in front of the real sources.
enum SignalHold: Equatable {
    case mic(Bool)
    case capture(Bool)
    case fullscreen(Bool)

    /// Applies the hold, or lifts it when the signal is switched back off.
    func apply(to overrides: SignalOverrides) {
        switch self {
        case .mic(let on): overrides.micInUse = on ? true : nil
        case .capture(let on): overrides.captured = on ? true : nil
        case .fullscreen(let on): overrides.fullscreen = on ? true : nil
        }
    }
}
