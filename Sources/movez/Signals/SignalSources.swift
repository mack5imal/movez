import Foundation

/// The four impure readings the scheduler depends on, each behind a protocol so the whole
/// suppression and idle story can be exercised with fakes.
protocol IdleSource: AnyObject {
    /// Seconds since the last keyboard, mouse or trackpad event.
    func idleSeconds() -> TimeInterval
}

protocol MicSource: AnyObject {
    /// True when the default input device is running somewhere — a call, a recording, anything.
    func isInUse() -> Bool
}

protocol CaptureSource: AnyObject {
    /// True when something that looks like a screen recorder or share is running.
    func isCaptured() -> Bool
}

/// The frontmost app, and whether it fills a whole screen.
struct FullscreenReading: Equatable {
    var isFullscreen: Bool
    var bundleId: String?

    static let none = FullscreenReading(isFullscreen: false, bundleId: nil)
}

protocol FullscreenSource: AnyObject {
    func reading(exceptions: Set<String>) -> FullscreenReading
}
