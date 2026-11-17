import SwiftUI

/// The mode control: a `SegmentedControl` whose segments are each mode's badge, glyph and name.
///
/// Settings always shows every name. The dropdown is narrower, so once there are more than two
/// modes its inactive segments collapse to glyph-only buttons, each still named for VoiceOver and
/// in its tooltip.
struct ModeSegmentedControl: View {
    enum Variant {
        case settings
        case dropdown
    }

    var definitions: [ModeDefinition]
    /// The selected definition's id.
    @Binding var selection: String
    var variant: Variant = .settings

    /// A collapsed segment's width.
    static let collapsedWidth: CGFloat = 36

    /// Whether an inactive segment shows its glyph alone.
    static func collapsesInactive(_ variant: Variant, modeCount: Int) -> Bool {
        variant == .dropdown && modeCount > 2
    }

    /// What VoiceOver reads for a segment: the mode's name, which matters most when the segment
    /// has collapsed to its glyph and draws no words at all.
    static func announcement(for definition: ModeDefinition) -> String { definition.displayName }

    var body: some View {
        let collapses = Self.collapsesInactive(variant, modeCount: definitions.count)
        HStack(spacing: variant == .dropdown ? 2 : 0) {
            ForEach(definitions, id: \.id) { definition in
                segment(definition, collapsed: collapses && definition.id != selection)
            }
        }
        .padding(3)
        .background(Capsule().fill(Tokens.accentTintSegmented.color))
    }

    private func segment(_ definition: ModeDefinition, collapsed: Bool) -> some View {
        let selected = definition.id == selection
        let color = selected ? Tokens.ink : Tokens.text2
        return Button {
            selection = definition.id
        } label: {
            ModeBadge(
                definition: definition,
                size: variant == .dropdown ? .dropdown : .settings,
                label: collapsed ? .glyphOnly : .name,
                style: MovezType.segment,
                textColor: color,
                glyphColor: color
            )
            .padding(.horizontal, collapsed ? 0 : (variant == .dropdown ? 8 : 14))
            .padding(.vertical, 6)
            .frame(width: collapsed ? Self.collapsedWidth : nil)
            // The dropdown's row spans the menu, so its named segments share the width rather
            // than huddling at the leading edge.
            .frame(maxWidth: variant == .dropdown && !collapsed ? .infinity : nil)
            .background(Capsule().fill(selected ? Tokens.accent.color : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(definition.displayName)
        .accessibilityLabel(Self.announcement(for: definition))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
