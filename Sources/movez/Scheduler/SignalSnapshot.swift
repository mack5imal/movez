import Foundation

/// One reading of every system signal the scheduler cares about.
///
/// The monitors that fill this in arrive later; the scheduler only ever sees the struct, which is
/// what lets every interruption rule be tested with fakes.
struct SignalSnapshot: Codable, Equatable, Hashable {
    var idleSeconds: Int = 0
    var microphoneActive: Bool = false
    var screenCaptureActive: Bool = false
    var fullscreenActive: Bool = false
    var screenLocked: Bool = false
    var displaySleeping: Bool = false
    /// The frontmost app when the reading was taken, for the fullscreen exceptions list.
    var frontmostBundleId: String?

    /// True when any suppression signal is raised.
    var suppressing: Bool { microphoneActive || screenCaptureActive || fullscreenActive }

    /// Which signal to blame, for the deferred-break badge.
    var reason: SuppressionReason? {
        if microphoneActive { return .microphone }
        if screenCaptureActive { return .screenCapture }
        if fullscreenActive { return .fullscreen }
        return nil
    }

    static let quiet = SignalSnapshot()
}

/// Why a break was held back, phrased the way the heads-up badge says it.
enum SuppressionReason: String, Codable, Equatable, CaseIterable {
    case microphone
    case screenCapture
    case fullscreen

    /// "break waited for your call"
    var phrase: String {
        switch self {
        case .microphone: return "your call"
        case .screenCapture: return "your screen share"
        case .fullscreen: return "your fullscreen app"
        }
    }
}
