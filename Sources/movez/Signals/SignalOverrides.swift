import Foundation

/// Debug values held in front of the real system sources.
///
/// An injected signal has to behave like the real one or it proves nothing: "mic on" must stay on
/// until "mic off", through every poll in between, so suppression, the deferral and the grace
/// period all run exactly as they would during an actual call. A one-shot event would be undone
/// by the very next sample.
final class SignalOverrides {
    var idleSeconds: TimeInterval?
    var micInUse: Bool?
    var captured: Bool?
    var fullscreen: Bool?

    var isActive: Bool {
        idleSeconds != nil || micInUse != nil || captured != nil || fullscreen != nil
    }

    func clear() {
        idleSeconds = nil
        micInUse = nil
        captured = nil
        fullscreen = nil
    }

    /// "mic=on capture=off" — what the inspector prints, or "none".
    var summary: String {
        var parts: [String] = []
        if let idleSeconds { parts.append("idle=\(Int(idleSeconds)) s") }
        if let micInUse { parts.append("mic=\(micInUse ? "on" : "off")") }
        if let captured { parts.append("capture=\(captured ? "on" : "off")") }
        if let fullscreen { parts.append("fullscreen=\(fullscreen ? "on" : "off")") }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }
}

/// Each real source, with the override in front of it.
final class OverridingIdleSource: IdleSource {
    private let base: IdleSource
    private let overrides: SignalOverrides

    init(_ base: IdleSource, overrides: SignalOverrides) {
        self.base = base
        self.overrides = overrides
    }

    func idleSeconds() -> TimeInterval { overrides.idleSeconds ?? base.idleSeconds() }
}

final class OverridingMicSource: MicSource {
    private let base: MicSource
    private let overrides: SignalOverrides

    init(_ base: MicSource, overrides: SignalOverrides) {
        self.base = base
        self.overrides = overrides
    }

    func isInUse() -> Bool { overrides.micInUse ?? base.isInUse() }
}

final class OverridingCaptureSource: CaptureSource {
    private let base: CaptureSource
    private let overrides: SignalOverrides

    init(_ base: CaptureSource, overrides: SignalOverrides) {
        self.base = base
        self.overrides = overrides
    }

    func isCaptured() -> Bool { overrides.captured ?? base.isCaptured() }
}

final class OverridingFullscreenSource: FullscreenSource {
    private let base: FullscreenSource
    private let overrides: SignalOverrides

    init(_ base: FullscreenSource, overrides: SignalOverrides) {
        self.base = base
        self.overrides = overrides
    }

    func reading(exceptions: Set<String>) -> FullscreenReading {
        guard let fullscreen = overrides.fullscreen else { return base.reading(exceptions: exceptions) }
        return FullscreenReading(isFullscreen: fullscreen, bundleId: base.reading(exceptions: exceptions).bundleId)
    }
}
