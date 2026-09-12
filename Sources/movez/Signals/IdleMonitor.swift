import CoreGraphics
import Foundation

/// Idle time from the window server.
///
/// `CGEventSource.secondsSinceLastEventType` needs no Accessibility permission, which is why the
/// brief picked it: movez should not ask for the right to read the user's keystrokes just to
/// notice they went to make coffee.
final class IdleMonitor: IdleSource {
    /// `kCGAnyInputEventType`, which Swift does not import as a case.
    private static let anyInputEventType = CGEventType(rawValue: ~0)

    func idleSeconds() -> TimeInterval {
        guard let eventType = Self.anyInputEventType else { return 0 }
        let combined = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
        // A long drag registers as one event, so sample it separately or a slow drag reads as idle.
        let drag = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged)
        return max(0, min(combined, drag))
    }
}
