import Foundation

/// Everything that can move the scheduler. The coordinator drives ticks and input; the monitors
/// drive signals; the UI drives the user actions.
enum SchedulerEvent: Equatable {
    case tick
    case input(lastEventAgeSeconds: Int)

    // User actions — menu bar
    case userTakeBreakNow
    case userMakeDueIn(seconds: Int)
    case userPause(seconds: Int?)
    case userResume
    case userExtendPause(seconds: Int)
    case userStartSession
    case userEndSession

    // User actions — heads-up and overlay
    case userStartNow
    case userSnooze
    case userSkip
    case userNextBlock
    case userDone(completedBlocks: Int, totalBlocks: Int, elapsed: Int)
    case breakEnded(completedBlocks: Int, totalBlocks: Int, elapsed: Int)
    /// The overlay was left paused for its limit. A snooze, even with none left.
    case overlayPauseExpired

    // User actions — micro
    case userMicroStartNow
    case userMicroSnooze
    case userMicroSkip
    case microEnded

    // System signals
    case idle(seconds: Int)
    case sleep
    case wake(gapSeconds: Int)
    case lock
    case unlock(gapSeconds: Int)
    case gapDetected(seconds: Int)
    case signals(SignalSnapshot)
    case focusFilter(paused: Bool)

    // Settings and toasts
    case settingsChanged(SchedulerConfig)
    case toastReverse(ToastReversal)
}

/// The two reversible credits the away toast offers.
enum ToastReversal: String, Codable, Equatable {
    /// "I was sitting" after a credited full break — restore the interval that was running.
    case wasSittingAfterFullCredit
    /// "I was sitting" after a micro credit — restore the paused countdown.
    case wasSittingAfterMicroCredit
}
