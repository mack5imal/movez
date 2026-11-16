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
        return Self.reading(
            bundleId: frontmost.bundleIdentifier,
            ownBundleId: ownBundleId,
            exceptions: exceptions,
            windows: { Self.frontmostWindowBounds(pid: frontmost.processIdentifier) },
            screens: Self.screens
        )
    }

    /// One display, in Core Graphics coordinates (origin top-left), with the height of the strip
    /// a camera housing takes off its top.
    struct Screen: Equatable {
        var frame: CGRect
        /// `NSScreen.safeAreaInsets.top`: 32 pt on a notched MacBook panel, 0 everywhere else.
        var topInset: CGFloat = 0

        /// The rects a fullscreen window on this display can occupy. A notched panel has two:
        /// macOS places native fullscreen content inside the safe area, below the camera housing,
        /// but an app set to draw over the notch fills the whole frame.
        var fullscreenRects: [CGRect] {
            guard topInset > 0 else { return [frame] }
            let safeArea = CGRect(
                x: frame.minX,
                y: frame.minY + topInset,
                width: frame.width,
                height: frame.height - topInset
            )
            return [frame, safeArea]
        }
    }

    /// The decision on its own, so it can be tested without a window server. Movez itself and
    /// the user's exceptions are answered before the window list is read, which is the expensive
    /// part, so the window and screen lookups are passed in lazily.
    static func reading(
        bundleId: String?,
        ownBundleId: String?,
        exceptions: Set<String>,
        windows: () -> [CGRect],
        screens: () -> [Screen]
    ) -> FullscreenReading {
        if let bundleId, bundleId == ownBundleId || exceptions.contains(bundleId) {
            return FullscreenReading(isFullscreen: false, bundleId: bundleId)
        }
        let displays = screens()
        let fullscreen = windows().contains { isFullscreen(windowBounds: $0, screens: displays) }
        return FullscreenReading(isFullscreen: fullscreen, bundleId: bundleId)
    }

    /// True when the window covers any screen entirely, or a notched screen's safe area, within a
    /// point.
    ///
    /// The safe area costs nothing in false positives: a zoomed window on a notched panel starts
    /// under the menu bar, which is taller than the camera housing, so it matches neither rect.
    static func isFullscreen(windowBounds: CGRect, screens: [Screen]) -> Bool {
        screens.flatMap(\.fullscreenRects).contains { rect in
            abs(windowBounds.width - rect.width) <= tolerance
                && abs(windowBounds.height - rect.height) <= tolerance
                && abs(windowBounds.minX - rect.minX) <= tolerance
                && abs(windowBounds.minY - rect.minY) <= tolerance
        }
    }

    /// Every display in Core Graphics coordinates (origin top-left), which is what the window
    /// list reports in, with its camera-housing inset.
    static func screens() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let flipHeight = primary.frame.maxY
        return NSScreen.screens.map { screen in
            Screen(
                frame: CGRect(
                    x: screen.frame.minX,
                    y: flipHeight - screen.frame.maxY,
                    width: screen.frame.width,
                    height: screen.frame.height
                ),
                topInset: screen.safeAreaInsets.top
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
