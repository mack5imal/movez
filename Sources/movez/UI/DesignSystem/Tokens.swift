import AppKit
import SwiftUI

/// A colour from the handoff, kept as components so tests can assert the exact values rather than
/// trusting a hex literal that has been retyped four times.
struct MovezColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// 0–255 components, which is how the handoff writes the rgba() colours.
    struct Components: Equatable {
        var red: Int
        var green: Int
        var blue: Int
    }

    var rgb255: Components {
        Components(
            red: Int((red * 255).rounded()),
            green: Int((green * 255).rounded()),
            blue: Int((blue * 255).rounded())
        )
    }

    var hexString: String {
        let components = rgb255
        return String(format: "#%02x%02x%02x", components.red, components.green, components.blue)
    }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func opacity(_ alpha: Double) -> MovezColor {
        MovezColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A shadow from the handoff.
struct MovezShadow: Equatable {
    var radius: CGFloat
    var offsetY: CGFloat
    var opacity: Double

    /// The handoff writes blur radius; SwiftUI's `radius` is roughly half of a CSS blur.
    init(cssBlur: CGFloat, offsetY: CGFloat, opacity: Double) {
        radius = cssBlur / 2
        self.offsetY = offsetY
        self.opacity = opacity
    }
}

/// Every colour, radius and shadow in movez, taken verbatim from the design handoff.
enum Tokens {
    // MARK: - Colours

    static let ink = MovezColor(hex: 0x0816_1F)
    static let accent = MovezColor(hex: 0x7FC8_B7)
    static let text = MovezColor(hex: 0xE6F1_EE)
    static let text2 = MovezColor(hex: 0xA9C3_C0)
    static let text3 = MovezColor(hex: 0x5A7A_86)
    static let warn = MovezColor(hex: 0xE2A4_5F)

    /// The panel fill at its three weights, plus the solid settings window.
    static let panel = MovezColor(red: 18 / 255, green: 42 / 255, blue: 58 / 255, alpha: 0.92)
    static let panelSmall = panel.opacity(0.94)
    static let panelMenu = panel.opacity(0.96)
    static let panelSolid = MovezColor(hex: 0x1228_3A)

    static let panelBorder = accent.opacity(0.28)
    static let accentTint = accent.opacity(0.14)
    static let accentTintSegmented = accent.opacity(0.12)
    static let accentTintBadge = accent.opacity(0.10)
    static let secondaryBorder = accent.opacity(0.35)

    static let rule = accent.opacity(0.18)
    static let ruleInactive = accent.opacity(0.25)
    static let ruleSettings = accent.opacity(0.14)

    /// The screen dim behind the overlay, and the lighter dim of the end state.
    static let dim = MovezColor(red: 8 / 255, green: 22 / 255, blue: 34 / 255, alpha: 0.86)
    static let dimEnd = dim.opacity(0.78)

    /// The unfilled part of a timer ring, drawn on the accent disc.
    static let ringTrack = ink.opacity(0.15)
    static let toggleOffTrack = MovezColor(red: 1, green: 1, blue: 1, alpha: 0.2)
    static let emptyRing = accent.opacity(0.25)

    /// The backdrop blur behind the overlay dim, in points.
    static let backdropBlur: CGFloat = 24

    // MARK: - Radii

    enum Radius {
        static let overlay: CGFloat = 36
        static let panel: CGFloat = 20
        static let toast: CGFloat = 16
        static let menu: CGFloat = 12
        static let row: CGFloat = 7
        static let settings: CGFloat = 12
        static let pill: CGFloat = 999
        static let select: CGFloat = 8
        static let badge: CGFloat = 10
    }

    // MARK: - Shadows

    enum Shadow {
        static let overlay = MovezShadow(cssBlur: 100, offsetY: 40, opacity: 0.5)
        static let panel = MovezShadow(cssBlur: 60, offsetY: 24, opacity: 0.45)
        static let menu = MovezShadow(cssBlur: 50, offsetY: 18, opacity: 0.45)
        static let disc = MovezShadow(cssBlur: 60, offsetY: 30, opacity: 0.5)
    }

    // MARK: - Metrics

    enum Metric {
        static let overlayCard = CGSize(width: 1000, height: 660)
        static let overlayDisc: CGFloat = 300
        static let panelWidth: CGFloat = 400
        static let panelWidthDeferred: CGFloat = 420
        static let panelDisc: CGFloat = 64
        static let toastWidth: CGFloat = 380
        static let menuWidth: CGFloat = 264
        static let menuDisc: CGFloat = 40
        static let settings = CGSize(width: 760, height: 700)
        static let togglesize = CGSize(width: 38, height: 22)
        static let stripGap: CGFloat = 16
        static let stripRule: CGFloat = 3
        static let overlayRingStroke: CGFloat = 6
        static let panelRingStroke: CGFloat = 2.5
    }
}

extension View {
    /// Applies one of the handoff's shadows.
    func movezShadow(_ shadow: MovezShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.offsetY)
    }
}
