import Foundation
@testable import movez

/// Settable stand-ins for the four system sources, for the tests. The debug injectors in the
/// settings window do not use these: they hold values in `SignalOverrides`, which the real
/// sources are wrapped in.
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
