import Foundation

/// The scheduler never calls `Date()` directly. Everything it does is a function of a clock it is
/// handed, which is what lets a 55-minute interval be exercised in 55 milliseconds and what makes
/// the debug time-scale possible.
protocol Clock: AnyObject {
    var now: Date { get }
}

/// Wall-clock time, optionally running fast for debugging.
///
/// Changing the scale re-bases the origin, so time never jumps backwards or forwards when the
/// user flips from 1× to 60× mid-session.
final class SystemClock: Clock {
    private var scaledOrigin: Date
    private var realOrigin: Date

    var timeScale: Double {
        didSet {
            guard timeScale != oldValue else { return }
            rebase(from: oldValue)
        }
    }

    init(timeScale: Double = 1) {
        self.timeScale = timeScale
        let now = Date()
        scaledOrigin = now
        realOrigin = now
    }

    var now: Date {
        scaledOrigin.addingTimeInterval(Date().timeIntervalSince(realOrigin) * timeScale)
    }

    /// Re-anchors the origin using the scale that was in force, so scaled time is continuous
    /// across the change instead of jumping backwards or forwards.
    private func rebase(from previousScale: Double) {
        scaledOrigin = scaledOrigin.addingTimeInterval(Date().timeIntervalSince(realOrigin) * previousScale)
        realOrigin = Date()
    }
}

/// A clock the tests move by hand.
final class ManualClock: Clock {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_767_225_600)) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    func set(_ date: Date) {
        now = date
    }
}
