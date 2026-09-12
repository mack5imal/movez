import AppKit
import CoreGraphics
import Foundation

/// Whether the frontmost app is filling a whole display — a presentation, a fullscreen video
/// call, a game.
///
/// The window-bounds comparison is a pure function so the tricky part is testable without a
/// screen.
final class FullscreenMonitor: FullscreenSource {
    /// How far a window's bounds may differ from the screen's and still count as fullscreen.
    static let tolerance: CGFloat = 1

    private let ownBundleId: String?

    init(ownBundleId: String? = Bundle.main.bundleIdentifier) {
        self.ownBundleId = ownBundleId
    }

    func reading(exceptions: Set<String>) -> FullscreenReading {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return .none }
        let bundleId = frontmost.bundleIdentifier

        if let bundleId, bundleId == ownBundleId || exceptions.contains(bundleId) {
            return FullscreenReading(isFullscreen: false, bundleId: bundleId)
        }

        let windows = Self.frontmostWindowBounds(pid: frontmost.processIdentifier)
        let screens = Self.screenFrames()
        let fullscreen = windows.contains { Self.isFullscreen(windowBounds: $0, screenFrames: screens) }
        return FullscreenReading(isFullscreen: fullscreen, bundleId: bundleId)
    }

    /// True when the window covers any screen entirely, within a point.
    static func isFullscreen(windowBounds: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { frame in
            abs(windowBounds.width - frame.width) <= tolerance
                && abs(windowBounds.height - frame.height) <= tolerance
                && abs(windowBounds.minX - frame.minX) <= tolerance
                && abs(windowBounds.minY - frame.minY) <= tolerance
        }
    }

    /// Screen frames in Core Graphics coordinates (origin top-left), which is what the window
    /// list reports in.
    static func screenFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        let flipHeight = primary.frame.maxY
        return NSScreen.screens.map { screen in
            CGRect(
                x: screen.frame.minX,
                y: flipHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
    }

    static func frontmostWindowBounds(pid: pid_t) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return rect
        }
    }
}
