import AppKit
import SwiftUI

/// One line of the handoff's type scale: size, weight, tracking in em, line height and case.
struct MovezTextStyle: Equatable {
    var size: CGFloat
    var weight: NSFont.Weight
    var trackingEm: CGFloat = 0
    var lineHeight: CGFloat = 1
    var uppercase: Bool = false

    var font: Font { MovezFont.manrope(size, weight: weight) }
    var nsFont: NSFont { MovezFont.nsFont(size, weight: weight) }
    /// The handoff writes tracking in em; SwiftUI wants points.
    var tracking: CGFloat { trackingEm * size }

    /// The handoff writes line height as a multiple of the font size, but SwiftUI's `lineSpacing`
    /// is the gap *between* line boxes. Subtracting the font's own line box is what makes a
    /// 28 px / 1.45 paragraph actually set at 1.45.
    ///
    /// Spacing can only be added, so a line height tighter than Manrope's own line box (about
    /// 1.37) cannot be drawn. The handoff's tighter values (1.05 to 1.3) are therefore written as 1,
    /// the font's natural line, and a test holds every style to 1 or at least the natural ratio
    /// (DECISIONS 85).
    var lineSpacing: CGFloat {
        guard lineHeight > 1 else { return 0 }
        let naturalLineBox = nsFont.ascender - nsFont.descender + nsFont.leading
        return max(0, size * lineHeight - naturalLineBox)
    }
}

/// The full type scale. Every surface pulls from here so no screen invents its own size.
enum MovezType {
    // Overlay
    static let eyebrowOverlay = MovezTextStyle(size: 18, weight: .semibold, trackingEm: 0.1, uppercase: true)
    static let overlayName = MovezTextStyle(size: 80, weight: .bold, trackingEm: -0.035)
    static let overlayNameSide = MovezTextStyle(size: 56, weight: .bold, trackingEm: -0.035)
    static let instruction = MovezTextStyle(size: 28, weight: .regular, lineHeight: 1.45)
    static let instructionSide = MovezTextStyle(size: 24, weight: .regular, lineHeight: 1.45)
    static let helperLink = MovezTextStyle(size: 18, weight: .semibold)
    static let discNumerals = MovezTextStyle(size: 84, weight: .semibold, trackingEm: -0.04)
    static let discLabel = MovezTextStyle(size: 16, weight: .bold, trackingEm: 0.12, uppercase: true)
    static let stripNumber = MovezTextStyle(size: 24, weight: .heavy)
    static let stripName = MovezTextStyle(size: 17, weight: .regular)
    static let endTitle = MovezTextStyle(size: 84, weight: .bold, trackingEm: -0.035)
    static let endBody = MovezTextStyle(size: 28, weight: .regular)
    static let backToWork = MovezTextStyle(size: 22, weight: .bold)
    static let sideToggle = MovezTextStyle(size: 30, weight: .bold)
    /// The movement name on a rep-based set, smaller than `overlayName` to make room for the meter.
    static let setName = MovezTextStyle(size: 56, weight: .bold, trackingEm: -0.03)
    static let setKicker = MovezTextStyle(size: 20, weight: .semibold)
    static let dose = MovezTextStyle(size: 28, weight: .bold, trackingEm: -0.015)
    static let doseModifier = MovezTextStyle(size: 20, weight: .semibold)
    static let repCounter = MovezTextStyle(size: 28, weight: .bold, trackingEm: -0.015)
    static let upNext = MovezTextStyle(size: 28, weight: .semibold)
    /// The compact SideToggle that sits at the end of the dose line.
    static let sidePillCompact = MovezTextStyle(size: 22, weight: .bold)

    // Panels
    static let eyebrowPanel = MovezTextStyle(size: 11, weight: .semibold, trackingEm: 0.1, uppercase: true)
    static let panelTitle = MovezTextStyle(size: 20, weight: .bold, trackingEm: -0.015)
    static let panelBody = MovezTextStyle(size: 13, weight: .regular, lineHeight: 1.45)
    static let panelDisc = MovezTextStyle(size: 17, weight: .bold)
    static let panelButton = MovezTextStyle(size: 13, weight: .semibold)
    static let badge = MovezTextStyle(size: 12.5, weight: .regular)
    /// The dose line in a micro panel, drawn in accent.
    static let panelDose = MovezTextStyle(size: 20, weight: .bold, trackingEm: -0.015)
    /// Weight guidance is an info badge that runs to several lines, so it sets a real line height,
    /// with its lead sentence in the heavier weight.
    static let guidance = MovezTextStyle(size: 12.5, weight: .regular, lineHeight: 1.45)
    static let guidanceLead = MovezTextStyle(size: 12.5, weight: .semibold, lineHeight: 1.45)
    static let toastTitle = MovezTextStyle(size: 14, weight: .bold)
    static let toastBody = MovezTextStyle(size: 12, weight: .regular)

    // Menu
    static let menuRow = MovezTextStyle(size: 13, weight: .medium)
    static let menuTitle = MovezTextStyle(size: 14, weight: .bold)
    static let menuSecondary = MovezTextStyle(size: 12, weight: .regular)
    static let menuDisc = MovezTextStyle(size: 14, weight: .bold)

    // Settings
    static let settingsRow = MovezTextStyle(size: 13, weight: .medium)
    static let sectionLabel = MovezTextStyle(size: 11, weight: .semibold, trackingEm: 0.1, uppercase: true)
    static let settingsTitle = MovezTextStyle(size: 13, weight: .bold)
    static let version = MovezTextStyle(size: 12, weight: .regular)
    static let segment = MovezTextStyle(size: 12, weight: .semibold)
    /// The sub-label under a Settings row label.
    static let settingsSub = MovezTextStyle(size: 12, weight: .regular, lineHeight: 1.4)

    /// Every style, for the gallery and for the test that checks they all resolve to Manrope.
    static let all: [(name: String, style: MovezTextStyle)] = [
        ("eyebrowOverlay", eyebrowOverlay), ("overlayName", overlayName), ("overlayNameSide", overlayNameSide),
        ("instruction", instruction), ("instructionSide", instructionSide), ("helperLink", helperLink),
        ("discNumerals", discNumerals), ("discLabel", discLabel), ("stripNumber", stripNumber),
        ("stripName", stripName), ("endTitle", endTitle), ("endBody", endBody),
        ("backToWork", backToWork),
        ("sideToggle", sideToggle), ("eyebrowPanel", eyebrowPanel), ("panelTitle", panelTitle),
        ("panelBody", panelBody), ("panelDisc", panelDisc), ("panelButton", panelButton),
        ("badge", badge), ("toastTitle", toastTitle), ("toastBody", toastBody),
        ("menuRow", menuRow), ("menuTitle", menuTitle), ("menuSecondary", menuSecondary),
        ("menuDisc", menuDisc), ("settingsRow", settingsRow), ("sectionLabel", sectionLabel),
        ("settingsTitle", settingsTitle), ("version", version), ("segment", segment),
        ("setName", setName), ("setKicker", setKicker), ("dose", dose), ("doseModifier", doseModifier),
        ("repCounter", repCounter), ("upNext", upNext), ("sidePillCompact", sidePillCompact),
        ("panelDose", panelDose), ("guidance", guidance), ("guidanceLead", guidanceLead),
        ("settingsSub", settingsSub)
    ]
}

extension View {
    /// Applies a type style's font, tracking and line spacing in one place.
    func movezType(_ style: MovezTextStyle) -> some View {
        self.font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

/// The app's clock, in one place.
///
/// "9:00", "14:02" — the overlay, the menu bar and the toast all show the same 24-hour time, and
/// the formatter is cached because building one is among the most expensive things Foundation
/// does and these are read on a per-second redraw path.
enum MovezClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    static func label(_ date: Date) -> String { formatter.string(from: date) }
}

/// Text in one of the house styles, in one of the house colours.
struct MovezText: View {
    let content: String
    let style: MovezTextStyle
    var color: MovezColor = Tokens.text
    var alignment: TextAlignment = .leading
    /// nil lets the text wrap onto as many lines as it needs.
    var lineLimit: Int?
    /// Below 1, text too long for its lines shrinks towards this fraction of its size instead of
    /// being cut off with an ellipsis.
    var minimumScaleFactor: CGFloat = 1

    init(
        _ content: String,
        _ style: MovezTextStyle,
        color: MovezColor = Tokens.text,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = nil,
        minimumScaleFactor: CGFloat = 1
    ) {
        self.content = content
        self.style = style
        self.color = color
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
    }

    var body: some View {
        Text(style.uppercase ? content.uppercased() : content)
            .movezType(style)
            .foregroundStyle(color.color)
            .multilineTextAlignment(alignment)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
    }
}
