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

    static let quiet = SignalSnapshot()
}
