import AppKit

/// The menu-bar icon: an 18 pt circle with the current mode's glyph inside. In a sitting bout the
/// circle's spent arc is the fraction of the bout already gone, so the time to the next break is
/// legible without opening anything.
///
/// It is a template image, so it follows the menu bar's own appearance — light on a dark bar, dark
/// on a light one — rather than insisting on the app's palette in the one place on screen that
/// belongs to the system. Every mode draws the same circle; modes differ by glyph only, and the
/// glyph comes from the mode's definition.
enum MenuBarIcon {
    /// The full status-item height.
    static let pointSize: CGFloat = Tokens.Metric.menuBarIcon
    /// The design's measurements at 18 pt; everything scales with the drawn size.
    static let ringRadius: CGFloat = 8
    static let ringStroke: CGFloat = 1.6
    static let glyphSize: CGFloat = 10
    static let glyphStroke: CGFloat = 1.1
    /// The paused ring's dash and gap, in hundredths of the circle's length.
    static let pausedDash: (dash: CGFloat, gap: CGFloat) = (6, 5)

    static func image(for state: MenuBarState, size: CGFloat = pointSize) -> NSImage {
        image(
            mode: state.mode,
            fraction: state.elapsedFraction,
            glyph: ModeGlyph.menuBar(for: state.breakMode.definition),
            size: size
        )
    }

    static func image(
        mode: MenuBarState.Mode,
        fraction: Double,
        glyph: ModeGlyph? = ModeGlyph.menuBar(for: BreakMode.fallback.definition),
        size: CGFloat = pointSize
    ) -> NSImage {
        // Flipped, so the glyph's vectors and the arc are drawn in the design's y-down coordinates.
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(mode: mode, fraction: fraction, glyph: glyph, in: rect, context: context)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The alpha the whole ring is drawn at before any progress goes on top.
    static func ringAlpha(for mode: MenuBarState.Mode) -> CGFloat {
        switch mode {
        case .sitting: return Tokens.iconTrack.alpha
        case .paused: return Tokens.iconPaused.alpha
        case .offHours: return Tokens.iconOffhours.alpha
        case .away: return Tokens.iconAway.alpha
        }
    }

    /// Off hours the glyph goes quiet with the ring; otherwise it is the one thing always at full
    /// strength.
    static func glyphAlpha(for mode: MenuBarState.Mode) -> CGFloat {
        mode == .offHours ? Tokens.iconOffhours.alpha : 1
    }

    /// Only a sitting bout has progress to show.
    static func showsProgress(_ mode: MenuBarState.Mode) -> Bool { mode == .sitting }

    /// The dash pattern of the ring at `size`, nil for a solid ring. Only a pause dashes it.
    static func dashPattern(for mode: MenuBarState.Mode, size: CGFloat = pointSize) -> [CGFloat]? {
        guard mode == .paused else { return nil }
        let unit = 2 * CGFloat.pi * ringRadius * size / pointSize / 100
        return [pausedDash.dash * unit, pausedDash.gap * unit]
    }

    private static func draw(mode: MenuBarState.Mode, fraction: Double, glyph: ModeGlyph?, in rect: NSRect, context: CGContext) {
        let scale = rect.width / pointSize
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = ringRadius * scale
        let stroke = ringStroke * scale
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.setLineWidth(stroke)
        context.setStrokeColor(Tokens.templateInk.opacity(ringAlpha(for: mode)).nsColor.cgColor)
        if let dashes = dashPattern(for: mode, size: rect.width) {
            context.setLineDash(phase: 0, lengths: dashes)
        }
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        if showsProgress(mode) {
            drawArc(fraction: fraction, center: center, radius: radius, stroke: stroke, context: context)
        }

        guard let glyph else { return }
        let side = glyphSize * scale
        let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        context.setLineWidth(glyphStroke * scale)
        context.setStrokeColor(Tokens.templateInk.opacity(glyphAlpha(for: mode)).nsColor.cgColor)
        context.addPath(glyph.cgPath(in: box))
        context.strokePath()
    }

    /// The spent arc, from twelve o'clock, clockwise — the same direction every ring in movez
    /// drains. In y-down coordinates a growing angle runs clockwise.
    private static func drawArc(fraction: Double, center: CGPoint, radius: CGFloat, stroke: CGFloat, context: CGContext) {
        let spent = max(0, min(1, fraction))
        guard spent > 0 else { return }
        let arc = CGMutablePath()
        arc.addRelativeArc(center: center, radius: radius, startAngle: -.pi / 2, delta: 2 * .pi * CGFloat(spent))
        context.setLineWidth(stroke)
        context.setStrokeColor(Tokens.templateInk.nsColor.cgColor)
        context.addPath(arc)
        context.strokePath()
    }
}
