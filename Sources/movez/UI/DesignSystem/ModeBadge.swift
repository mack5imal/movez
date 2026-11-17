import SwiftUI

/// The mode badge: the mode's glyph in accent, then its name or eyebrow in the surrounding text
/// style.
///
/// Every surface that names a break shows one, so the mode is legible by its glyph and its word
/// rather than by colour: the glyph is accent in every mode and nothing about the badge changes
/// colour between modes. Its glyph and words come from the `ModeDefinition`, so a mode added later
/// gets a badge by being defined.
struct ModeBadge: View {
    /// The design's five placements, each with its own glyph size and gap.
    enum Size: CaseIterable {
        case overlay
        case panel
        case dropdown
        case settings
        case weightGuidance

        var glyph: CGFloat {
            switch self {
            case .overlay: return 22
            case .panel: return 13
            case .dropdown, .settings: return 14
            case .weightGuidance: return 16
            }
        }

        var gap: CGFloat {
            switch self {
            case .overlay: return 10
            case .panel, .dropdown, .settings: return 6
            case .weightGuidance: return 8
            }
        }

        /// The text style the badge takes when the caller does not pass the surrounding one.
        var defaultStyle: MovezTextStyle {
            switch self {
            case .overlay: return MovezType.eyebrowOverlay
            case .panel: return MovezType.eyebrowPanel
            case .dropdown, .settings: return MovezType.segment
            case .weightGuidance: return MovezType.guidanceLead
            }
        }
    }

    /// What the badge says after its glyph.
    enum Label: Equatable {
        /// "STRENGTH BREAK"
        case breakEyebrow
        /// "STRENGTH MICRO-BREAK"
        case microBreakEyebrow
        /// "Strength"
        case name
        /// The glyph alone, for a collapsed mode button.
        case glyphOnly
    }

    let definition: ModeDefinition
    var size: Size = .panel
    var label: Label = .breakEyebrow
    var style: MovezTextStyle?
    var textColor: MovezColor = Tokens.accent
    /// Accent everywhere except on a selected segment, where the glyph sits on the accent fill.
    var glyphColor: MovezColor = Tokens.accent

    /// The glyph the definition names.
    var glyph: ModeGlyph? { ModeGlyph.badge(for: definition) }

    /// The words the badge shows, exactly as rendered.
    var text: String {
        Self.text(for: definition, label: label, inCapitals: (style ?? size.defaultStyle).uppercase)
    }

    /// The badge's words. In a capitals style the name is the definition's eyebrow word, which is
    /// already cased as the design writes it, because uppercasing the display name would turn
    /// "100s" into "100S".
    static func text(for definition: ModeDefinition, label: Label, inCapitals: Bool = false) -> String {
        switch label {
        case .breakEyebrow: return definition.breakEyebrow
        case .microBreakEyebrow: return definition.microBreakEyebrow
        case .name: return inCapitals ? definition.eyebrowWord : definition.displayName
        case .glyphOnly: return ""
        }
    }

    /// The style the text is drawn in. The style's own uppercasing never touches a mode word: an
    /// eyebrow and a name in capitals are already cased, and that is what keeps the lowercase "s"
    /// in "100s BREAK" and "100s".
    var resolvedStyle: MovezTextStyle {
        var resolved = style ?? size.defaultStyle
        if label != .glyphOnly {
            resolved.uppercase = false
        }
        return resolved
    }

    var body: some View {
        HStack(alignment: .center, spacing: size.gap) {
            ModeGlyphView(glyph: glyph, size: size.glyph, color: glyphColor)
            if label != .glyphOnly {
                MovezText(text, resolvedStyle, color: textColor, lineLimit: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label == .glyphOnly ? definition.displayName : text)
    }
}
