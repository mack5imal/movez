import AppKit

/// The menu-bar glyph: a small ring whose filled arc is the fraction of the sitting bout already
/// spent, so the time to the next break is legible without opening anything.
///
/// It is a template image, so it follows the menu bar's own appearance — light text on a dark
/// bar, dark on a light one — rather than insisting on the app's palette in the one place on
/// screen that belongs to the system.
enum MenuBarIcon {
    /// The handoff's 12 px ring.
    static let pointSize: CGFloat = 12
    static let strokeRatio: CGFloat = 1.2 / 12
    /// Off hours the ring is still there, just quieter.
    static let offHoursAlpha: CGFloat = 0.55
    /// The unspent part of the ring, under the filled arc.
    static let trackAlpha: CGFloat = 0.3
    static let pausedAlpha: CGFloat = 0.75

    static func image(for state: MenuBarState, size: CGFloat = pointSize) -> NSImage {
        image(mode: state.mode, fraction: state.elapsedFraction, size: size)
    }

    static func image(mode: MenuBarState.Mode, fraction: Double, size: CGFloat = pointSize) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(mode: mode, fraction: fraction, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The alpha the ring is drawn at, which is what the off-hours criterion is about.
    static func ringAlpha(for mode: MenuBarState.Mode) -> CGFloat {
        switch mode {
        case .sitting: return trackAlpha
        case .paused: return pausedAlpha
        case .offHours: return offHoursAlpha
        }
    }

    private static func draw(mode: MenuBarState.Mode, fraction: Double, in rect: NSRect) {
        let stroke = max(1, rect.width * strokeRatio)
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: stroke / 2, dy: stroke / 2))
        ring.lineWidth = stroke
        NSColor.black.withAlphaComponent(ringAlpha(for: mode)).setStroke()

        if mode == .paused {
            var dashes: [CGFloat] = [stroke * 2, stroke * 2]
            ring.setLineDash(&dashes, count: dashes.count, phase: 0)
        }
        ring.stroke()

        guard mode == .sitting else { return }
        drawArc(fraction: fraction, in: rect, stroke: stroke)
    }

    /// The spent arc, from twelve o'clock, clockwise — the same direction every ring in movez
    /// drains.
    private static func drawArc(fraction: Double, in rect: NSRect, stroke: CGFloat) {
        let spent = max(0, min(1, fraction))
        guard spent > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: (rect.width - stroke) / 2,
            startAngle: 90,
            endAngle: 90 - 360 * spent,
            clockwise: true
        )
        arc.lineWidth = stroke
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
    }
}
